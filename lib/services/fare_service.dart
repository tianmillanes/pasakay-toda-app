import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';

class FareService {
  static const String _googleMapsApiKey =
      'AIzaSyDhsS5TahdyUKJl61qR1swg9vLpFNL3U1Q'; // Google Maps API key
  static const double _baseFare = 15.0; // Base fare in PHP
  static const double _farePerKm = 8.0; // Fare per kilometer in PHP
  static const double _minimumFare = 15.0; // Minimum fare in PHP

  static Future<Map<String, dynamic>> calculateFareAndETA({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    double? driverLat,
    double? driverLng,
  }) async {
    try {
      // Calculate distance and duration using Google Maps Distance Matrix API
      final distanceData = await _getDistanceMatrix(
        pickupLat,
        pickupLng,
        dropoffLat,
        dropoffLng,
      );

      double distanceKm = distanceData['distance'] / 1000; // Convert to km
      int durationMinutes = (distanceData['duration'] / 60)
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

  static Future<Map<String, dynamic>> _getDistanceMatrix(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    final String url =
        'https://maps.googleapis.com/maps/api/distancematrix/json'
        '?origins=$originLat,$originLng'
        '&destinations=$destLat,$destLng'
        '&units=metric'
        '&key=$_googleMapsApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['status'] == 'OK' && data['rows'].isNotEmpty) {
        final element = data['rows'][0]['elements'][0];

        if (element['status'] == 'OK') {
          return {
            'distance': element['distance']['value'].toDouble(), // in meters
            'duration': element['duration']['value'].toDouble(), // in seconds
          };
        }
      }
    }

    throw Exception('Failed to get distance matrix data');
  }

  static Future<int> _calculateETA(
    double driverLat,
    double driverLng,
    double pickupLat,
    double pickupLng,
  ) async {
    try {
      final distanceData = await _getDistanceMatrix(
        driverLat,
        driverLng,
        pickupLat,
        pickupLng,
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
    double fare = _baseFare + (distanceKm * _farePerKm);
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

    return {
      'fare': fare,
      'distance': distanceKm,
      'duration': durationMinutes,
      'eta': etaMinutes,
    };
  }

  static String formatFare(double fare) {
    return '₱${fare.toStringAsFixed(2)}';
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
    double? baseFare,
    double? farePerKm,
    double? minimumFare,
  }) async {
    // This would typically update the rates in Firestore
    // For now, we'll just print the values
    print('Updating fare rates:');
    if (baseFare != null) print('Base fare: ₱$baseFare');
    if (farePerKm != null) print('Fare per km: ₱$farePerKm');
    if (minimumFare != null) print('Minimum fare: ₱$minimumFare');
  }
}
