import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import '../config/credentials_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/lat_lng.dart';
import '../utils/polyline_decoder.dart';

class FareService {
  static double _baseFare = 20.0; // Base fare in PHP
  static double _firstTwoKmFare = 20.0; // Fixed fare for first 2km
  static double _farePer500m = 10.0; // Fare per 500m after first 2km
  static double _minimumFare = 20.0; // Minimum fare in PHP
  static double _surgeMultiplier = 1.0;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Stream<DocumentSnapshot<Map<String, dynamic>>> get fareRulesStream {
    return _firestore.collection('settings').doc('fare_rules').snapshots();
  }

  static Future<void> loadFareRules() async {
    try {
      final doc = await _firestore.collection('settings').doc('fare_rules').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _baseFare = (data['baseFare'] ?? 20.0).toDouble();
        _firstTwoKmFare = (data['firstTwoKmFare'] ?? 20.0).toDouble();
        _farePer500m = (data['farePer500m'] ?? 10.0).toDouble();
        _minimumFare = (data['minimumFare'] ?? 20.0).toDouble();
        _surgeMultiplier = (data['surgeMultiplier'] ?? 1.0).toDouble();
      }
    } catch(e) {
      print('Failed to load fare rules, using defaults: $e');
    }
  }

  static Future<List<LatLng>> getRouteGeometry({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    bool includeTraffic = false,
  }) async {
    final routeData = await _getDirectionsMatrix(
      originLat,
      originLng,
      destLat,
      destLng,
      includeTraffic: includeTraffic,
    );
    return routeData['geometry'] as List<LatLng>? ?? [];
  }

  static Future<Map<String, dynamic>> calculateFareAndETA({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    double? driverLat,
    double? driverLng,
  }) async {
    try {
      // Load freshest fare rules from Admin DB before calculating
      await loadFareRules();

      // Calculate distance and duration using Mapbox Directions API
      final routeData = await _getDirectionsMatrix(
        pickupLat,
        pickupLng,
        dropoffLat,
        dropoffLng,
      );

      double distanceKm = routeData['distance'] / 1000; // Convert to km
      int durationMinutes = (routeData['duration'] / 60)
          .round(); // Convert to minutes

      // Calculate fare
      double fare = _calculateFare(distanceKm);

      // Calculate ETA if driver location is provided
      int? etaMinutes;
      if (driverLat != null && driverLng != null) {
        etaMinutes = await _calculateETA(
          driverLat,
          driverLng,
          pickupLat,
          pickupLng,
        );
      }

      return {
        'fare': fare,
        'distance': distanceKm,
        'duration': durationMinutes,
        'eta': etaMinutes,
        'routeGeometry': routeData['geometry'], // Include decoded route geometry
      };
    } catch (e) {
      print('Error calculating fare and ETA: $e');
      // Fallback to straight-line distance calculation
      return _calculateFallbackFareAndETA(
        pickupLat,
        pickupLng,
        dropoffLat,
        dropoffLng,
        driverLat,
        driverLng,
      );
    }
  }

  static Future<Map<String, dynamic>> _getDirectionsMatrix(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
    {bool includeTraffic = false,}
  ) async {
    final String accessToken = CredentialsConfig.mapboxAccessToken;
    final String profile = includeTraffic ? 'mapbox/driving-traffic' : 'mapbox/driving';
    final String url =
        'https://api.mapbox.com/directions/v5/$profile/$originLng,$originLat;$destLng,$destLat'
        '?access_token=$accessToken'
        '&geometries=geojson'
        '&steps=true' // Enable steps for better route accuracy
        '&overview=full'
        '&continue_straight=false' // Allow U-turns when necessary
        '&annotations=distance,duration' // Get detailed annotations
        '&exclude=ferry'; // Only exclude ferries, allow other road types

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['routes'].isNotEmpty) {
        final route = data['routes'][0];
        final legs = route['legs'][0];

        // Decode route geometry with higher precision
        final geometry = route['geometry'] as Map<String, dynamic>?;
        List<LatLng> decodedGeometry = [];
        
        if (geometry != null) {
          decodedGeometry = PolylineDecoder.decodeMapboxGeometry(geometry);
          
          // Ensure minimum point density for smooth routing
          if (decodedGeometry.length < 10) {
            // If route has too few points, interpolate more points
            decodedGeometry = _interpolateRoutePoints(decodedGeometry);
          }
        }

        return {
          'distance': legs['distance'].toDouble(), // in meters
          'duration': legs['duration'].toDouble(), // in seconds
          'geometry': decodedGeometry, // decoded route points
        };
      }
    }

    throw Exception('Failed to get Mapbox directions data');
  }

  // Helper method to interpolate more points for smoother routes
  static List<LatLng> _interpolateRoutePoints(List<LatLng> originalPoints) {
    if (originalPoints.length < 2) return originalPoints;
    
    List<LatLng> interpolatedPoints = [];
    
    for (int i = 0; i < originalPoints.length - 1; i++) {
      final start = originalPoints[i];
      final end = originalPoints[i + 1];
      
      interpolatedPoints.add(start);
      
      // Calculate distance between points
      final distance = Geolocator.distanceBetween(
        start.latitude, start.longitude,
        end.latitude, end.longitude,
      );
      
      // If points are far apart (>100m), add intermediate points
      if (distance > 100) {
        final numInterpolations = (distance / 50).floor(); // Point every ~50m
        
        for (int j = 1; j < numInterpolations; j++) {
          final ratio = j / numInterpolations;
          final lat = start.latitude + (end.latitude - start.latitude) * ratio;
          final lng = start.longitude + (end.longitude - start.longitude) * ratio;
          interpolatedPoints.add(LatLng(lat, lng));
        }
      }
    }
    
    // Add the last point
    interpolatedPoints.add(originalPoints.last);
    
    return interpolatedPoints;
  }

  static Future<int> _calculateETA(
    double driverLat,
    double driverLng,
    double pickupLat,
    double pickupLng,
  ) async {
    try {
      final distanceData = await _getDirectionsMatrix(
        driverLat,
        driverLng,
        pickupLat,
        pickupLng,
        includeTraffic: true,
      );

      return (distanceData['duration'] / 60).round(); // Convert to minutes
    } catch (e) {
      // Fallback to straight-line distance calculation
      double distance = Geolocator.distanceBetween(
        driverLat,
        driverLng,
        pickupLat,
        pickupLng,
      );

      // Assume average speed of 30 km/h in city traffic
      double timeHours = (distance / 1000) / 30;
      return (timeHours * 60).round(); // Convert to minutes
    }
  }

  static double _calculateFare(double distanceKm) {
    if (distanceKm <= 0) return _minimumFare * _surgeMultiplier;
    
    // Base fare covers first 2km (or whatever firstTwoKmFare is configured to)
    double fare = _firstTwoKmFare;
    
    // Calculate distance beyond 2km
    double distanceBeyond2km = distanceKm - 2.0;
    if (distanceBeyond2km > 0) {
      // Calculate number of 500m increments, rounding up
      int increments = (distanceBeyond2km * 2).ceil();
      fare += increments * _farePer500m;
    }
    
    fare = fare * _surgeMultiplier;
    
    return fare < _minimumFare ? _minimumFare : fare;
  }

  static Map<String, dynamic> _calculateFallbackFareAndETA(
    double pickupLat,
    double pickupLng,
    double dropoffLat,
    double dropoffLng,
    double? driverLat,
    double? driverLng,
  ) {
    // Calculate straight-line distance
    double distance = Geolocator.distanceBetween(
      pickupLat,
      pickupLng,
      dropoffLat,
      dropoffLng,
    );

    double distanceKm = distance / 1000;
    double fare = _calculateFare(distanceKm);

    // Estimate duration (assume 1.5x straight-line distance for actual route)
    double adjustedDistanceKm = distanceKm * 1.5;
    int durationMinutes = (adjustedDistanceKm / 30 * 60)
        .round(); // 30 km/h average speed

    int? etaMinutes;
    if (driverLat != null && driverLng != null) {
      double etaDistance = Geolocator.distanceBetween(
        driverLat,
        driverLng,
        pickupLat,
        pickupLng,
      );
      double etaDistanceKm =
          (etaDistance / 1000) * 1.5; // Adjust for actual route
      etaMinutes = (etaDistanceKm / 30 * 60).round(); // 30 km/h average speed
    }

    // Create simple straight-line geometry for fallback
    final fallbackGeometry = [
      LatLng(pickupLat, pickupLng),
      LatLng(dropoffLat, dropoffLng),
    ];

    return {
      'fare': fare,
      'distance': distanceKm,
      'duration': durationMinutes,
      'eta': etaMinutes,
      'routeGeometry': fallbackGeometry, // Include fallback geometry
    };
  }

  static String formatFare(double fare) {
    return '₱${fare.toStringAsFixed(0)}';
  }

  static String formatDuration(int minutes) {
    if (minutes < 60) {
      return '${minutes}m';
    } else {
      int hours = minutes ~/ 60;
      int remainingMinutes = minutes % 60;
      return remainingMinutes > 0
          ? '${hours}h ${remainingMinutes}m'
          : '${hours}h';
    }
  }

  static String formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).round()}m';
    } else {
      return '${km.toStringAsFixed(1)}km';
    }
  }

  // Admin function to update fare rates
  static Future<void> updateFareRates({
    required String adminId,
    double? baseFare,
    double? firstTwoKmFare,
    double? farePer500m,
    double? minimumFare,
    double? surgeMultiplier,
  }) async {
    print('Updating fare rates to Firestore...');
    final data = {
      if (baseFare != null) 'baseFare': baseFare,
      if (firstTwoKmFare != null) 'firstTwoKmFare': firstTwoKmFare,
      if (farePer500m != null) 'farePer500m': farePer500m,
      if (minimumFare != null) 'minimumFare': minimumFare,
      if (surgeMultiplier != null) 'surgeMultiplier': surgeMultiplier,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': adminId,
    };

    // Update main setting document for real-time listener
    await _firestore.collection('settings').doc('fare_rules').set(data, SetOptions(merge: true));

    // Save history for audit
    await _firestore.collection('settings').doc('fare_rules').collection('history').add(data);
  }
}
