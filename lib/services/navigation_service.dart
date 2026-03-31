import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/lat_lng.dart';
import '../config/credentials_config.dart';
import '../utils/polyline_decoder.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class NavigationInstruction {
  final String instruction;
  final double distance;
  final double duration;
  final String maneuverType;
  final String? maneuverModifier;
  final LatLng location;
  final int routePointIndex; // Index of the maneuver location in the route points list

  NavigationInstruction({
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.maneuverType,
    this.maneuverModifier,
    required this.location,
    this.routePointIndex = -1,
  });
}

class NavigationState {
  final bool isNavigating;
  final double remainingDistance;
  final double remainingDuration;
  final NavigationInstruction? currentInstruction;
  final double? distanceToNextTurn; // Add this field
  final NavigationInstruction? nextInstruction;
  final LatLng currentLocation;
  final LatLng destination;
  final double heading;

  NavigationState({
    required this.isNavigating,
    required this.remainingDistance,
    required this.remainingDuration,
    this.currentInstruction,
    this.distanceToNextTurn,
    this.nextInstruction,
    required this.currentLocation,
    required this.destination,
    required this.heading,
  });
}

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  final FlutterTts _tts = FlutterTts();
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  final StreamController<NavigationState> _navigationStateController = 
      StreamController<NavigationState>.broadcast();
  
  List<NavigationInstruction> _instructions = [];
  List<LatLng> _routePoints = [];
  LatLng? _currentLocation;
  LatLng? _destination;
  bool _isNavigating = false;
  int _currentInstructionIndex = 0;
  int _currentRouteSegmentIndex = 0;
  // Timer? _voiceInstructionTimer; // Removed
  double _lastSpokenDistance = -1; // Added for voice tracking
  int _lastSpokenInstructionIndex = -1; // Added for voice tracking
  
  double _totalDistance = 0;
  double _totalDuration = 0;
  double _currentHeading = 0.0;
  DateTime? _lastNavigationStateEmit;
  DateTime? _lastOffRouteCheck;

  Stream<NavigationState> get navigationStateStream => 
      _navigationStateController.stream;

  Future<void> initializeTTS() async {
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.9);
  }

  Future<void> startCompassTracking() async {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        _currentHeading = event.heading!;
        _emitNavigationState();
      }
    });
  }

  Future<List<NavigationInstruction>> getTurnByTurnDirections(
    LatLng origin,
    LatLng destination, {
    bool includeTraffic = true,
  }) async {
    // Validate coordinates
    if (!_isValidCoordinate(origin) || !_isValidCoordinate(destination)) {
      print('❌ Invalid coordinates: origin=${origin.latitude},${origin.longitude}, destination=${destination.latitude},${destination.longitude}');
      throw Exception('Invalid coordinates provided');
    }

    final String accessToken = CredentialsConfig.mapboxAccessToken;
    final String profile = includeTraffic ? 'mapbox/driving-traffic' : 'mapbox/driving';
    final Map<String, String> queryParams = {
      'access_token': accessToken,
      'steps': 'true',
      'overview': 'full',
      'geometries': 'geojson',
      'exclude': 'motorway,toll,ferry',
    };
    
    final Uri uri = Uri.parse('https://api.mapbox.com/directions/v5/$profile/'
        '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}')
        .replace(queryParameters: queryParams);

    print('🗺️ Requesting directions from ${origin.latitude},${origin.longitude} to ${destination.latitude},${destination.longitude}');
    print('🔗 API URL: $uri');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        
        if (routes.isEmpty) {
          print('⚠️ No routes found between the specified points');
          return [];
        }

        final route = routes[0];
        
        // Store route geometry first so we can map instructions to points
        final geometry = route['geometry'];
        if (geometry is Map<String, dynamic>) {
          _routePoints = PolylineDecoder.decodeMapboxGeometry(geometry);
        } else if (geometry is String) {
          _routePoints = PolylineDecoder.decodePolyline(geometry);
        }

        final legs = route['legs'] as List;
        final instructions = <NavigationInstruction>[];
        int lastRoutePointIndex = 0;

        for (final leg in legs) {
          final steps = leg['steps'] as List;
          
          for (final step in steps) {
            final maneuver = step['maneuver'] as Map<String, dynamic>;
            final instruction = step['maneuver']['instruction'] ?? 
                              step['maneuver']['type'] ?? 'Continue';
            
            final location = LatLng(
                (maneuver['location'][1] as num).toDouble(),
                (maneuver['location'][0] as num).toDouble(),
            );

            // Find closest route point index
            int bestIndex = lastRoutePointIndex;
            double minDistance = double.infinity;
            
            // Search forward from last known index
            if (_routePoints.isNotEmpty) {
              for (int i = lastRoutePointIndex; i < _routePoints.length; i++) {
                 final dist = _calculateDistance(location, _routePoints[i]);
                 if (dist < minDistance) {
                   minDistance = dist;
                   bestIndex = i;
                 }
                 // Optimization: if we found a very close point (< 10m) and distance starts increasing, break
                 if (minDistance < 20 && dist > 50) {
                   break; 
                 }
              }
            }
            
            // Update start index for next search
            lastRoutePointIndex = bestIndex;

            instructions.add(NavigationInstruction(
              instruction: instruction,
              distance: (step['distance'] as num).toDouble(),
              duration: (step['duration'] as num).toDouble(),
              maneuverType: maneuver['type'] ?? 'turn',
              maneuverModifier: maneuver['modifier'],
              location: location,
              routePointIndex: bestIndex,
            ));
          }
        }

        _totalDistance = (route['distance'] as num).toDouble();
        _totalDuration = (route['duration'] as num).toDouble();

        print('✅ Successfully retrieved ${instructions.length} navigation instructions');
        return instructions;
      } else {
        final errorBody = response.body;
        print('❌ Mapbox API error: ${response.statusCode}');
        print('❌ Response body: $errorBody');
        throw Exception('Failed to get directions: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('❌ Error getting turn-by-turn directions: $e');
      return [];
    }
  }

  // Validate coordinate ranges
  bool _isValidCoordinate(LatLng coord) {
    return coord.latitude >= -90 && coord.latitude <= 90 &&
           coord.longitude >= -180 && coord.longitude <= 180 &&
           (coord.latitude != 0 || coord.longitude != 0); // Allow 0 for one but not both
  }

  Future<void> startNavigation(
    LatLng origin,
    LatLng destination,
    {bool enableVoice = true,
  }) async {
    try {
      // Validate input coordinates
      if (!_isValidCoordinate(origin) || !_isValidCoordinate(destination)) {
        throw Exception('Invalid origin or destination coordinates');
      }
      
      if (_isNavigating) {
        await stopNavigation();
      }

      print('🧭 Starting navigation from ${origin.latitude},${origin.longitude} to ${destination.latitude},${destination.longitude}');

      _destination = destination;
      _currentLocation = origin;
      _instructions = await getTurnByTurnDirections(origin, destination);
      _currentInstructionIndex = 0;
      _currentRouteSegmentIndex = 0;
      _isNavigating = true;
      _lastSpokenDistance = -1;
      _lastSpokenInstructionIndex = -1;

      if (enableVoice) {
        try {
          await initializeTTS();
        } catch (ttsError) {
          print('⚠️ Failed to initialize TTS: $ttsError');
          // Continue navigation without voice instructions
        }
      }

      // Start GPS tracking and compass
      try {
        await _startLocationTracking();
      } catch (locationError) {
        print('⚠️ Failed to start location tracking: $locationError');
        // Continue navigation with best effort
      }
      
      try {
        await startCompassTracking();
      } catch (compassError) {
        print('⚠️ Failed to start compass tracking: $compassError');
        // Continue navigation with best effort
      }

      // Emit initial navigation state
      _emitNavigationState();

      // Start voice instructions if TTS is available
      if (enableVoice && _instructions.isNotEmpty) {
        try {
          // Speak initial instruction immediately
          final dist = _calculateDistance(_currentLocation!, _instructions[0].location);
          _speakInstruction(_instructions[0], dist);
          _lastSpokenDistance = dist;
          _lastSpokenInstructionIndex = 0;
        } catch (voiceError) {
          print('⚠️ Failed to start voice instructions: $voiceError');
          // Continue navigation without voice instructions
        }
      }

      print('🧭 Navigation started with ${_instructions.length} instructions');
    } catch (e) {
      print('❌ Failed to start navigation: $e');
      _isNavigating = false;
      // Don't rethrow to prevent app crashes, let UI handle the failure gracefully
    }
  }

  Future<void> stopNavigation() async {
    _isNavigating = false;
    await _positionStreamSubscription?.cancel();
    await _compassSubscription?.cancel();
    // _voiceInstructionTimer?.cancel();
    await _tts.stop();

    _emitNavigationState();
    print('🛑 Navigation stopped');
  }

  Future<void> _startLocationTracking() async {
    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2, // Update every 2 meters for precise tracking
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _updateLocation(
        LatLng(position.latitude, position.longitude),
        accuracy: position.accuracy,
      );
    });
  }

  void _updateLocation(LatLng newLocation, {double accuracy = 0.0}) {
    _currentLocation = newLocation;
    final now = DateTime.now();
    
    // Update the current segment index on the route
    _updateCurrentRouteSegmentIndex();
    
    // Check if we need to advance to next instruction or speak voice guidance
    if (_currentInstructionIndex < _instructions.length) {
      final currentInstruction = _instructions[_currentInstructionIndex];
      final distanceToInstruction = _calculateDistance(
        newLocation,
        currentInstruction.location,
      );

      // --- Voice Guidance Logic ---
      
      // If instruction index changed (e.g. reroute), reset tracking
      if (_lastSpokenInstructionIndex != _currentInstructionIndex) {
        _lastSpokenDistance = double.infinity;
        _lastSpokenInstructionIndex = _currentInstructionIndex;
      }

      // Voice Thresholds (in meters)
      // Speak if we crossed a threshold since last speak
      final thresholds = [2000.0, 1000.0, 500.0, 200.0, 100.0];
      
      bool shouldSpeak = false;
      
      // Check standard thresholds
      for (final threshold in thresholds) {
        if (_lastSpokenDistance > threshold && distanceToInstruction <= threshold) {
          shouldSpeak = true;
          break;
        }
      }
      
      // Check "Turn Now" threshold (approx 40m)
      // Only speak if we haven't spoken "Turn Now" yet (which would be < 50m check)
      if (!shouldSpeak && _lastSpokenDistance > 50.0 && distanceToInstruction <= 50.0) {
        shouldSpeak = true;
      }

      if (shouldSpeak) {
        _speakInstruction(currentInstruction, distanceToInstruction);
        _lastSpokenDistance = distanceToInstruction;
      }

      // --- Advance Logic ---
      
      // Advance instruction if we're close enough OR if we've passed the point on route
      double advanceThreshold = 15.0 + (accuracy > 30 ? accuracy * 0.2 : 0);
      advanceThreshold = advanceThreshold.clamp(15.0, 40.0);

      bool shouldAdvance = false;
      if (distanceToInstruction < advanceThreshold) {
        shouldAdvance = true;
      } else if (currentInstruction.routePointIndex >= 0) {
        // If we are significantly past the instruction point (e.g. +3 segments ~30-50m)
        // This handles cases where driver made the turn but didn't get close enough to the waypoint
        if (_currentRouteSegmentIndex > currentInstruction.routePointIndex + 3) {
             shouldAdvance = true;
             print('⏩ Advancing instruction by route index: segment=$_currentRouteSegmentIndex > instruction=${currentInstruction.routePointIndex}');
        }
      }

      if (shouldAdvance) {
        _currentInstructionIndex++;
        
        // When advancing, immediately speak the NEXT instruction if it exists
        if (_currentInstructionIndex < _instructions.length) {
            final nextInstruction = _instructions[_currentInstructionIndex];
            final distToNext = _calculateDistance(newLocation, nextInstruction.location);
            
            // Speak next instruction
            _speakInstruction(nextInstruction, distToNext);
            
            // Update tracking
            _lastSpokenInstructionIndex = _currentInstructionIndex;
            _lastSpokenDistance = distToNext;
        }
      }
    }

    // Throttle off-route detection to reduce heavy geometry work (500ms for faster rerouting)
    final shouldCheckOffRoute = _lastOffRouteCheck == null ||
        now.difference(_lastOffRouteCheck!) >= const Duration(milliseconds: 500);

    if (shouldCheckOffRoute && _isOffRoute(newLocation, accuracy: accuracy)) {
      _lastOffRouteCheck = now;
      _recalculateRoute(newLocation);
    }

    // Check if we've reached destination
    if (_destination != null) {
      final distanceToDestination = _calculateDistance(newLocation, _destination!);
      // Same logic for arrival threshold
      double arrivalThreshold = 20.0 + (accuracy > 30 ? accuracy * 0.2 : 0);
      arrivalThreshold = arrivalThreshold.clamp(20.0, 60.0);

      if (distanceToDestination < arrivalThreshold) {
        _speakInstruction(null, 0);
        stopNavigation();
      }
    }

    // Throttle navigation state emission to avoid excessive rebuilds
    final shouldEmitState = _lastNavigationStateEmit == null ||
        now.difference(_lastNavigationStateEmit!) >= const Duration(milliseconds: 300);

    if (shouldEmitState) {
      _lastNavigationStateEmit = now;
      _emitNavigationState();
    }
  }

  void _updateCurrentRouteSegmentIndex() {
    if (_routePoints.length < 2 || _currentLocation == null) return;
    
    // Define search window to prevent index jumping
    // Search a bit backwards (for jitter) and significantly forward
    int startIndex = (_currentRouteSegmentIndex - 2).clamp(0, _routePoints.length - 2);
    int endIndex = (_currentRouteSegmentIndex + 30).clamp(0, _routePoints.length - 2);
    
    // If we just started or re-routed (index 0), search a wider initial window
    if (_currentRouteSegmentIndex == 0) {
        endIndex = (_routePoints.length - 2).clamp(0, 100); 
    }

    int bestSegmentIndex = _currentRouteSegmentIndex;
    double minDistance = double.infinity;
    
    for (int i = startIndex; i <= endIndex; i++) {
      final distance = _calculateDistanceToLineSegment(
        _currentLocation!,
        _routePoints[i],
        _routePoints[i + 1],
      );
      
      // Add a small bias to favor forward progress
      // If distances are equal, we prefer the higher index (further along route)
      // or we prefer sticking to current index if the improvement is negligible
      if (distance < minDistance) {
        minDistance = distance;
        bestSegmentIndex = i;
      }
    }
    
    // Only update if we found a segment within a reasonable distance
    // If the best segment is > 100m away, we might be off-route or the index is wrong.
    // In that case, we don't update (let off-route detection handle it)
    if (minDistance < 100.0) {
       _currentRouteSegmentIndex = bestSegmentIndex;
    }
  }

  // Check if driver has deviated from the planned route
  bool _isOffRoute(LatLng currentLocation, {double accuracy = 0.0}) {
    // If no route points available, we can't determine if off-route
    if (_routePoints.isEmpty || _routePoints.length < 2) {
      return false;
    }

    // If GPS accuracy is extremely poor (> 200m), skip off-route detection
    // to prevent constant recalculation loops from "jumping" locations.
    if (accuracy > 200) {
      print('⚠️ Skipping off-route check: GPS accuracy is too low (${accuracy.toStringAsFixed(1)}m)');
      return false;
    }
    
    try {
      // Calculate distance from current location to route line
      double minDistanceToRoute = double.infinity;
      for (int i = 0; i < _routePoints.length - 1; i++) {
        final distance = _calculateDistanceToLineSegment(
          currentLocation,
          _routePoints[i],
          _routePoints[i + 1],
        );
        if (distance < minDistanceToRoute) {
          minDistanceToRoute = distance;
        }
      }
      
      // Consider off-route if more than the threshold from planned path.
      // Base threshold is 50 meters.
      // If accuracy is poor, we increase the threshold to avoid false positives.
      double offRouteThreshold = 50.0;
      if (accuracy > 30) {
        // Add a portion of accuracy to the threshold, capped at 200m total.
        offRouteThreshold = (50.0 + (accuracy * 0.7)).clamp(50.0, 200.0);
      }

      final isOff = minDistanceToRoute > offRouteThreshold;
      if (isOff) {
        print('🔄 Off-route: dist=${minDistanceToRoute.toStringAsFixed(1)}m, threshold=${offRouteThreshold.toStringAsFixed(1)}m (accuracy=${accuracy.toStringAsFixed(1)}m)');
      }
      
      return isOff;
    } catch (e) {
      print('⚠️ Error checking off-route status: $e');
      return false;
    }
  }

  // Calculate distance from point to line segment
  double _calculateDistanceToLineSegment(LatLng point, LatLng lineStart, LatLng lineEnd) {
    final A = point.latitude - lineStart.latitude;
    final B = point.longitude - lineStart.longitude;
    final C = lineEnd.latitude - lineStart.latitude;
    final D = lineEnd.longitude - lineStart.longitude;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    
    if (lenSq == 0) return _calculateDistance(point, lineStart);
    
    final param = dot / lenSq;
    final xx = lineStart.latitude + param * C;
    final yy = lineStart.longitude + param * D;
    
    return _calculateDistance(point, LatLng(xx, yy));
  }

  // Recalculate route when off-route
  void _recalculateRoute(LatLng currentLocation) async {
    try {
      // Ensure destination is not null before recalculating
      if (_destination == null) {
        print('⚠️ Cannot recalculate route: destination is null');
        return;
      }
      
      print('🔄 Off-route detected, recalculating from current position...');
      
      final newInstructions = await getTurnByTurnDirections(
        currentLocation,
        _destination!,
        includeTraffic: true,
      );
      
      if (newInstructions.isNotEmpty) {
        _instructions = newInstructions;
        _currentInstructionIndex = 0;
        _currentRouteSegmentIndex = 0;
        _totalDistance = _calculateTotalRouteDistance();

        print('📍 Route recalculated with ${newInstructions.length} instructions');
        final dist = _calculateDistance(currentLocation, _instructions[0].location);
        _speakInstruction(_instructions[0], dist);
        _lastSpokenDistance = dist;
        _lastSpokenInstructionIndex = 0;
        
        // Emit new state immediately so UI updates the route line
        _emitNavigationState();
      }
    } catch (e) {
      print('❌ Failed to recalculate route: $e');
    }
  }

  // Calculate total route distance
  double _calculateTotalRouteDistance() {
    if (_routePoints.isEmpty || _routePoints.length < 2) return 0;
    
    double totalDistance = 0;
    try {
      for (int i = 0; i < _routePoints.length - 1; i++) {
        totalDistance += _calculateDistance(_routePoints[i], _routePoints[i + 1]);
      }
    } catch (e) {
      print('⚠️ Error calculating total route distance: $e');
      return 0;
    }
    return totalDistance;
  }

  // Removed _startVoiceInstructions as we now use distance-based triggers in _updateLocation

  Future<void> _speakInstruction(NavigationInstruction? instruction, double distance) async {
    if (instruction == null) {
      await _tts.speak("You have arrived at your destination");
    } else {
      String message = _formatVoiceInstruction(instruction, distance);
      await _tts.speak(message);
    }
  }

  String _formatVoiceInstruction(NavigationInstruction instruction, double distance) {
    String baseInstruction = instruction.instruction;
    
    // If very close (Turn Now)
    if (distance < 50) {
      // Just say the instruction e.g. "Turn Right"
      // Sometimes instructions already contain "Turn right onto X street"
      return baseInstruction; 
    }
    
    // Add distance information
    if (distance < 100) {
      return "In ${distance.round()} meters, $baseInstruction";
    } else if (distance < 1000) {
      return "In ${(distance / 10).round() * 10} meters, $baseInstruction";
    } else {
      final km = (distance / 1000).toStringAsFixed(1);
      return "In $km kilometers, $baseInstruction";
    }
  }

  void _emitNavigationState() {
    if (!_navigationStateController.isClosed) {
      // Ensure we have valid locations before emitting state
      final currentLocation = _currentLocation ?? LatLng(0, 0);
      final destination = _destination ?? LatLng(0, 0);
      
      double? distToTurn;
      if (_isNavigating && _currentInstructionIndex < _instructions.length) {
        final instruction = _instructions[_currentInstructionIndex];
        if (instruction.routePointIndex >= 0) {
           distToTurn = _calculateDistanceAlongRoute(targetPointIndex: instruction.routePointIndex);
        } else {
           distToTurn = _calculateDistance(currentLocation, instruction.location);
        }
      }

      final state = NavigationState(
        isNavigating: _isNavigating,
        remainingDistance: _calculateDistanceAlongRoute(),
        remainingDuration: _calculateRemainingDuration(),
        currentInstruction: _currentInstructionIndex < _instructions.length 
            ? _instructions[_currentInstructionIndex] 
            : null,
        distanceToNextTurn: distToTurn,
        nextInstruction: _currentInstructionIndex + 1 < _instructions.length 
            ? _instructions[_currentInstructionIndex + 1] 
            : null,
        currentLocation: currentLocation,
        destination: destination,
        heading: _currentHeading, // Real compass heading
      );

      _navigationStateController.add(state);
    }
  }

  double _calculateDistanceAlongRoute({int? targetPointIndex}) {
    if (_currentLocation == null) return 0;
    if (_routePoints.isEmpty || _routePoints.length < 2) {
       // Fallback to direct distance if no route
       if (targetPointIndex == null && _destination != null) {
          return _calculateDistance(_currentLocation!, _destination!);
       }
       return 0;
    }
    
    int endIndex = targetPointIndex ?? (_routePoints.length - 1);
    
    // Safety check
    if (endIndex >= _routePoints.length) endIndex = _routePoints.length - 1;
    if (endIndex <= _currentRouteSegmentIndex) return 0;

    double distance = 0;
    
    try {
      // Distance to end of current segment
      int nextPointIndex = _currentRouteSegmentIndex + 1;
      
      if (nextPointIndex <= endIndex) {
          distance += _calculateDistance(_currentLocation!, _routePoints[nextPointIndex]);
      }
      
      // Sum full segments
      for (int i = nextPointIndex; i < endIndex; i++) {
        distance += _calculateDistance(_routePoints[i], _routePoints[i + 1]);
      }
    } catch (e) {
      print('⚠️ Error calculating distance along route: $e');
      if (targetPointIndex == null && _destination != null) {
         return _calculateDistance(_currentLocation!, _destination!);
      }
    }
    
    return distance;
  }

  double _calculateRemainingDistance() => _calculateDistanceAlongRoute();

  double _calculateRemainingDuration() {
    if (_instructions.isEmpty || _currentInstructionIndex >= _instructions.length) {
       final remainingDistance = _calculateRemainingDistance();
       
       if (_totalDistance > 0 && _totalDuration > 0) {
         final ratio = (remainingDistance / _totalDistance).clamp(0.0, 1.0);
         return (_totalDuration / 60.0) * ratio;
       }

       return remainingDistance / (13.9 * 1000 / 60);
    }

    double remainingDuration = 0;
    
    // 1. Current step remainder
    final current = _instructions[_currentInstructionIndex];
    double distToTurn = 0;
    
    if (current.routePointIndex >= 0) {
       distToTurn = _calculateDistanceAlongRoute(targetPointIndex: current.routePointIndex);
    } else {
       distToTurn = _calculateDistance(_currentLocation ?? LatLng(0,0), current.location);
    }
    
    if (current.distance > 0) {
      double fraction = (distToTurn / current.distance).clamp(0.0, 1.0);
      remainingDuration += current.duration * fraction;
    }
    
    // 2. Subsequent steps
    for (int i = _currentInstructionIndex + 1; i < _instructions.length; i++) {
      remainingDuration += _instructions[i].duration;
    }
    
    return remainingDuration / 60.0; // Convert seconds to minutes
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  // Snap a location to the nearest point on the route with improved accuracy
  LatLng snapToRoute(LatLng point) {
    if (_routePoints.isEmpty) return point;
    if (_routePoints.length < 2) return _routePoints.first;

    double minDistance = double.infinity;
    LatLng closestPoint = point;
    int bestSegmentIndex = _currentRouteSegmentIndex;

    // Intelligent search strategy: search more broadly to find actual closest point
    int searchRadius = 50; // Increased from 15 to 50 for better coverage
    int start = (_currentRouteSegmentIndex - searchRadius).clamp(0, _routePoints.length - 2);
    int end = (_currentRouteSegmentIndex + searchRadius).clamp(0, _routePoints.length - 2);
    
    // If we are at the start or end, search more broadly
    if (_currentRouteSegmentIndex < 20) {
      end = (_routePoints.length - 2).clamp(0, 200);
    }
    if (_currentRouteSegmentIndex > _routePoints.length - 30) {
      start = (_routePoints.length - 200).clamp(0, _currentRouteSegmentIndex);
    }

    // First pass: find the closest segment
    for (int i = start; i <= end; i++) {
      final p1 = _routePoints[i];
      final p2 = _routePoints[i + 1];
      
      // Calculate perpendicular distance to segment
      final projected = _projectPointOnSegment(point, p1, p2);
      final dist = _calculateDistance(point, projected);

      if (dist < minDistance) {
        minDistance = dist;
        closestPoint = projected;
        bestSegmentIndex = i;
      }
    }

    // Update current segment index for better tracking
    _currentRouteSegmentIndex = bestSegmentIndex;

    // Always snap to the closest point on route, regardless of distance
    // This prevents route jumps caused by inconsistent snapping logic
    return closestPoint;
  }

  Map<String, dynamic> snapToRouteWithIndex(LatLng point) {
    if (_routePoints.isEmpty) return {'point': point, 'index': 0};
    if (_routePoints.length < 2) return {'point': _routePoints.first, 'index': 0};

    double minDistance = double.infinity;
    LatLng closestPoint = point;
    int bestIndex = 0;

    // Enhanced search with broader radius for better accuracy
    int searchRadius = 50; // Increased from 20 to 50
    int start = (_currentRouteSegmentIndex - searchRadius).clamp(0, _routePoints.length - 2);
    int end = (_currentRouteSegmentIndex + searchRadius).clamp(0, _routePoints.length - 2);

    for (int i = start; i <= end; i++) {
      final p1 = _routePoints[i];
      final p2 = _routePoints[i + 1];
      
      final projected = _projectPointOnSegment(point, p1, p2);
      final dist = _calculateDistance(point, projected);

      if (dist < minDistance) {
        minDistance = dist;
        closestPoint = projected;
        bestIndex = i;
      }
    }

    // Update tracking
    _currentRouteSegmentIndex = bestIndex;

    // Always return the closest point found, ensuring consistent snapping
    return {
      'point': closestPoint,
      'index': bestIndex,
      'distance': minDistance,
    };
  }

  // Improved point projection on line segment
  LatLng _projectPointOnSegment(LatLng point, LatLng segmentStart, LatLng segmentEnd) {
    final dx = segmentEnd.longitude - segmentStart.longitude;
    final dy = segmentEnd.latitude - segmentStart.latitude;
    
    if (dx == 0 && dy == 0) {
      return segmentStart; // Degenerate segment
    }
    
    final t = ((point.longitude - segmentStart.longitude) * dx + 
               (point.latitude - segmentStart.latitude) * dy) / 
              (dx * dx + dy * dy);
    
    // Clamp t to [0, 1] to stay within segment bounds
    final clampedT = t.clamp(0.0, 1.0);
    
    return LatLng(
      segmentStart.latitude + clampedT * dy,
      segmentStart.longitude + clampedT * dx,
    );
  }

  List<LatLng> get routePoints => _routePoints;
  
  List<LatLng> get remainingRoutePoints {
    if (_routePoints.isEmpty) return [];
    if (_currentLocation == null) return _routePoints;

    // Start from the next point in the segment to avoid backward spikes
    // The current segment is from index i to i+1.
    // Since we are traversing this segment, we should draw from the driver
    // to i+1, then to i+2, etc.
    int nextPointIndex = _currentRouteSegmentIndex + 1;
    
    if (nextPointIndex >= _routePoints.length) {
      return [];
    }
    
    return _routePoints.sublist(nextPointIndex);
  }

  // Public getters for accessing navigation data
  List<NavigationInstruction> get instructions => _instructions;
  int get currentInstructionIndex => _currentInstructionIndex;
  LatLng? get currentLocation => _currentLocation;
  bool get isNavigating => _isNavigating;
  
  NavigationState get currentState => NavigationState(
    isNavigating: _isNavigating,
    remainingDistance: _calculateRemainingDistance(),
    remainingDuration: _calculateRemainingDuration(),
    currentInstruction: _currentInstructionIndex < _instructions.length 
        ? _instructions[_currentInstructionIndex] 
        : null,
    nextInstruction: _currentInstructionIndex + 1 < _instructions.length 
        ? _instructions[_currentInstructionIndex + 1] 
        : null,
    currentLocation: _currentLocation ?? LatLng(0, 0),
    destination: _destination ?? LatLng(0, 0),
    heading: _currentHeading,
  );

  void dispose() {
    stopNavigation();
  }

  /// Get alternative routes (up to 3 options)
  /// Returns a list of route options with distance, duration, and geometry
  Future<List<Map<String, dynamic>>> getAlternativeRoutes(
    LatLng origin,
    LatLng destination, {
    bool includeTraffic = true,
  }) async {
    try {
      if (!_isValidCoordinate(origin) || !_isValidCoordinate(destination)) {
        print('❌ Invalid coordinates for alternative routes');
        return [];
      }

      final String accessToken = CredentialsConfig.mapboxAccessToken;
      final String profile = includeTraffic ? 'mapbox/driving-traffic' : 'mapbox/driving';
      final Map<String, String> queryParams = {
        'access_token': accessToken,
        'steps': 'true',
        'overview': 'full',
        'geometries': 'geojson',
        'exclude': 'motorway,toll,ferry',
        'alternatives': 'true', // Request alternative routes
      };
      
      final Uri uri = Uri.parse('https://api.mapbox.com/directions/v5/$profile/'
          '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}')
          .replace(queryParameters: queryParams);

      print('🗺️ Requesting alternative routes...');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;
        
        if (routes.isEmpty) {
          print('⚠️ No alternative routes found');
          return [];
        }

        final alternatives = <Map<String, dynamic>>[];
        
        // Process up to 3 routes
        for (int i = 0; i < routes.length && i < 3; i++) {
          final route = routes[i];
          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toDouble();
          
          // Decode geometry
          List<LatLng> routePoints = [];
          final geometry = route['geometry'];
          if (geometry is Map<String, dynamic>) {
            routePoints = PolylineDecoder.decodeMapboxGeometry(geometry);
          } else if (geometry is String) {
            routePoints = PolylineDecoder.decodePolyline(geometry);
          }

          alternatives.add({
            'distance': distance,
            'duration': duration,
            'durationMinutes': (duration / 60.0).toStringAsFixed(0),
            'distanceKm': (distance / 1000.0).toStringAsFixed(1),
            'routePoints': routePoints,
            'isRecommended': i == 0, // First route is recommended
          });
        }

        print('✅ Retrieved ${alternatives.length} alternative routes');
        return alternatives;
      } else {
        print('❌ Failed to get alternative routes: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error getting alternative routes: $e');
      return [];
    }
  }
}

