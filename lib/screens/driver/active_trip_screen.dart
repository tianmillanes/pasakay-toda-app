import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../models/lat_lng.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/fare_service.dart';
import '../../models/ride_model.dart';
import '../../models/user_model.dart';
import '../../models/pasabuy_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';
import '../../widgets/location_helpers.dart';
import '../../config/credentials_config.dart';
import '../../widgets/chat_button.dart';
import '../../widgets/common/animated_map_button.dart';
import '../../services/navigation_service.dart';
import '../../utils/polyline_decoder.dart';
import '../../utils/polyline_simplifier.dart';

class ActiveTripScreen extends StatefulWidget {
  final RideModel ride;

  const ActiveTripScreen({super.key, required this.ride});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> with TickerProviderStateMixin {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleAnnotationManager;
  mapbox.PolylineAnnotationManager? _lineAnnotationManager;
  mapbox.PointAnnotationManager? _pointAnnotationManager;
  mapbox.PolylineAnnotation? _routeLine;
  mapbox.CircleAnnotation? _driverPuck;
  mapbox.CircleAnnotation? _pulseCircle;
  mapbox.PointAnnotation? _driverPoint;
  Uint8List? _driverPuckImageBytes;
  String? _driverNameInitial;
  Uint8List? _motorcycleIcon;
  NavigationService _navigationService = NavigationService();
  StreamSubscription<NavigationState>? _navigationSubscription;
  StreamSubscription<RideModel?>? _rideSubscription;
  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  RideModel? _currentRide;
  final ValueNotifier<NavigationState?> _navStateNotifier = ValueNotifier(null);
  RideStatus? _lastRideStatus;
  DateTime? _lastPolylineDraw;
  LatLng? _lastPolylineStart;
  bool _isZoomedIn = false;
  bool _isLoading = false;
  bool _useLocationPuck = false;
  String _driverModelSourceId = 'driver_model_source';
  String _driverModelLayerId = 'driver_model_layer';
  bool _driver3DEnabled = false;
  bool _isFollowing = true;
  double _currentZoom = 17.5;
  double _currentBearing = 0.0;
  int? _rideEtaMinutes;
  Future<DocumentSnapshot>? _passengerInfoFuture;
  bool _isDriverMoving = false;
  DateTime? _lastMotionSampleTime;
  LatLng? _lastMotionSampleLoc;
  late LocationService _locationService;
  
  // Animation for pulsing location puck
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Animation for smooth marker movement
  late AnimationController _markerMovementController;
  LatLng? _currentDisplayedLocation;
  double _currentDisplayedHeading = 0;
  LatLng? _animStartLocation;
  LatLng? _animTargetLocation;
  double? _animStartHeading;
  double? _animTargetHeading;
  
  // Scroll controller reference for the draggable sheet
  ScrollController? _sheetScrollController;

  @override
  void initState() {
    super.initState();
    _currentRide = widget.ride;
    _lastRideStatus = widget.ride.status;
    _passengerInfoFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.ride.passengerId)
        .get();
    _loadMotorcycleIcon();
    _loadDriverPuckImage();

    // Initialize pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 8.0, end: 22.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    )..addListener(() {
      _updatePulseMarker();
    });

    _markerMovementController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onMarkerAnimationTick);

    _locationService = Provider.of<LocationService>(context, listen: false);
    _locationService.addListener(_onLocationUpdate);

    _navigationSubscription = _navigationService.navigationStateStream.listen((state) {
      if (mounted) {
        _navStateNotifier.value = state;
        _updateMapForNavigation(state);
        _maybeRedrawPolylineFromNavigation();
        if (state.isNavigating) {
          _updateRideEtaFromNavigation(state);
        }
      }
    });

    // Listen to ride updates from Firestore
    _rideSubscription = Provider.of<FirestoreService>(context, listen: false)
        .getRideStream(widget.ride.id)
        .listen((ride) {
      if (ride != null && mounted) {
        setState(() {
          _currentRide = ride;
        });
        _handleRideUpdate(ride);
      }
    });

    // Listen to driver profile changes for real-time profile image updates
    final authService = Provider.of<AuthService>(context, listen: false);
    final driverId = authService.currentUser?.uid;
    if (driverId != null) {
      _profileSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(driverId)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          final data = snapshot.data() as Map<String, dynamic>;
          final photoUrl = data['photoUrl'] as String?;
          final name = data['name'] as String?;
          
          // Only reload if photoUrl changed
          if (photoUrl != null) {
            _updateDriverPuckImage(photoUrl, name);
          }
        }
      });
    }

    // Start driver location tracking
    if (driverId != null) {
      Provider.of<LocationService>(context, listen: false)
          .startDriverLocationTracking(driverId);
    }

    // Trigger initial marker setup
    _getDriverLatLng().then((loc) {
      if (loc != null && mounted) {
        _updateCurrentLocationMarker(loc);
      }
    });
  }

  @override
  void dispose() {
    _locationService.removeListener(_onLocationUpdate);
    _markerMovementController.dispose();
    _pulseController.dispose();
    _navStateNotifier.dispose();
    _navigationSubscription?.cancel();
    _rideSubscription?.cancel();
    _profileSubscription?.cancel();
    _navigationService.stopNavigation();
    
    // Cleanup Mapbox managers
    _circleAnnotationManager = null;
    _lineAnnotationManager = null;
    _pointAnnotationManager = null;
    _mapboxMap = null;

    final locationService = Provider.of<LocationService>(context, listen: false);
    locationService.stopDriverLocationTracking();
    
    super.dispose();
  }

  Future<void> _setupMarkers() async {
    if (_circleAnnotationManager == null) return;
    
    await _circleAnnotationManager!.deleteAll();
    
    _driverPuck = null;
    _pulseCircle = null;
    if (_driverPoint != null) {
      await _pointAnnotationManager?.delete(_driverPoint!);
      _driverPoint = null;
    }

    final currentStatus = _currentRide?.status ?? widget.ride.status;
    
    // Only show Pickup Marker if ride is NOT in progress
    if (currentStatus != RideStatus.inProgress) {
      await _circleAnnotationManager!.create(
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(coordinates: mapbox.Position(widget.ride.pickupLocation.longitude, widget.ride.pickupLocation.latitude)),
          circleRadius: 8.0,
          circleColor: const Color(0xFF4CAF50).value, // Consistent Green
          circleStrokeWidth: 2.0,
          circleStrokeColor: Colors.white.value,
        ),
      );
    }
    
    // Dropoff Marker
    await _circleAnnotationManager!.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(widget.ride.dropoffLocation.longitude, widget.ride.dropoffLocation.latitude)),
        circleRadius: 8.0,
        circleColor: const Color(0xFFF44336).value, // Consistent Red
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    // Draw route polyline
    await _drawRoute(widget.ride);
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _lineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    _routeLine = null;
    
    await _setupMarkers();
    _fitMapBounds();
  }

  void _onStyleLoaded(mapbox.StyleLoadedEventData data) async {
    if (_mapboxMap == null) return;
    
    _driver3DEnabled = false;
    _useLocationPuck = false; // Set to false to use manual circle marker

    // Disable built-in location component to avoid duplication with manual circle
    await _mapboxMap!.location.updateSettings(
      mapbox.LocationComponentSettings(
        enabled: false,
        pulsingEnabled: false,
        showAccuracyRing: false,
      ),
    );
  }

  Future<void> _loadDriverPuckImage() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final uid = auth.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      final name = data?['name'] as String?;
      final photoUrl = data?['photoUrl'] as String?;
      final initial = (name != null && name.isNotEmpty) ? name.substring(0, 1) : null;
      final bytes = await LocationHelpers.getProfilePuckMarkerImage(
        photoUrl: photoUrl,
        initial: initial,
        size: 150,
        pinColor: const Color(0xFFE53935),
      );
      if (!mounted) return;
      setState(() {
        _driverPuckImageBytes = bytes;
        _driverNameInitial = initial;
      });
    } catch (e) {
      // Silent fail; will fall back to circle
    }
  }

  // Update driver puck image when profile changes (real-time updates)
  Future<void> _updateDriverPuckImage(String? photoUrl, String? name) async {
    try {
      if (photoUrl == null) return;
      final initial = (name != null && name.isNotEmpty) ? name.substring(0, 1) : null;
      final bytes = await LocationHelpers.getProfilePuckMarkerImage(
        photoUrl: photoUrl,
        initial: initial,
        size: 150,
        pinColor: const Color(0xFFE53935),
      );
      if (!mounted) return;
      setState(() {
        _driverPuckImageBytes = bytes;
        _driverNameInitial = initial;
      });
    } catch (e) {
      // Silent fail; will fall back to circle
    }
  }

  bool _shouldRouteToDropoff(RideStatus status) {
    return status == RideStatus.pending || status == RideStatus.inProgress || status == RideStatus.completed;
  }

  // Helper method to find the nearest point on the route
  LatLng _findNearestRoutePoint(LatLng location, List<LatLng> route) {
    if (route.isEmpty) return location;
    
    double minDistance = double.infinity;
    LatLng nearestPoint = route.first;
    
    for (final point in route) {
      final distance = Geolocator.distanceBetween(
        location.latitude, location.longitude,
        point.latitude, point.longitude,
      );
      
      if (distance < minDistance) {
        minDistance = distance;
        nearestPoint = point;
      }
    }
    
    return nearestPoint;
  }

  // Optimized route geometry based on zoom level and navigation state
  List<LatLng> _getOptimizedRouteGeometry(List<LatLng> originalRoute) {
    if (originalRoute.length <= 2) return originalRoute;
    
    // Less aggressive simplification for better road adherence
    double tolerance;
    
    if (_navigationService.isNavigating) {
      // During navigation, keep more detail for accuracy
      tolerance = _currentZoom > 16 ? 0.00001 : 0.00005; // Very detailed
    } else {
      // Static view can be slightly simplified
      tolerance = _currentZoom > 14 ? 0.00002 : 0.0001;
    }
    
    return PolylineSimplifier.simplifyDouglasPeucker(originalRoute, tolerance);
  }

  Future<LatLng?> _getDriverLatLng() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final cached = locationService.currentPosition;
    if (cached != null) {
      return LatLng(cached.latitude, cached.longitude);
    }

    final currentPosition = await locationService.getCurrentLocation();
    if (currentPosition == null) return null;
    return LatLng(currentPosition.latitude, currentPosition.longitude);
  }

  Future<void> _zoomToDriverOnMap() async {
    if (_mapboxMap == null) return;
    final loc = await _getDriverLatLng();
    if (loc == null) return;
    _mapboxMap!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(loc.longitude, loc.latitude)),
        zoom: 16.0,
      ),
      mapbox.MapAnimationOptions(duration: 800),
    );
  }

  Future<void> _drawRoute(RideModel ride) async {
    if (_lineAnnotationManager == null) return;

    try {
      List<LatLng> routeGeometry;
      
      if (_navigationService.isNavigating) {
        // Use navigation service route with improved snapping
        routeGeometry = _navigationService.remainingRoutePoints;

        // Get current driver location with better accuracy
        final navState = _navigationService.currentState;
        LatLng? driverLoc;
        if (navState.currentLocation.latitude != 0 || navState.currentLocation.longitude != 0) {
          driverLoc = navState.currentLocation;
        } else {
          driverLoc = await _getDriverLatLng();
        }

        if (driverLoc != null && routeGeometry.isNotEmpty) {
          // Improved snapping: snap to route and ensure smooth connection
          final snapped = _navigationService.snapToRoute(driverLoc);
          
          // Check if snapped point is too far from actual location (>50m)
          final snapDistance = Geolocator.distanceBetween(
            driverLoc.latitude, driverLoc.longitude,
            snapped.latitude, snapped.longitude,
          );
          
          if (snapDistance > 50) {
            // If snap is too far, create a smooth connection from driver to route
            final nearestRoutePoint = _findNearestRoutePoint(driverLoc, routeGeometry);
            routeGeometry = [driverLoc, nearestRoutePoint, ...routeGeometry];
          } else {
            // Use snapped location for smooth route display
            routeGeometry = [snapped, ...routeGeometry];
          }
        }

        // Fallback to API if navigation route is insufficient
        if (routeGeometry.length <= 1) {
          final origin = driverLoc ?? LatLng(0, 0);
          final destination = _shouldRouteToDropoff(ride.status)
              ? LatLng(ride.dropoffLocation.latitude, ride.dropoffLocation.longitude)
              : LatLng(ride.pickupLocation.latitude, ride.pickupLocation.longitude);
               
          routeGeometry = await FareService.getRouteGeometry(
            originLat: origin.latitude,
            originLng: origin.longitude,
            destLat: destination.latitude,
            destLng: destination.longitude,
            includeTraffic: true,
          );
        }
      } else {
        // Static route display with improved accuracy
        final LatLng origin;
        final LatLng destination;

        if (ride.status == RideStatus.pending || 
            ride.status == RideStatus.accepted || 
            ride.status == RideStatus.driverArrived) {
          // Preview mode: show trip route (pickup to dropoff)
          origin = LatLng(ride.pickupLocation.latitude, ride.pickupLocation.longitude);
          destination = LatLng(ride.dropoffLocation.latitude, ride.dropoffLocation.longitude);
        } else {
          final driverLoc = await _getDriverLatLng();
          if (driverLoc == null) return;
          
          origin = driverLoc;
          destination = _shouldRouteToDropoff(ride.status)
              ? LatLng(ride.dropoffLocation.latitude, ride.dropoffLocation.longitude)
              : LatLng(ride.pickupLocation.latitude, ride.pickupLocation.longitude);
        }

        // Get high-quality route with traffic data for better accuracy
        routeGeometry = await FareService.getRouteGeometry(
          originLat: origin.latitude,
          originLng: origin.longitude,
          destLat: destination.latitude,
          destLng: destination.longitude,
          includeTraffic: true,
        );
      }

      if (routeGeometry.isEmpty) return;

      // Improved polyline simplification based on zoom level and navigation state
      final simplifiedGeometry = _getOptimizedRouteGeometry(routeGeometry);

      final positions = PolylineDecoder.toMapboxPositions(simplifiedGeometry);
      final color = AppTheme.primaryGreen.value;
      final width = _navigationService.isNavigating ? 8.0 : 6.0;

      if (_routeLine != null) {
        _routeLine!.geometry = mapbox.LineString(coordinates: positions);
        _routeLine!.lineColor = color;
        _routeLine!.lineWidth = width;
        _routeLine!.lineOpacity = 0.9; // Increased opacity for better visibility
        _routeLine!.lineJoin = mapbox.LineJoin.ROUND;
        await _lineAnnotationManager!.update(_routeLine!);
      } else {
        await _lineAnnotationManager!.deleteAll();

        // Draw route line using PolylineAnnotation with LineString geometry
        _routeLine = await _lineAnnotationManager!.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: positions),
            lineColor: color,
            lineWidth: width,
            lineOpacity: 0.9, // Increased opacity for better visibility
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      }

      // Route drawn with ${routeGeometry.length} points
    } catch (e) {
      // Error drawing route: $e
      _routeLine = null; // Reset on error
    }
  }

  void _maybeRedrawPolylineFromNavigation() async {
    if (!_navigationService.isNavigating || _lineAnnotationManager == null) return;

    final remainingPoints = _navigationService.remainingRoutePoints;
    if (remainingPoints.isEmpty) return;

    final now = DateTime.now();
    final last = _lastPolylineDraw;
    // Increased throttle from 500ms to 1000ms to reduce excessive redraws
    if (last != null && now.difference(last).inMilliseconds < 1000) return;
    _lastPolylineDraw = now;

    try {
      // Simplify remaining route for better performance
      final simplifiedRoute = _getOptimizedRouteGeometry(remainingPoints);
      
      final navState = _navigationService.currentState;
      final currentLoc = LatLng(navState.currentLocation.latitude, navState.currentLocation.longitude);
      final snapped = _navigationService.snapToRoute(currentLoc);
      
      // Always use snapped point for consistent route drawing
      // This prevents route jumps caused by inconsistent snapping logic
      final routeWithStart = [snapped, ...simplifiedRoute];
      final positions = PolylineDecoder.toMapboxPositions(routeWithStart);

      if (_routeLine != null) {
        _routeLine!.geometry = mapbox.LineString(coordinates: positions);
        _routeLine!.lineOpacity = 0.9;
        await _lineAnnotationManager!.update(_routeLine!);
      } else {
        // If route line was somehow lost, recreate it
        final color = AppTheme.primaryGreen.value;
        _routeLine = await _lineAnnotationManager!.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: positions),
            lineColor: color,
            lineWidth: 8.0,
            lineOpacity: 0.9,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      }
    } catch (e) {
      print('❌ Error updating navigation polyline: $e');
    }
  }

  void _updateRideEtaFromNavigation(NavigationState state) {
    final ride = _currentRide ?? widget.ride;
    if (ride.isPasaBuy) {
      if (_rideEtaMinutes != null) {
        setState(() {
          _rideEtaMinutes = null;
        });
      }
      return;
    }

    final status = ride.status;
    double? targetLat;
    double? targetLng;

    if (status == RideStatus.accepted || status == RideStatus.driverOnWay) {
      targetLat = ride.pickupLocation.latitude;
      targetLng = ride.pickupLocation.longitude;
    } else if (status == RideStatus.inProgress) {
      targetLat = ride.dropoffLocation.latitude;
      targetLng = ride.dropoffLocation.longitude;
    } else {
      if (_rideEtaMinutes != null) {
        setState(() {
          _rideEtaMinutes = null;
        });
      }
      return;
    }

    final current = state.currentLocation;
    final distance = Geolocator.distanceBetween(
      current.latitude,
      current.longitude,
      targetLat,
      targetLng,
    );

    final adjustedDistance = distance * 1.4;
    final etaMinutes = (adjustedDistance / 416.6).round();
    final value = (etaMinutes == 0 && distance > 100) ? 1 : etaMinutes;

    setState(() {
      _rideEtaMinutes = value;
    });
  }

  RideModel? _currentRideFromNavOrWidget() {
    // We don't store the live ride in state; fallback to the widget's ride.
    // Status updates are handled in the StreamBuilder via _handleRideUpdate.
    return widget.ride;
  }

  Future<void> _handleRideUpdate(RideModel ride) async {
    if (!mounted) return;

    if (_lastRideStatus != ride.status) {
      final oldStatus = _lastRideStatus;
      _lastRideStatus = ride.status;

      // Ride status updated: $oldStatus -> ${ride.status}

      // 1. Handle navigation stops and screen transitions
      if (ride.status == RideStatus.completed || ride.status == RideStatus.cancelled) {
        if (_navigationService.isNavigating) {
          // Stopping navigation due to ride completion/cancellation
          await _navigationService.stopNavigation();
        }

        // Navigate back to dashboard after a short delay to allow the user to see the success message
        if (mounted) {
          // Ride finished, preparing to navigate to dashboard...
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              // Navigating to driver dashboard
              Navigator.of(context).pushNamedAndRemoveUntil('/driver', (route) => false);
            }
          });
        }
        return;
      }

      // 2. Handle navigation starts/switches
      if (ride.status == RideStatus.driverOnWay) {
        // Start navigation to pickup if not already navigating there
        if (!_navigationService.isNavigating) {
          // Automatically starting navigation to pickup
          await _startNavigationToPickup(ride, enableVoice: true);
        }
      } else if (ride.status == RideStatus.driverArrived) {
        // Stop navigation and show preview of the full trip
        // Arrived at pickup, stopping navigation and showing preview
        if (_navigationService.isNavigating) {
          await _navigationService.stopNavigation();
        }
        _fitTripPreview();
      } else if (ride.status == RideStatus.inProgress) {
        // Switch navigation to dropoff
        // Automatically switching navigation to dropoff
        await _startNavigationToDropoff(ride, enableVoice: true);
        // Refresh markers to remove pickup location
        await _setupMarkers();
      }

      if (!mounted) return;
      await _drawRoute(ride);
    }
  }

  Future<void> _startNavigationToPickup(
    RideModel ride, {
    required bool enableVoice,
  }) async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final currentPosition = await locationService.getCurrentLocation();
    if (currentPosition == null) {
      return;
    }
    final current = LatLng(currentPosition.latitude, currentPosition.longitude);
    final pickupLatLng = LatLng(
      ride.pickupLocation.latitude,
      ride.pickupLocation.longitude,
    );

    await _navigationService.startNavigation(
      current,
      pickupLatLng,
      enableVoice: enableVoice,
    );
  }

  Future<void> _startNavigationToDropoff(
    RideModel ride, {
    required bool enableVoice,
  }) async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final currentPosition = await locationService.getCurrentLocation();
    if (currentPosition == null) {
      return;
    }
    final current = LatLng(currentPosition.latitude, currentPosition.longitude);
    final dropoffLatLng = LatLng(
      ride.dropoffLocation.latitude,
      ride.dropoffLocation.longitude,
    );

    await _navigationService.startNavigation(
      current,
      dropoffLatLng,
      enableVoice: enableVoice,
    );
  }

  Future<void> _launchExternalNavigation(LatLng destination) async {
    final googleMapsUrl = Uri.parse('google.navigation:q=${destination.latitude},${destination.longitude}&mode=d');
    final appleMapsUrl = Uri.parse('maps://?q=${destination.latitude},${destination.longitude}');
    
    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl);
      } else if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl);
      } else {
        // Fallback to web URL
        final webUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}');
        if (await canLaunchUrl(webUrl)) {
          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch maps';
        }
      }
    } catch (e) {
      if (mounted) {
        // Snackbar removed as requested
      }
    }
  }

  void _fitMapBounds() async {
    if (_mapboxMap == null) return;
    
    final coordinates = <mapbox.Point>[
      mapbox.Point(coordinates: mapbox.Position(widget.ride.pickupLocation.longitude, widget.ride.pickupLocation.latitude)),
      mapbox.Point(coordinates: mapbox.Position(widget.ride.dropoffLocation.longitude, widget.ride.dropoffLocation.latitude)),
    ];

    // Also include driver's current location if available
    final driverLoc = await _getDriverLatLng();
    if (driverLoc != null) {
      coordinates.add(mapbox.Point(coordinates: mapbox.Position(driverLoc.longitude, driverLoc.latitude)));
    }
    
    final camera = await _mapboxMap!.cameraForCoordinates(
      coordinates,
      mapbox.MbxEdgeInsets(top: 100, left: 60, bottom: 250, right: 60), // Adjusted for bottom sheet
      null,
      null,
    );
    
    _mapboxMap!.flyTo(
      camera,
      mapbox.MapAnimationOptions(duration: 1000),
    );
  }

  void _onCameraChangeListener(mapbox.CameraChangedEventData event) async {
    if (_mapboxMap == null) return;
    
    // Track current zoom level
    final cameraState = await _mapboxMap!.getCameraState();
    _currentZoom = cameraState.zoom;
    _currentBearing = cameraState.bearing;
    
    // Update marker scale dynamically based on zoom
    _updateMarkerScale();
    
    // Detect manual movement only when map is moving but not following
    // Note: Since Mapbox 2.17.0 removed explicit move listeners, 
    // we use camera change and let user explicitly re-enable following with the FAB
  }

  Future<void> _updateMarkerScale() async {
    final scale = (_currentZoom / 15.0).clamp(0.3, 1.3);
    
    if (_pointAnnotationManager != null && _driverPoint != null) {
      bool needsUpdate = false;
      if ((_driverPoint!.iconSize! - scale).abs() > 0.05) {
        _driverPoint!.iconSize = scale;
        needsUpdate = true;
      }
      // Keep icon upright on screen
      if ((_driverPoint!.iconRotate! - 0).abs() > 0.1) {
        _driverPoint!.iconRotate = 0;
        needsUpdate = true;
      }
      
      if (needsUpdate) {
        await _pointAnnotationManager!.update(_driverPoint!);
      }
    }
    
    if (_circleAnnotationManager != null && _driverPuck != null) {
      final radius = (10.0 * scale).clamp(3.0, 15.0);
      if ((_driverPuck!.circleRadius! - radius).abs() > 0.5) {
        _driverPuck!.circleRadius = radius;
        await _circleAnnotationManager!.update(_driverPuck!);
      }
    }
  }

  void _onMapTapped(mapbox.MapContentGestureContext context) {
    if (_isFollowing) {
      setState(() {
        _isFollowing = false;
      });
    }
  }

  void _fitTripPreview() async {
    if (_mapboxMap == null) return;
    
    final ride = _currentRide ?? widget.ride;
    final coordinates = <mapbox.Point>[
      mapbox.Point(coordinates: mapbox.Position(ride.pickupLocation.longitude, ride.pickupLocation.latitude)),
      mapbox.Point(coordinates: mapbox.Position(ride.dropoffLocation.longitude, ride.dropoffLocation.latitude)),
    ];
    
    final camera = await _mapboxMap!.cameraForCoordinates(
      coordinates,
      mapbox.MbxEdgeInsets(top: 120, left: 70, bottom: 300, right: 70), // Slightly larger padding for preview
      null,
      null,
    );
    
    _mapboxMap!.flyTo(
      camera,
      mapbox.MapAnimationOptions(duration: 1200),
    );
  }

  Future<void> _zoomIn() async {
    if (_mapboxMap == null) return;
    setState(() {
      _currentZoom = (_currentZoom + 1).clamp(2.0, 20.0);
    });
    final camera = await _mapboxMap!.getCameraState();
    _mapboxMap!.flyTo(
      mapbox.CameraOptions(zoom: _currentZoom, center: camera.center),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _zoomOut() async {
    if (_mapboxMap == null) return;
    setState(() {
      _currentZoom = (_currentZoom - 1).clamp(2.0, 20.0);
    });
    final camera = await _mapboxMap!.getCameraState();
    _mapboxMap!.flyTo(
      mapbox.CameraOptions(zoom: _currentZoom, center: camera.center),
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _recenter() async {
    if (_mapboxMap == null) return;
    
    final loc = await _getDriverLatLng();
    if (loc == null) return;

    setState(() {
      _isFollowing = true;
      _currentZoom = 18.0; // Exact zoom for navigation
    });

    final camera = mapbox.CameraOptions(
      center: mapbox.Point(coordinates: mapbox.Position(loc.longitude, loc.latitude)),
      zoom: _currentZoom,
      pitch: 50.0,
      bearing: _navStateNotifier.value?.heading ?? 0,
    );

    _mapboxMap!.flyTo(
      camera,
      mapbox.MapAnimationOptions(duration: 800),
    );
  }

  Future<void> _toggleMapZoom() async {
    if (_mapboxMap == null) return;

    setState(() {
      _isFollowing = false;
    });

    if (_isZoomedIn) {
      setState(() {
        _isZoomedIn = false;
      });
      _fitMapBounds();
      return;
    }

    final loc = await _getDriverLatLng();
    final center = loc ?? LatLng(widget.ride.pickupLocation.latitude, widget.ride.pickupLocation.longitude);
    setState(() {
      _isZoomedIn = true;
    });
    _mapboxMap!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(center.longitude, center.latitude)),
        zoom: 16.0,
      ),
      mapbox.MapAnimationOptions(duration: 800),
    );
  }

  double _lastPulseRadius = 0;
  bool _isUpdatingPulse = false;
  bool _isUpdatingLocation = false;

  Future<void> _updatePulseMarker() async {
    if (_circleAnnotationManager == null || !mounted || _isUpdatingPulse) return;

    // Check if we have a valid anchor (either point or puck)
    final anchorGeometry = _driverPoint != null
        ? _driverPoint!.geometry
        : _driverPuck?.geometry;
        
    if (anchorGeometry == null) return;

    try {
      _isUpdatingPulse = true;
      // Scale pulse if using image marker (which is much larger than the circle fallback)
      final bool isImageMarker = _driverPoint != null;
      final double sizeMultiplier = isImageMarker ? 1.8 : 1.0; 
      final double baseRadius = _pulseAnimation.value * sizeMultiplier;
      final double scale = (_currentZoom / 15.0).clamp(0.3, 1.3);
      final double displayRadius = baseRadius * scale;
      
      // Calculate opacity and color
      // Adjust opacity curve for larger pulse
      final double progress = (_pulseAnimation.value - 8.0) / (22.0 - 8.0);
      final opacity = (1.0 - progress).clamp(0.0, 0.4);
      final int colorValue = AppTheme.primaryGreen.value;

      // Only update if radius change is significant OR color changed
      // We can track last color to force update on change
      if (_pulseCircle != null) {
        // Force update if color changed
        if (_pulseCircle!.circleColor != colorValue || (displayRadius - _lastPulseRadius).abs() >= 0.5) {
           _pulseCircle!
            ..circleRadius = displayRadius
            ..circleOpacity = opacity
            ..geometry = anchorGeometry
            ..circleColor = colorValue;
          await _circleAnnotationManager!.update(_pulseCircle!);
          _lastPulseRadius = displayRadius;
        }
      } else {
        _pulseCircle = await _circleAnnotationManager!.create(
          mapbox.CircleAnnotationOptions(
            geometry: anchorGeometry,
            circleRadius: displayRadius,
            circleColor: colorValue,
            circleOpacity: opacity,
            circleStrokeWidth: 0.0,
          ),
        );
        _lastPulseRadius = displayRadius;
      }
    } catch (e) {
      // Ignore animation update errors
    } finally {
      _isUpdatingPulse = false;
    }
  }

  bool _isUpdatingGeometry = false;

  void _onLocationUpdate() {
    if (!mounted) return;
    // If navigation service is active, let it handle updates to avoid conflict/jitter
    if (_navigationService.isNavigating) return;
    
    final pos = _locationService.currentPosition;
    if (pos != null) {
      _updateCurrentLocationMarker(LatLng(pos.latitude, pos.longitude), heading: pos.heading);
    }
  }

  void _onMarkerAnimationTick() {
    if (!mounted || _animStartLocation == null || _animTargetLocation == null) return;
    
    final t = _markerMovementController.value;
    final lat = _animStartLocation!.latitude + (_animTargetLocation!.latitude - _animStartLocation!.latitude) * t;
    final lng = _animStartLocation!.longitude + (_animTargetLocation!.longitude - _animStartLocation!.longitude) * t;
    
    final newPos = LatLng(lat, lng);
    
    double? newHeading;
    if (_animStartHeading != null && _animTargetHeading != null) {
      var diff = _animTargetHeading! - _animStartHeading!;
      if (diff > 180) diff -= 360;
      if (diff < -180) diff += 360;
      newHeading = _animStartHeading! + diff * t;
    }
    
    _currentDisplayedLocation = newPos;
    if (newHeading != null) _currentDisplayedHeading = newHeading;
    
    _updateMarkerGeometry(newPos, heading: newHeading);
  }

  Future<void> _updateMarkerGeometry(LatLng location, {double? heading}) async {
    if (_isUpdatingGeometry) return;
    _isUpdatingGeometry = true;
    
    try {
      if (_pointAnnotationManager != null && _driverPoint != null) {
        _driverPoint!.geometry = mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude));
        // Keep icon upright on screen
        _driverPoint!.iconRotate = 0;
        await _pointAnnotationManager!.update(_driverPoint!);
      } else if (_circleAnnotationManager != null && _driverPuck != null) {
        _driverPuck!.geometry = mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude));
        await _circleAnnotationManager!.update(_driverPuck!);
      }

      // Update pulse circle position to follow the marker
      final anchorGeometry = _driverPoint != null ? _driverPoint!.geometry : _driverPuck?.geometry;
      if (anchorGeometry != null && _pulseCircle != null && _circleAnnotationManager != null) {
        _pulseCircle!.geometry = anchorGeometry;
        await _circleAnnotationManager!.update(_pulseCircle!);
      }
    } catch (e) {
      // Ignore transient update errors
    } finally {
      _isUpdatingGeometry = false;
    }
  }

  Future<void> _updateCurrentLocationMarker(LatLng location, {double? heading}) async {
    if ((_circleAnnotationManager == null && _pointAnnotationManager == null) || _isUpdatingLocation) return;

    // 1. Initial Creation if needed
    if (_driverPoint == null && _driverPuck == null) {
      try {
        _isUpdatingLocation = true;
        
        if (_driverPuckImageBytes == null) {
          await _loadDriverPuckImage();
        }
        
        if (_driverPuckImageBytes != null) {
          _driverPoint = await _pointAnnotationManager!.create(
            mapbox.PointAnnotationOptions(
              geometry: mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude)),
              image: _driverPuckImageBytes!,
              iconSize: (_currentZoom / 15.0).clamp(0.3, 1.3),
              iconAnchor: mapbox.IconAnchor.BOTTOM,
              iconRotate: 0,
            ),
        );
        } else {
          _driverPuck = await _circleAnnotationManager!.create(
            mapbox.CircleAnnotationOptions(
              geometry: mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude)),
              circleRadius: 10.0,
              circleColor: const Color(0xFF4285F4).value,
              circleStrokeWidth: 2.0,
              circleStrokeColor: Colors.white.value,
            ),
          );
        }
        
        // Initialize displayed state
        _currentDisplayedLocation = location;
        _currentDisplayedHeading = heading ?? 0;
        
      } catch (e) {
        print('Error creating driver puck: $e');
      } finally {
        _isUpdatingLocation = false;
      }
      return;
    }

    // 2. Animation Logic
    if (_currentDisplayedLocation == null) {
      _currentDisplayedLocation = location;
      _updateMarkerGeometry(location, heading: heading);
      return;
    }

    // Check distance for snap vs animate
    final dist = Geolocator.distanceBetween(
      _currentDisplayedLocation!.latitude, _currentDisplayedLocation!.longitude,
      location.latitude, location.longitude,
    );
    
    // If distance is large (> 500m), snap immediately
    if (dist > 500) {
      _currentDisplayedLocation = location;
      _currentDisplayedHeading = heading ?? _currentDisplayedHeading;
      _updateMarkerGeometry(location, heading: heading);
      return;
    }
    
    // Set up animation
    _animStartLocation = _currentDisplayedLocation;
    _animTargetLocation = location;
    _animStartHeading = _currentDisplayedHeading;
    
    // Stabilize heading to prevent swinging:
    // 1. If distance moved is small (< 2m), ignore heading updates (assume stationary noise)
    // 2. If heading change is small (< 5 degrees), ignore it (jitter)
    double targetH = heading ?? _currentDisplayedHeading;
    
    // Calculate heading difference
    double diff = (targetH - _currentDisplayedHeading).abs();
    if (diff > 180) diff = 360 - diff;

    if (dist < 2.0) {
      // Too close, keep old heading
      targetH = _currentDisplayedHeading;
    } else if (diff < 5.0) {
       // Ignore small jitter
       targetH = _currentDisplayedHeading;
    }
    
    _animTargetHeading = targetH;
    
    // Reset and start animation
    _markerMovementController.duration = const Duration(milliseconds: 1000);
    _markerMovementController.forward(from: 0.0);
  }

  double? _lastHeading;
  LatLng? _lastCameraLocation;



  Future<void> _updateMapForNavigation(NavigationState state) async {
    if (_mapboxMap == null || !state.isNavigating) return;

    // Update current bearing to match navigation heading
    _currentBearing = state.heading;

    final location = state.currentLocation;

    // Determine motion state using last sample (m/s threshold ~0.5)
    final now = DateTime.now();
    if (_lastMotionSampleLoc != null && _lastMotionSampleTime != null) {
      final dtMs = now.difference(_lastMotionSampleTime!).inMilliseconds.clamp(1, 1000000);
      final dist = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        _lastMotionSampleLoc!.latitude,
        _lastMotionSampleLoc!.longitude,
      );
      final speed = dist / (dtMs / 1000.0); // m/s
      final bool moving = speed > 0.5; // ~1.8 km/h threshold
      if (moving != _isDriverMoving) {
        setState(() {
          _isDriverMoving = moving;
        });
        // Adjust pulse speed: faster when moving, slower when idle
        final targetDuration = moving ? const Duration(milliseconds: 1200) : const Duration(milliseconds: 2200);
        if (_pulseController.duration != targetDuration) {
          _pulseController
            ..duration = targetDuration
            ..reset()
            ..repeat();
        }
      }
    }
    _lastMotionSampleLoc = location;
    _lastMotionSampleTime = now;

    await _updateCurrentLocationMarker(location, heading: state.heading);

    if (!_isFollowing) return;

    // Check if change is significant enough to update camera (smoothness optimization)
    // Reduced thresholds to improve responsiveness while maintaining smoothness
    final bool significantHeading = _lastHeading == null || 
        (state.heading - _lastHeading!).abs() > 1.0;
    
    final bool significantLocation = _lastCameraLocation == null ||
        (location.latitude - _lastCameraLocation!.latitude).abs() > 0.00002 ||
        (location.longitude - _lastCameraLocation!.longitude).abs() > 0.00002;

    if (!significantHeading && !significantLocation) {
      // Force update bearing even if location hasn't moved significantly
      // to ensure rotation happens during stops if compass changes
      if (significantHeading) {
        _lastHeading = state.heading;
        final camera = mapbox.CameraOptions(
          bearing: state.heading,
        );
        _mapboxMap!.easeTo(
          camera,
          mapbox.MapAnimationOptions(duration: 300),
        );
      }
      return;
    }

    _lastHeading = state.heading;
    _lastCameraLocation = location;

    // Center map on current location with heading using easeTo for smoothness
    final camera = mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(
          location.longitude,
          location.latitude,
        ),
      ),
      zoom: _currentZoom,
      bearing: state.heading,
      pitch: 45.0,
    );
    
    _mapboxMap!.easeTo(
      camera,
      mapbox.MapAnimationOptions(duration: 300),
    );
  }

  Future<void> _loadMotorcycleIcon() async {
    try {
      final bytes = await LocationHelpers.get3DUserMarkerImage(size: 80);
      if (mounted) {
        setState(() {
          _motorcycleIcon = bytes;
        });
      }
    } catch (e) {
      print('Error loading motorcycle icon: $e');
    }
  }

  Future<void> _updateRideStatus(RideStatus newStatus) async {
    setState(() => _isLoading = true);
    
    // API URL: $uriver updating status from ${_currentRide?.status} to: $newStatus at ${DateTime.now()}');

    try {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);
      final driverId = authService.currentUser?.uid;
      
      // Update ride status with authorization check
      await firestoreService.updateRideStatus(widget.ride.id, newStatus, driverId: driverId);

      
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Snackbar removed as requested
      }
    }
  }

  String _getStatusText(RideStatus status) {
    switch (status) {
      case RideStatus.pending: return widget.ride.isPasaBuy ? 'New PasaBuy Request' : 'New Ride Request';
      case RideStatus.accepted: return widget.ride.isPasaBuy ? 'PasaBuy Accepted' : 'Trip Accepted';
      case RideStatus.driverOnWay: return widget.ride.isPasaBuy ? 'Going to Pickup' : 'On The Way';
      case RideStatus.driverArrived: return 'Arrived at Pickup';
      case RideStatus.inProgress: return widget.ride.isPasaBuy ? 'Delivery In Progress' : 'Trip In Progress';
      case RideStatus.completed: return widget.ride.isPasaBuy ? 'Delivery Completed' : 'Trip Completed';
      default: return widget.ride.isPasaBuy ? 'PasaBuy Details' : 'Ride Details';
    }
  }

  String _getStatusSubtext(RideStatus status) {
    switch (status) {
      case RideStatus.pending: return 'Review the route before accepting';
      case RideStatus.accepted: return widget.ride.isPasaBuy ? 'Head to pickup location' : 'Head to pickup location';
      case RideStatus.driverOnWay: return widget.ride.isPasaBuy ? 'Driving to pickup location' : 'Driving to pickup location';
      case RideStatus.driverArrived: return widget.ride.isPasaBuy ? 'Buy the items requested' : 'Waiting for passenger';
      case RideStatus.inProgress: return 'Drive safely to destination';
      case RideStatus.completed: return 'Thank you for your service';
      default: return 'Trip Information';
    }
  }

  Color _getStatusColor(RideStatus status) {
    switch (status) {
      case RideStatus.driverArrived: return Colors.orange;
      case RideStatus.completed: return AppTheme.primaryGreen;
      default: return AppTheme.primaryGreen;
    }
  }

  IconData _getStatusIcon(RideStatus status) {
    switch (status) {
      case RideStatus.driverArrived: return Icons.location_on_rounded;
      case RideStatus.inProgress: return Icons.directions_car_rounded;
      case RideStatus.completed: return Icons.verified_rounded;
      default: return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _currentRide ?? widget.ride;
    
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushReplacementNamed('/driver');
        return false;
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // Full screen map
              _buildFullScreenMap(ride),
              // Compact status chip
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: _buildCompactStatusChip(ride.status),
              ),
              // Navigation overlay
              ValueListenableBuilder<NavigationState?>(
                valueListenable: _navStateNotifier,
                builder: (context, navState, child) {
                  return _buildNavigationInfo(navState);
                },
              ),
              
              // FABs (Center on me, Zoom etc)
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).size.height * 0.3 + 20, // Above bottom sheet
                child: Column(
                  children: [
                    // Recenter / Follow
                    if (!_isFollowing)
                      AnimatedMapButton(
                        onPressed: _recenter,
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.white,
                        heroTag: 'recenter_on_me',
                        child: const Icon(Icons.navigation_rounded, size: 28),
                      )
                    else
                      AnimatedMapButton(
                        onPressed: () {
                          setState(() {
                            _isFollowing = false;
                          });
                        },
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryGreen,
                        heroTag: 'following_me',
                        child: const Icon(Icons.my_location_rounded),
                      ),
                  ],
                ),
              ),

              // Draggable bottom sheet
              _buildDraggableSheet(ride),
              
              // Loading Overlay
              if (_isLoading)
                Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String heroTag,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: const Color(0xFF1A1A1A),
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableSheet(RideModel ride) {
    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.15,
      maxChildSize: 0.8,
      snap: true,
      builder: (context, scrollController) {
        return _buildCompactBottomSheet(ride, scrollController);
      },
    );
  }

  Widget _buildCompactStatusChip(RideStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _getStatusColor(status),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _getStatusColor(status).withOpacity(0.4),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _getStatusText(status).toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenMap(RideModel ride) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: kIsWeb
          ? Container(
              color: Colors.blueGrey[100],
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map, size: 64, color: Colors.blueGrey[400]),
                    SizedBox(height: 16),
                    Text(
                      'Map View',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey[700],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Trip from: ${ride.pickupAddress}',
                      style: TextStyle(color: Colors.blueGrey[600]),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'To: ${ride.dropoffAddress}',
                      style: TextStyle(color: Colors.blueGrey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : mapbox.MapWidget(
              key: const ValueKey("mapbox_active_trip_full"),
              onMapCreated: _onMapCreated,
              onStyleLoadedListener: _onStyleLoaded,
              onCameraChangeListener: _onCameraChangeListener,
              onTapListener: _onMapTapped,
              cameraOptions: mapbox.CameraOptions(
                center: mapbox.Point(coordinates: mapbox.Position(ride.pickupLocation.longitude, ride.pickupLocation.latitude)),
                zoom: 15.0,
              ),
            ),
    );
  }

  Widget _buildCompactBottomSheet(RideModel ride, ScrollController scrollController) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Passenger info (compact)
                  _buildCompactPassengerCard(ride),
                  
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      _buildInfoChip(
                        Icons.timer_outlined,
                        () {
                          if (_rideEtaMinutes != null && !ride.isPasaBuy) {
                            return '$_rideEtaMinutes min';
                          }
                          if (ride.estimatedDuration > 0) {
                            return '${ride.estimatedDuration} min';
                          }
                          return '--';
                        }(),
                        const Color(0xFF4285F4).withOpacity(0.1),
                        const Color(0xFF4285F4),
                      ),
                      const SizedBox(width: 8),
                      _buildInfoChip(
                        Icons.account_balance_wallet_outlined,
                        FareService.formatFare(ride.fare),
                        const Color(0xFF4CAF50).withOpacity(0.1),
                        const Color(0xFF4CAF50),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  
                  // Expanded content
                  _buildTripRoute(ride),
                  
                  if (ride.isPasaBuy && ride.itemDescription != null) ...[
                    const SizedBox(height: 24),
                    _buildPasaBuyItems(ride.itemDescription!),
                  ],
                  
                  if (ride.notes != null && ride.notes!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildRideNotes(ride.notes!),
                  ],
                  
                  const SizedBox(height: 24),
                  _buildFareInfo(ride),
                  
                  const SizedBox(height: 24),
                  
                  // Action buttons
                  _buildCompactActionButtons(ride),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color bgColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: iconColor.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripRoute(RideModel ride) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TRIP ROUTE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Color(0xFF9E9E9E),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                const Icon(Icons.circle, size: 12, color: Color(0xFF4CAF50)),
                Container(
                  width: 2,
                  height: 30,
                  color: Colors.grey[200],
                ),
                const Icon(Icons.location_on, size: 14, color: Color(0xFFF44336)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ride.pickupAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    ride.dropoffAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFareInfo(RideModel ride) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAYMENT INFO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Color(0xFF9E9E9E),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              _buildFareRow('Total Fare', FareService.formatFare(ride.fare), isTotal: true),
              const Divider(height: 24),
              _buildFareRow('Requested at', DateFormat('hh:mm a').format(ride.requestedAt)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFareRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isTotal ? const Color(0xFF1A1A1A) : Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            color: isTotal ? AppTheme.primaryGreen : const Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildRideNotes(String notes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RIDE NOTES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Color(0xFF9E9E9E),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withOpacity(0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 18, color: Colors.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  notes,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasaBuyItems(String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ITEMS TO BUY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Color(0xFF9E9E9E),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 18, color: AppTheme.primaryGreen),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactPassengerCard(RideModel ride) {
    return FutureBuilder<DocumentSnapshot>(
      future: _passengerInfoFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                Text('Loading...', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.person_off_rounded, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text('Passenger unavailable', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              ],
            ),
          );
        }

        final passengerData = snapshot.data!.data() as Map<String, dynamic>?;
        if (passengerData == null) {
          return const Text('Passenger data is not available.');
        }
        final passengerName = passengerData['name'] ?? 'Unknown';
        final passengerPhone = passengerData['phone'] ?? '';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    passengerName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passengerName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${ride.pickupAddress.split(',').first} → ${ride.dropoffAddress.split(',').first}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (passengerPhone.isNotEmpty)
                IconButton(
                  onPressed: () => _makePhoneCall(passengerPhone),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                ),
              const SizedBox(width: 8),
              if (ride.status != RideStatus.pending)
                ChatButton(
                  contextId: ride.id,
                  collectionPath: 'rides',
                  otherUserName: passengerName,
                  otherUserId: ride.passengerId,
                  mini: true,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactActionButtons(RideModel ride) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    if (ride.status == RideStatus.pending) {
      return Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () async {
                try {
                  final driverId = authService.currentUser?.uid;
                  if (driverId != null) {
                    // Show confirmation dialog
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (BuildContext context) {
                        return Dialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                                  child: const Icon(Icons.close_rounded, color: Colors.red, size: 32),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  ride.isPasaBuy ? 'Decline Request?' : 'Decline Ride?',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  ride.isPasaBuy 
                                    ? 'Are you sure you want to decline this PasaBuy request?' 
                                    : 'Are you sure you want to decline this ride request?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500)
                                ),
                                const SizedBox(height: 32),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton(
                                        onPressed: () => Navigator.of(context).pop(false),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: const StadiumBorder(),
                                        ),
                                        child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w900, fontSize: 16)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => Navigator.of(context).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: const StadiumBorder(),
                                        ),
                                        child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );

                    if (confirmed != true) return;

                    if (ride.isPasaBuy) {
                      await firestoreService.declinePasaBuyRequest(ride.id, driverId);
                    } else {
                      await firestoreService.declineRideRequest(ride.id, driverId);
                    }
                    if (mounted) Navigator.of(context).pop();
                  }
                } catch (e) {
                  if (mounted) {
                    // Snackbar removed as requested
                  }
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: EdgeInsets.zero,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () async {
                try {
                  final driverId = authService.currentUser?.uid;
                  if (driverId != null) {
                    if (ride.isPasaBuy) {
                      await firestoreService.acceptPasaBuyRequest(
                        ride.id,
                        driverId,
                        authService.currentUserModel?.name ?? 'Driver',
                      );
                    } else {
                      await firestoreService.acceptRideRequest(ride.id, driverId);
                    }
                    // Snackbar removed as requested
                  }
                } catch (e) {
                  if (mounted) {
                    // Snackbar removed as requested
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                ride.isPasaBuy ? 'Accept PasaBuy' : 'Accept Ride',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      );
    }

    if (ride.status == RideStatus.accepted) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _startGoingToPickup,
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: Text(
                ride.isPasaBuy ? 'Go to Store' : 'Go to Pickup',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      );
    }

    if (ride.status == RideStatus.driverOnWay) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () => _updateRideStatus(RideStatus.driverArrived),
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                ride.isPasaBuy ? 'Arrived at Store' : 'Arrived',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.zero,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      );
    }

    if (ride.status == RideStatus.driverArrived) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: () => ride.isPasaBuy ? _updateRideStatus(RideStatus.inProgress) : _startTrip(ride),
          icon: Icon(ride.isPasaBuy ? Icons.shopping_cart_rounded : Icons.play_arrow_rounded, size: 18),
          label: Text(ride.isPasaBuy ? 'Done Buying' : 'Start Trip', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: EdgeInsets.zero,
          ),
        ),
      );
    }

    if (ride.status == RideStatus.inProgress) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () async {
                if (!ride.isPasaBuy) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) {
                      return Dialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                                child: const Icon(Icons.check_rounded, color: Colors.green, size: 32),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Complete Trip?',
                                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Are you sure you want to mark this trip as completed?',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 15, color: Color(0xFF757575), fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => Navigator.of(context).pop(false),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: const StadiumBorder(),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(color: Color(0xFF757575), fontWeight: FontWeight.w900, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => Navigator.of(context).pop(true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primaryGreen,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: const StadiumBorder(),
                                      ),
                                      child: const Text(
                                        'Complete',
                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );

                  if (confirmed != true) return;
                }

                await _updateRideStatus(RideStatus.completed);
              },
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: Text(ride.isPasaBuy ? 'Delivered' : 'Complete Trip', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else if (mounted) {
      // Snackbar removed as requested
    }
  }

  Future<void> _startGoingToPickup() async {
    try {
      // Validate pickup coordinates
      final pickupLatLng = LatLng(
        widget.ride.pickupLocation.latitude,
        widget.ride.pickupLocation.longitude,
      );
      
      if (pickupLatLng.latitude == 0 || pickupLatLng.longitude == 0) {
        throw Exception('Invalid pickup location coordinates');
      }

      await _updateRideStatus(RideStatus.driverOnWay);
      
      final loc = await _getDriverLatLng();
      if (loc != null) {
        await _updateCurrentLocationMarker(loc);
      }
      await _zoomToDriverOnMap();
      
      // Snackbar removed as requested
    } catch (e) {
      print('Error starting navigation: $e');
      if (mounted) {
        // Snackbar removed as requested
      }
    }
  }

  Future<void> _startTrip(RideModel ride) async {
    try {
      await _updateRideStatus(RideStatus.inProgress);
      await _zoomToDriverOnMap();
      // Snackbar removed as requested
    } catch (e) {
      if (mounted) {
        // Snackbar removed as requested
      }
    }
  }

  Widget _buildNavigationInfo(NavigationState? navState) {
    if (!_navigationService.isNavigating || navState == null) {
      return const SizedBox.shrink();
    }

    // Determine target location for external nav
    final targetLocation = navState.destination;

    return Positioned(
      top: 70, // Keep position below status chip
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A).withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Turn Icon / Direction Section
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2D2D),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            navState.currentInstruction != null 
                              ? _getManeuverIcon(
                                  navState.currentInstruction!.maneuverType,
                                  navState.currentInstruction!.maneuverModifier,
                                )
                              : Icons.navigation_rounded,
                            color: const Color(0xFF4CAF50),
                            size: 32,
                          ),
                        ),
                        if (navState.distanceToNextTurn != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              navState.distanceToNextTurn! > 1000 
                                ? '${(navState.distanceToNextTurn! / 1000).toStringAsFixed(1)} km'
                                : '${navState.distanceToNextTurn!.round()} m',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(width: 16),
                    
                    // Info Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (navState.currentInstruction != null)
                            Text(
                              navState.currentInstruction!.instruction,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.3,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Remaining Distance
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF4CAF50).withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.directions_car_rounded,
                                      size: 14,
                                      color: Color(0xFF4CAF50),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${(navState.remainingDistance / 1000).toStringAsFixed(1)} km',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF4CAF50),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // ETA
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time_rounded,
                                      size: 14,
                                      color: Colors.grey[300],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${(navState.remainingDuration).round()} min',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey[300],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            
          ],
        ),
      ),
    );
  }

  IconData _getManeuverIcon(String type, String? modifier) {
    final t = type.toLowerCase();
    final m = modifier?.toLowerCase() ?? '';

    // Arrive/Depart
    if (t == 'arrive') return Icons.flag_rounded;
    if (t == 'depart') return Icons.trip_origin_rounded;

    // Roundabouts
    if (t.contains('roundabout') || t.contains('rotary')) {
      if (m.contains('left')) return Icons.roundabout_left_rounded;
      return Icons.roundabout_right_rounded;
    }

    // U-Turn
    if (m == 'uturn' || t == 'u-turn') return Icons.u_turn_left_rounded;

    // Common Types
    if (t == 'continue' || t.contains('new name') || t == 'stay') return Icons.straight_rounded;
    if (t == 'end of road') {
      if (m.contains('left')) return Icons.turn_left_rounded;
      if (m.contains('right')) return Icons.turn_right_rounded;
      return Icons.stop_circle_outlined;
    }

    // Turns (using modifier primarily)
    if (m == 'sharp right') return Icons.turn_sharp_right_rounded;
    if (m == 'right') return Icons.turn_right_rounded;
    if (m == 'slight right') return Icons.turn_slight_right_rounded;
    
    if (m == 'sharp left') return Icons.turn_sharp_left_rounded;
    if (m == 'left') return Icons.turn_left_rounded;
    if (m == 'slight left') return Icons.turn_slight_left_rounded;
    
    if (m == 'straight') return Icons.straight_rounded;

    // Merge/Fork/Ramps
    if (t == 'merge') return Icons.merge_type_rounded;
    if (t == 'fork') return Icons.alt_route_rounded;
    if (t == 'off ramp' || t == 'on ramp') {
       if (m.contains('left')) return Icons.turn_slight_left_rounded;
       if (m.contains('right')) return Icons.turn_slight_right_rounded;
       return Icons.merge_type_rounded;
    }

    // Fallbacks
    if (m.contains('right')) return Icons.turn_right_rounded;
    if (m.contains('left')) return Icons.turn_left_rounded;

    return Icons.navigation_rounded;
  }

  void _showLocationDisabledDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.location_off, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Location Services Disabled'),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Open location settings
              await Geolocator.openLocationSettings();
              // Try starting navigation again after settings are opened
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _startGoingToPickup();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D2D2D),
              foregroundColor: Colors.white,
            ),
            child: const Text('Enable Location'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.location_disabled, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Location Permission Required'),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Open app settings
              await Geolocator.openAppSettings();
              // Try starting navigation again after settings are opened
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _startGoingToPickup();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D2D2D),
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
