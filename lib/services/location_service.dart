import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../models/lat_lng.dart';
import 'address_search_service.dart';

// Custom exceptions for better error handling
class LocationServiceException implements Exception {
  final String message;
  LocationServiceException(this.message);
  
  @override
  String toString() => message;
}

class LocationPermissionException implements Exception {
  final String message;
  LocationPermissionException(this.message);
  
  @override
  String toString() => message;
}

class LocationService extends ChangeNotifier {
  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  StreamSubscription<Position>? _positionStream;
  bool _isTracking = false;
  bool get isTracking => _isTracking;

  // Driver tracking
  String? _trackingDriverId;
  Timer? _locationUpdateTimer;

  // Geofence polygons
  List<List<double>>? _barangayGeofence;
  List<List<double>>? _todaTerminalGeofence;
  String? _currentBarangayId; // Track which barangay's geofence is loaded

  Future<bool> requestLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are disabled. Don't return false immediately,
      // instead throw an exception that can be caught and handled properly
      throw LocationServiceException('Location services are disabled. Please enable GPS/location services.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationPermissionException('Location permission denied. Please grant permission to access your location.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionException('Location permission permanently denied. Please enable location permission in app settings.');
    }

    return true;
  }

  Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await requestLocationPermission();
      if (!hasPermission) return null;

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      // Log GPS accuracy for debugging - no blocking, geofence validation will determine access
      if (kDebugMode) {
        if (position.accuracy > 100.0) {
          print('INFO: GPS accuracy is low (${position.accuracy.toStringAsFixed(1)}m) - relying on geofence validation');
        } else if (position.accuracy > 50.0) {
          print('INFO: GPS accuracy is moderate (${position.accuracy.toStringAsFixed(1)}m)');
        } else {
          print('INFO: GPS accuracy is good (${position.accuracy.toStringAsFixed(1)}m)');
        }
      }

      if (kDebugMode) {
        print('Location acquired:');
        print('  Coordinates: (${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)})');
        print('  Accuracy: ${position.accuracy.toStringAsFixed(1)}m');
        print('  Timestamp: ${DateTime.fromMillisecondsSinceEpoch(position.timestamp.millisecondsSinceEpoch)}');
      }

      _currentPosition = position;
      notifyListeners();
      return position;
    } on LocationServiceException catch (e) {
      // Re-throw location service exceptions for UI to handle
      rethrow;
    } on LocationPermissionException catch (e) {
      // Re-throw permission exceptions for UI to handle
      rethrow;
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  void startLocationTracking({Function(Position)? onLocationUpdate}) {
    if (_isTracking) return;

    _isTracking = true;
    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10, // Update every 10 meters
          ),
        ).listen((Position position) {
          _currentPosition = position;
          notifyListeners();
          onLocationUpdate?.call(position);
        });
  }

  void stopLocationTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    notifyListeners();
  }

  Future<String> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      print('Getting address for coordinates: ($latitude, $longitude)');
      
      final String? address = await AddressSearchService.getAddressFromCoordinates(
        LatLng(latitude, longitude)
      );
      
      if (address != null && address.isNotEmpty) {
        print('✅ Mapbox Geocoding Result: $address');
        return address;
      }
      
      return 'Unknown Location ($latitude, $longitude)';
    } catch (e) {
      print('Error in getAddressFromCoordinates: $e');
      return 'Unknown Location ($latitude, $longitude)';
    }
  }

  /// Provide approximate location names based on coordinates when geocoding fails
  String _getApproximateLocationName(double latitude, double longitude) {
    // Philippines coordinate ranges (approximate)
    // This is a simple fallback for when geocoding services fail
    
    // Metro Manila area (rough bounds)
    if (latitude >= 14.4 && latitude <= 14.8 && longitude >= 120.9 && longitude <= 121.2) {
      if (latitude >= 14.55 && latitude <= 14.65 && longitude >= 121.0 && longitude <= 121.1) {
        return 'Makati Area (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
      } else if (latitude >= 14.5 && latitude <= 14.6 && longitude >= 120.95 && longitude <= 121.05) {
        return 'Manila Area (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
      } else if (latitude >= 14.6 && latitude <= 14.7 && longitude >= 121.05 && longitude <= 121.15) {
        return 'Quezon City Area (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
      } else {
        return 'Metro Manila (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
      }
    }
    
    // Central Luzon area
    else if (latitude >= 15.0 && latitude <= 15.5 && longitude >= 120.5 && longitude <= 121.0) {
      return 'Central Luzon Area (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
    }
    
    // Southern Luzon area
    else if (latitude >= 13.5 && latitude <= 14.4 && longitude >= 120.8 && longitude <= 121.5) {
      return 'Southern Luzon Area (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
    }
    
    // General Philippines area
    else if (latitude >= 4.0 && latitude <= 21.0 && longitude >= 116.0 && longitude <= 127.0) {
      return 'Philippines (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
    }
    
    // Outside Philippines or unknown area
    else {
      return 'Location (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
    }
  }

  Future<List<LatLng>> getCoordinatesFromAddress(String address) async {
    try {
      // Use current position as proximity if available
      LatLng? proximity;
      if (_currentPosition != null) {
        proximity = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      }
      
      final LatLng? coords = await AddressSearchService.getCoordinatesFromAddress(
        address, 
        proximity: proximity,
      );
      return coords != null ? [coords] : [];
    } catch (e) {
      print('Error getting coordinates from address: $e');
      return [];
    }
  }

  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  // Geofencing functions
  Future<void> loadGeofences({String? barangayId, bool forceReload = false}) async {
    // Check if we already have the correct barangay geofence loaded
    if (!forceReload && barangayId != null && _currentBarangayId == barangayId && areGeofencesLoaded()) {
      if (kDebugMode) {
        print('Geofences already loaded for barangay $barangayId, skipping reload');
      }
      return;
    }
    
    if (kDebugMode) {
      print('Loading geofences from Firestore for barangayId: $barangayId...');
    }
    try {
      // Load barangay-specific geofence if barangayId is provided
      if (barangayId != null) {
        DocumentSnapshot barangayDoc = await FirebaseFirestore.instance
            .collection('barangays')
            .doc(barangayId)
            .get()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException('Barangay geofence loading timed out');
              },
            );

        if (barangayDoc.exists) {
          Map<String, dynamic> data = barangayDoc.data() as Map<String, dynamic>;
          var coordinates = data['geofenceCoordinates'];
          if (coordinates is List) {
            _barangayGeofence = List<List<double>>.from(
              coordinates.map((coord) {
                if (coord is Map) {
                  return [
                    (coord['lat'] as num).toDouble(),
                    (coord['lng'] as num).toDouble(),
                  ];
                }
                return [0.0, 0.0];
              }),
            );
            _currentBarangayId = barangayId;
            if (kDebugMode) {
              print('✅ Loaded barangay geofence for $barangayId with ${_barangayGeofence?.length ?? 0} points');
            }
          }
        }
      } else {
        // Fallback to system geofence if no barangayId provided
        DocumentSnapshot barangayDoc = await FirebaseFirestore.instance
            .collection('system')
            .doc('geofence')
            .get()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException('Barangay geofence loading timed out');
              },
            );

        if (barangayDoc.exists) {
          Map<String, dynamic> data = barangayDoc.data() as Map<String, dynamic>;
          var coordinates = data['coordinates'];
          if (coordinates is List) {
            _barangayGeofence = List<List<double>>.from(
              coordinates.map((coord) => [
                (coord['lat'] as num).toDouble(),
                (coord['lng'] as num).toDouble(),
              ]),
            );
          }
        }
      }

      // Load TODA terminal geofence - per barangay if barangayId provided, otherwise system-wide
      if (barangayId != null) {
        // Load barangay-specific terminal geofence
        DocumentSnapshot barangayDoc = await FirebaseFirestore.instance
            .collection('barangays')
            .doc(barangayId)
            .get()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException('Terminal geofence loading timed out');
              },
            );

        if (barangayDoc.exists) {
          Map<String, dynamic> data = barangayDoc.data() as Map<String, dynamic>;
          var coordinates = data['terminalGeofenceCoordinates'];
          if (coordinates is List) {
            _todaTerminalGeofence = List<List<double>>.from(
              coordinates.map((coord) {
                if (coord is Map) {
                  return [
                    (coord['lat'] as num).toDouble(),
                    (coord['lng'] as num).toDouble(),
                  ];
                }
                return [0.0, 0.0];
              }),
            );
            if (kDebugMode) {
              print('✅ Loaded barangay terminal geofence for $barangayId with ${_todaTerminalGeofence?.length ?? 0} points');
            }
          }
        }
      } else {
        // Fallback to system terminal geofence
        DocumentSnapshot terminalDoc = await FirebaseFirestore.instance
            .collection('system')
            .doc('terminal_geofence')
            .get()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException('Terminal geofence loading timed out');
              },
            );

        if (terminalDoc.exists) {
          Map<String, dynamic> data = terminalDoc.data() as Map<String, dynamic>;
          var coordinates = data['coordinates'];
          if (coordinates is List) {
            _todaTerminalGeofence = List<List<double>>.from(
              coordinates.map((coord) => [
                (coord['lat'] as num).toDouble(),
                (coord['lng'] as num).toDouble(),
              ]),
            );
          }
        }
      }
      
      if (kDebugMode) {
        print('✅ Geofences loaded successfully');
      }
    } catch (e) {
      print('Error loading geofences: $e');
      // Don't rethrow - allow app to continue even if geofences fail to load
    }
  }

  bool isPointInPolygon(double lat, double lon, List<List<double>> polygon) {
    if (polygon.isEmpty || polygon.length < 3) {
      if (kDebugMode) {
        print('Invalid polygon: ${polygon.length} points (minimum 3 required)');
      }
      return false;
    }

    int intersectCount = 0;
    
    // Use ray casting algorithm with improved precision
    for (int i = 0; i < polygon.length; i++) {
      int j = (i + 1) % polygon.length;
      
      double xi = polygon[i][0]; // latitude
      double yi = polygon[i][1]; // longitude
      double xj = polygon[j][0]; // latitude
      double yj = polygon[j][1]; // longitude
      
      // Check if point is exactly on a vertex (with small tolerance for GPS precision)
      const double tolerance = 0.000001; // ~0.1 meter precision
      if ((lat - xi).abs() < tolerance && (lon - yi).abs() < tolerance) {
        if (kDebugMode) {
          print('Point is exactly on vertex $i: ($xi, $yi)');
        }
        return true;
      }
      
      // Check if point is on an edge (optional but improves robustness)
      // This is a simplified distance-to-segment check
      double d2 = (xj - xi) * (xj - xi) + (yj - yi) * (yj - yi);
      if (d2 > 0) {
        double t = ((lat - xi) * (xj - xi) + (lon - yi) * (yj - yi)) / d2;
        if (t >= 0 && t <= 1) {
          double projectionLat = xi + t * (xj - xi);
          double projectionLon = yi + t * (yj - yi);
          double dist2 = (lat - projectionLat) * (lat - projectionLat) + (lon - projectionLon) * (lon - projectionLon);
          if (dist2 < tolerance * tolerance) {
            if (kDebugMode) {
              print('Point is on edge between $i and $j');
            }
            return true;
          }
        }
      }
      
      // Ray casting intersection check
      // We use a small epsilon for the longitude check to avoid horizontal edge issues
      const double epsilon = 0.0000000001;
      if (((yi > lon) != (yj > lon)) &&
          (lat < (xj - xi) * (lon - yi) / (yj - yi + epsilon) + xi)) {
        intersectCount++;
      }
    }

    bool isInside = (intersectCount % 2) == 1;

    if (kDebugMode) {
      print('Enhanced point-in-polygon check:');
      print('  Point: ($lat, $lon)');
      print('  Polygon vertices: ${polygon.length}');
      print('  Ray intersections: $intersectCount');
      print('  Result: $isInside');
    }

    return isInside;
  }

  bool rayCastIntersect(
    double lat,
    double lon,
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    double aLat = lat1 - lat;
    double bLat = lat2 - lat;
    double aLon = lon1 - lon;
    double bLon = lon2 - lon;

    if ((aLat > 0 && bLat > 0) || (aLat < 0 && bLat < 0)) {
      return false;
    }

    if ((aLon > 0 && bLon > 0)) {
      return false;
    }

    if ((aLon < 0 && bLon < 0)) {
      return true;
    }

    double m = (lat2 - lat1) / (lon2 - lon1);
    double bee = (-aLon) / m + lat;
    return bee > lat;
  }

  bool isInBarangayGeofence(double lat, double lon) {
    if (_barangayGeofence == null || _barangayGeofence!.isEmpty) {
      throw Exception('Barangay geofence not loaded. Please restart the app.');
    }
    return isPointInPolygon(lat, lon, _barangayGeofence!);
  }

  /// Check if geofences are properly loaded
  bool areGeofencesLoaded() {
    bool terminalLoaded = _todaTerminalGeofence != null && 
        _todaTerminalGeofence!.isNotEmpty && 
        _todaTerminalGeofence!.length >= 3;
    bool barangayLoaded = _barangayGeofence != null && 
        _barangayGeofence!.isNotEmpty && 
        _barangayGeofence!.length >= 3;
    
    if (kDebugMode) {
      print('Geofence loading status:');
      print('  Terminal: $terminalLoaded (${_todaTerminalGeofence?.length ?? 0} points)');
      print('  Barangay: $barangayLoaded (${_barangayGeofence?.length ?? 0} points)');
    }
    
    return terminalLoaded && barangayLoaded;
  }

  /// Get geofence status for debugging
  Map<String, dynamic> getGeofenceStatus() {
    return {
      'terminalGeofenceLoaded': _todaTerminalGeofence != null,
      'terminalGeofencePoints': _todaTerminalGeofence?.length ?? 0,
      'barangayGeofenceLoaded': _barangayGeofence != null,
      'barangayGeofencePoints': _barangayGeofence?.length ?? 0,
    };
  }

  /// Get barangay geofence coordinates
  List<List<double>>? getBarangayGeofence() {
    return _barangayGeofence;
  }

  /// Get terminal geofence coordinates
  List<List<double>>? getTerminalGeofence() {
    return _todaTerminalGeofence;
  }

  bool isInTodaTerminalGeofence(double lat, double lon) {
    if (_todaTerminalGeofence == null || _todaTerminalGeofence!.isEmpty) {
      throw Exception('Terminal geofence not loaded. Please restart the app.');
    }
    
    if (_todaTerminalGeofence!.length < 3) {
      throw Exception('Terminal geofence needs at least 3 points to form a valid polygon. Current points: ${_todaTerminalGeofence!.length}');
    }
    
    if (kDebugMode) {
      print('Checking terminal geofence for location: ($lat, $lon)');
      print('Terminal geofence coordinates:');
      for (int i = 0; i < _todaTerminalGeofence!.length; i++) {
        print('  Point $i: [${_todaTerminalGeofence![i][0]}, ${_todaTerminalGeofence![i][1]}]');
      }
    }
    
    bool isInside = isPointInPolygon(lat, lon, _todaTerminalGeofence!);
    
    if (kDebugMode) {
      // Calculate distance to geofence center for debugging only
      double centerLat = _todaTerminalGeofence!.map((p) => p[0]).reduce((a, b) => a + b) / _todaTerminalGeofence!.length;
      double centerLng = _todaTerminalGeofence!.map((p) => p[1]).reduce((a, b) => a + b) / _todaTerminalGeofence!.length;
      double distanceToCenter = calculateDistance(lat, lon, centerLat, centerLng);
      
      print('Distance to geofence center: ${distanceToCenter.toStringAsFixed(2)} meters');
      print('Point-in-polygon result: $isInside');
      
      if (!isInside) {
        print('GEOFENCE VALIDATION FAILED: Driver is outside the terminal geofence');
        print('Driver location: ($lat, $lon)');
        print('Distance from center: ${distanceToCenter.toStringAsFixed(2)}m');
      } else {
        print('GEOFENCE VALIDATION PASSED: Driver is inside the terminal geofence');
      }
    }
    
    // Return ONLY the exact geofence validation result
    return isInside;
  }

  Future<void> updateGeofence(
    String type,
    List<List<double>> coordinates,
  ) async {
    try {
      // Convert nested arrays to maps to avoid Firestore nested array limitation
      final coordinateMaps = coordinates.map((coord) => {
        'lat': coord[0],
        'lng': coord[1],
      }).toList();

      await FirebaseFirestore.instance
          .collection('system')
          .doc(type == 'barangay' ? 'geofence' : 'terminal_geofence')
          .set({'coordinates': coordinateMaps});

      if (type == 'barangay') {
        _barangayGeofence = coordinates;
      } else {
        _todaTerminalGeofence = coordinates;
      }

      notifyListeners();
    } catch (e) {
      print('Error updating geofence: $e');
      rethrow;
    }
  }

  /// Start real-time location tracking for drivers
  Future<void> startDriverLocationTracking(String driverId) async {
    if (_isTracking && _trackingDriverId == driverId) return;

    await stopDriverLocationTracking();

    _trackingDriverId = driverId;
    _isTracking = true;

    // Update location every 10 seconds
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      await _updateDriverLocation();
    });

    // Initial location update
    await _updateDriverLocation();

    notifyListeners();
  }

  /// Stop driver location tracking
  Future<void> stopDriverLocationTracking() async {
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _trackingDriverId = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Update driver location in Firestore
  Future<void> _updateDriverLocation() async {
    if (_trackingDriverId == null) return;

    try {
      final position = await getCurrentLocation();
      if (position != null) {
        // Driver data is stored in 'users' collection with role='driver'
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_trackingDriverId!)
            .update({
              'currentLocation': GeoPoint(
                position.latitude,
                position.longitude,
              ),
              'lastLocationUpdate': FieldValue.serverTimestamp(),
              'speed': position.speed,
              'heading': position.heading,
              'accuracy': position.accuracy,
            });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating driver location: $e');
      }
    }
  }

  /// Get real-time location stream for a specific driver
  Stream<GeoPoint?> getDriverLocationStream(String driverId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(driverId)
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            return data['currentLocation'] as GeoPoint?;
          }
          return null;
        });
  }

  /// Calculate bearing between two points
  double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.bearingBetween(lat1, lon1, lat2, lon2);
  }

  @override
  void dispose() {
    stopLocationTracking();
    stopDriverLocationTracking();
    super.dispose();
  }
}
