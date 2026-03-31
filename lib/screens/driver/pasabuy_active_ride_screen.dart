import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../../widgets/location_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import '../../models/pasabuy_model.dart';
import '../../models/lat_lng.dart' as app_latlng;
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/navigation_service.dart';
import '../../services/fare_service.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import '../../config/credentials_config.dart';
import '../../widgets/chat_button.dart';
import '../../widgets/common/animated_map_button.dart';
import '../../utils/polyline_decoder.dart';
import '../../utils/polyline_simplifier.dart';

class PasaBuyActiveRideScreen extends StatefulWidget {
  final String requestId;
  final PasaBuyModel request;

  const PasaBuyActiveRideScreen({
    super.key,
    required this.requestId,
    required this.request,
  });

  @override
  State<PasaBuyActiveRideScreen> createState() => _PasaBuyActiveRideScreenState();
}

class _PasaBuyActiveRideScreenState extends State<PasaBuyActiveRideScreen> with TickerProviderStateMixin {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleAnnotationManager;
  mapbox.PolylineAnnotationManager? _lineAnnotationManager;
  mapbox.PointAnnotationManager? _driverAnnotationManager;
  mapbox.PolylineAnnotation? _routeLine;
  mapbox.CircleAnnotation? _driverPuck;
  mapbox.PointAnnotation? _driverPoint;
  Uint8List? _motorcycleIcon;
  Uint8List? _driverPuckImageBytes;
  String? _driverNameInitial;
  mapbox.CircleAnnotation? _pickupMarker;
  mapbox.CircleAnnotation? _dropoffMarker;
  
  bool _isLoading = false;
  bool _isZoomedIn = false;
  bool _isFollowing = true;
  double _currentZoom = 17.5;
  ScrollController? _sheetScrollController;
  bool _useLocationPuck = false;
  String _driverModelSourceId = 'driver_model_source';
  String _driverModelLayerId = 'driver_model_layer';
  bool _driver3DEnabled = false;
  bool _isCreatingPuck = false; // Guard against race condition
  mapbox.CircleAnnotation? _pulseCircle;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Animation for smooth marker movement
  late AnimationController _markerMovementController;
  app_latlng.LatLng? _currentDisplayedLocation;
  double _currentDisplayedHeading = 0;
  app_latlng.LatLng? _animStartLocation;
  app_latlng.LatLng? _animTargetLocation;
  double? _animStartHeading;
  double? _animTargetHeading;
  
  bool _isDriverMoving = false;
  bool _isUpdatingPulse = false;
  double _lastPulseRadius = 0;
  DateTime? _lastMotionSampleTime;
  app_latlng.LatLng? _lastMotionSampleLoc;
  late LocationService _locationService;
  
  // Track latest request data
  late PasaBuyModel _currentRequest;
  
  // Navigation State
  StreamSubscription<NavigationState>? _navSubscription;
  StreamSubscription<PasaBuyModel?>? _pasaBuySubscription;
  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  final ValueNotifier<NavigationState?> _navStateNotifier = ValueNotifier(null);
  final NavigationService _navigationService = NavigationService();
  PasaBuyStatus? _lastStatus;
  DateTime? _lastPolylineDraw;
  double? _lastHeading;
  app_latlng.LatLng? _lastCameraLocation;
  double _currentBearing = 0.0;

  // Workflow tracking
  // Timer? _shoppingTimer;
  // int _shoppingTimeElapsed = 0; // in seconds
  Map<String, bool> _checklist = {};
  Timer? _workflowTimeoutTimer;
  bool _hasStartedStoreTrip = false;
  int? _etaToPickup;
  Future<DocumentSnapshot>? _passengerInfoFuture;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.request;
    _lastStatus = widget.request.status;
    _passengerInfoFuture = FirebaseFirestore.instance.collection('users').doc(widget.request.passengerId).get();
    _loadMotorcycleIcon();
    _loadDriverPuckImage();
    
    _initNavigation();
    _initPasaBuyListener();
    _initChecklist();

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authService = Provider.of<AuthService>(context, listen: false);
      final driverId = authService.currentUser?.uid;
      if (driverId != null) {
        Provider.of<LocationService>(context, listen: false)
            .startDriverLocationTracking(driverId);
      }
      _resetWorkflowTimeout();

      // Trigger initial marker setup
      _getDriverLatLng().then((loc) {
        if (loc != null && mounted) {
          _updateCurrentLocationMarker(loc);
        }
      });
    });
  }

  @override
  void dispose() {
    _locationService.removeListener(_onLocationUpdate);
    _markerMovementController.dispose();
    // _shoppingTimer?.cancel();
    _workflowTimeoutTimer?.cancel();
    
    final locationService = Provider.of<LocationService>(context, listen: false);
    locationService.stopDriverLocationTracking();
    
    _navSubscription?.cancel();
    _pasaBuySubscription?.cancel();
    _profileSubscription?.cancel();
    _navigationService.stopNavigation();
    _navStateNotifier.dispose();
    _pulseController.dispose();
    
    _circleAnnotationManager = null;
    _lineAnnotationManager = null;
    _driverAnnotationManager = null;
    _mapboxMap = null;
    
    super.dispose();
  }

  void _initChecklist() {
    final items = _currentRequest.itemDescription.split(RegExp(r'[\n,]'));
    for (var item in items) {
      if (item.trim().isNotEmpty) {
        _checklist[item.trim()] = false;
      }
    }
  }

  void _resetWorkflowTimeout() {
    _workflowTimeoutTimer?.cancel();
    _workflowTimeoutTimer = Timer(const Duration(minutes: 15), () {
      if (mounted) {
        SnackbarHelper.showError(context, 'Workflow timeout: Please progress to the next stage.');
        // Optional: Could automatically cancel or alert the passenger here
      }
    });
  }

  Future<void> _logAction(String action) async {
    final driverId = Provider.of<AuthService>(context, listen: false).currentUser?.uid;
    await FirebaseFirestore.instance
        .collection('pasabuy_status_logs')
        .add({
      'requestId': widget.requestId,
      'action': action,
      'status': _currentRequest.status.toString(),
      'actorRole': 'driver',
      'changedByDriverId': driverId,
      'timestamp': Timestamp.now(),
    });
    
    _resetWorkflowTimeout();
  }

  bool _canClickDoneBuying() {
    return true; // No minimum shopping time
  }

  /* Timer removed
  void _startShoppingTimer() {
    _shoppingTimer?.cancel();
    _shoppingTimeElapsed = 0;
    _shoppingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _shoppingTimeElapsed++;
        });
      }
    });
  }
  */

  /* Timer removed
  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  */

  void _initPasaBuyListener() {
    _pasaBuySubscription = Provider.of<FirestoreService>(context, listen: false)
        .getPasaBuyStream(widget.requestId)
        .listen((request) {
      if (request != null && mounted) {
        setState(() {
          _currentRequest = request;
        });
        _handlePasaBuyUpdate(request);

        if (_currentRequest.status == PasaBuyStatus.accepted ||
            _currentRequest.status == PasaBuyStatus.driver_on_way ||
            _currentRequest.status == PasaBuyStatus.delivery_in_progress) {
          _getDriverLatLng().then((loc) {
            if (loc != null && mounted) {
              _updateEtaToPickup(loc.latitude, loc.longitude);
            }
          });
        }
      }
    });
  }

  void _initNavigation() {
    _navSubscription = _navigationService.navigationStateStream.listen((state) {
      if (mounted) {
        _navStateNotifier.value = state;
        _updateMapForNavigation(state);
        _maybeRedrawPolylineFromNavigation();
      }
    });
  }



  Future<void> _updateMapForNavigation(NavigationState state) async {
    if (_mapboxMap == null || !state.isNavigating) return;

    // Update current bearing to match navigation heading
    _currentBearing = state.heading;

    final location = state.currentLocation;

    final now = DateTime.now();
    if (_lastMotionSampleLoc != null && _lastMotionSampleTime != null) {
      final dtMs = now.difference(_lastMotionSampleTime!).inMilliseconds.clamp(1, 1000000);
      final dist = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        _lastMotionSampleLoc!.latitude,
        _lastMotionSampleLoc!.longitude,
      );
      final speed = dist / (dtMs / 1000.0);
      final moving = speed > 0.5;
      if (moving != _isDriverMoving) {
        setState(() {
          _isDriverMoving = moving;
        });
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
    _updateEtaToPickup(location.latitude, location.longitude);

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

  bool _isUpdatingGeometry = false;

  void _onLocationUpdate() {
    if (!mounted) return;
    if (_navigationService.isNavigating) return;
    
    final pos = _locationService.currentPosition;
    if (pos != null) {
      _updateCurrentLocationMarker(app_latlng.LatLng(pos.latitude, pos.longitude), heading: pos.heading);
    }
  }

  void _onMarkerAnimationTick() {
    if (!mounted || _animStartLocation == null || _animTargetLocation == null) return;
    
    final t = _markerMovementController.value;
    final lat = _animStartLocation!.latitude + (_animTargetLocation!.latitude - _animStartLocation!.latitude) * t;
    final lng = _animStartLocation!.longitude + (_animTargetLocation!.longitude - _animStartLocation!.longitude) * t;
    
    final newPos = app_latlng.LatLng(lat, lng);
    
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

  Future<void> _updateMarkerGeometry(app_latlng.LatLng location, {double? heading}) async {
    if (_isUpdatingGeometry) return;
    _isUpdatingGeometry = true;
    
    try {
      if (_driverPoint != null) {
        _driverPoint!.geometry = mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude));
        // Keep icon upright on screen
        _driverPoint!.iconRotate = 0;
        if (_driverAnnotationManager != null) {
          await _driverAnnotationManager!.update(_driverPoint!);
        }
      } else if (_driverPuck != null) {
        _driverPuck!.geometry = mapbox.Point(
          coordinates: mapbox.Position(location.longitude, location.latitude),
        );
        await _circleAnnotationManager!.update(_driverPuck!);
      }

      // Update pulse circle position
      final anchor = _driverPoint != null ? _driverPoint!.geometry : _driverPuck?.geometry;
      if (anchor != null && _pulseCircle != null && _circleAnnotationManager != null) {
        _pulseCircle!.geometry = anchor;
        await _circleAnnotationManager!.update(_pulseCircle!);
      }
    } catch (_) {
      // Ignore
    } finally {
      _isUpdatingGeometry = false;
    }
  }

  Future<void> _updateCurrentLocationMarker(app_latlng.LatLng location, {double? heading}) async {
    if (_circleAnnotationManager == null && _driverAnnotationManager == null) return;
    if (_isCreatingPuck) return; // Prevent concurrent creations

    // Check for upgrade to image marker
    if (_driverPoint == null && _driverPuckImageBytes != null && _driverAnnotationManager != null) {
      _isCreatingPuck = true;
      try {
         _driverPoint = await _driverAnnotationManager!.create(
             mapbox.PointAnnotationOptions(
               geometry: mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude)),
               image: _driverPuckImageBytes!,
               iconSize: (_currentZoom / 15.0).clamp(0.3, 1.3),
               iconAnchor: mapbox.IconAnchor.BOTTOM,
               iconRotate: 0,
             ),
           );
         if (_driverPuck != null && _circleAnnotationManager != null) {
           await _circleAnnotationManager!.delete(_driverPuck!);
           _driverPuck = null;
         }
         _currentDisplayedLocation = location;
         _currentDisplayedHeading = heading ?? 0;
      } catch (e) {
        print('Error upgrading driver puck: $e');
      } finally {
        _isCreatingPuck = false;
      }
      return;
    }

    // 1. Initial Creation if needed
    if (_driverPoint == null && _driverPuck == null) {
       _isCreatingPuck = true;
       try {
         if (_driverPuckImageBytes == null) {
             await _loadDriverPuckImage();
         }
         
         if (_driverPuckImageBytes != null && _driverAnnotationManager != null) {
           _driverPoint = await _driverAnnotationManager!.create(
               mapbox.PointAnnotationOptions(
                 geometry: mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude)),
                 image: _driverPuckImageBytes!,
                 iconSize: (_currentZoom / 15.0).clamp(0.3, 1.3),
                 iconAnchor: mapbox.IconAnchor.BOTTOM,
                 iconRotate: 0,
               ),
             );
         } else {
             // Fallback to circle
             if (_driverPuck == null && _circleAnnotationManager != null) {
                 _driverPuck = await _circleAnnotationManager!.create(
                   mapbox.CircleAnnotationOptions(
                     geometry: mapbox.Point(
                       coordinates: mapbox.Position(location.longitude, location.latitude),
                     ),
                     circleRadius: 10.0,
                     circleColor: AppTheme.primaryGreen.value,
                     circleStrokeWidth: 2.0,
                     circleStrokeColor: Colors.white.value,
                   ),
                 );
             }
         }
         
         _currentDisplayedLocation = location;
         _currentDisplayedHeading = heading ?? 0;
       } catch (e) {
         print('Error creating driver puck: $e');
       } finally {
         _isCreatingPuck = false;
       }
       return;
    }

    // 2. Animation Logic
    if (_currentDisplayedLocation == null) {
      _currentDisplayedLocation = location;
      _updateMarkerGeometry(location, heading: heading);
      return;
    }

    final dist = Geolocator.distanceBetween(
      _currentDisplayedLocation!.latitude, _currentDisplayedLocation!.longitude,
      location.latitude, location.longitude,
    );
    
    if (dist > 500) {
      _currentDisplayedLocation = location;
      _currentDisplayedHeading = heading ?? _currentDisplayedHeading;
      _updateMarkerGeometry(location, heading: heading);
      return;
    }
    
    _animStartLocation = _currentDisplayedLocation;
    _animTargetLocation = location;
    _animStartHeading = _currentDisplayedHeading;
    
    // Stabilize heading to prevent swinging
    double targetH = heading ?? _currentDisplayedHeading;
    double diff = (targetH - _currentDisplayedHeading).abs();
    if (diff > 180) diff = 360 - diff;
    
    if (dist < 2.0) {
      // Too close, ignore heading updates (stationary noise)
      targetH = _currentDisplayedHeading;
    } else if (diff < 5.0) {
      // Ignore small jitter
      targetH = _currentDisplayedHeading;
    }
    
    _animTargetHeading = targetH;
    
    _markerMovementController.duration = const Duration(milliseconds: 1000);
    _markerMovementController.forward(from: 0.0);
  }

  Future<void> _updatePulseMarker() async {
    if (_circleAnnotationManager == null || !mounted || _isUpdatingPulse) return;
    final anchor = _driverPoint != null ? _driverPoint!.geometry : _driverPuck?.geometry;
    if (anchor == null) return;
    
    try {
      _isUpdatingPulse = true;
      // Scale pulse if using image marker
      final bool isImageMarker = _driverPoint != null;
      final double sizeMultiplier = isImageMarker ? 1.8 : 1.0;
      final double baseRadius = _pulseAnimation.value * sizeMultiplier;
      final double scale = (_currentZoom / 15.0).clamp(0.3, 1.3);
      final double displayRadius = baseRadius * scale;
      
      // Calculate opacity and color
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
            ..geometry = anchor
            ..circleColor = colorValue;
          await _circleAnnotationManager!.update(_pulseCircle!);
          _lastPulseRadius = displayRadius;
        }
      } else {
        _pulseCircle = await _circleAnnotationManager!.create(
          mapbox.CircleAnnotationOptions(
            geometry: anchor,
            circleRadius: displayRadius,
            circleColor: colorValue,
            circleOpacity: opacity,
            circleStrokeWidth: 0.0,
          ),
        );
        _lastPulseRadius = displayRadius;
      }
    } catch (_) {
    } finally {
      _isUpdatingPulse = false;
    }
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
      // Silent fallback
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
      // Silent fallback
    }
  }

  Future<void> _handlePasaBuyUpdate(PasaBuyModel request) async {
    if (!mounted) return;

    if (_lastStatus != request.status) {
      final oldStatus = _lastStatus;
      _lastStatus = request.status;

      print('🔄 PasaBuy status updated: $oldStatus -> ${request.status}');

      if (request.status == PasaBuyStatus.arrived_pickup) {
        _hasStartedStoreTrip = false;
      }

      // Handle terminal states
      if (request.status == PasaBuyStatus.completed || request.status == PasaBuyStatus.cancelled) {
        if (_navigationService.isNavigating) {
          await _navigationService.stopNavigation();
        }

        if (mounted) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/driver', (route) => false);
            }
          });
        }
        return;
      }

      // Handle navigation transitions
      if (request.status == PasaBuyStatus.driver_on_way) {
        if (!_navigationService.isNavigating) {
          await _startNavigationToPickup();
        }
      } else if (request.status == PasaBuyStatus.arrived_pickup) {
        if (_navigationService.isNavigating) {
          await _navigationService.stopNavigation();
        }
        _fitTripPreview();
        // _startShoppingTimer();
      } else if (request.status == PasaBuyStatus.delivery_in_progress) {
        // _shoppingTimer?.cancel();
        if (!_navigationService.isNavigating) {
          await _startNavigationToDropoff();
        }
      }

      if (mounted) {
        await _setupMarkers();
      }
    }
  }

  Future<app_latlng.LatLng?> _getDriverLatLng() async {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final cached = locationService.currentPosition;
    if (cached != null) {
      return app_latlng.LatLng(cached.latitude, cached.longitude);
    }

    try {
      final currentPosition = await Geolocator.getCurrentPosition();
      return app_latlng.LatLng(currentPosition.latitude, currentPosition.longitude);
    } catch (e) {
      print('Error getting driver location: $e');
      return null;
    }
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

  void _updateEtaToPickup(double driverLat, double driverLng) {
    final status = _currentRequest.status;
    if (status != PasaBuyStatus.accepted &&
        status != PasaBuyStatus.driver_on_way &&
        status != PasaBuyStatus.delivery_in_progress) {
      if (_etaToPickup != null) {
        setState(() => _etaToPickup = null);
      }
      return;
    }

    double targetLat;
    double targetLng;

    if (status == PasaBuyStatus.delivery_in_progress) {
      targetLat = _currentRequest.dropoffLocation.latitude;
      targetLng = _currentRequest.dropoffLocation.longitude;
    } else {
      targetLat = _currentRequest.pickupLocation.latitude;
      targetLng = _currentRequest.pickupLocation.longitude;
    }

    final distance = Geolocator.distanceBetween(
      driverLat,
      driverLng,
      targetLat,
      targetLng,
    );

    final adjustedDistance = distance * 1.4;
    final etaMinutes = (adjustedDistance / 416.6).round();
    final value = (etaMinutes == 0 && distance > 100) ? 1 : etaMinutes;

    if (_etaToPickup != value) {
      setState(() {
        _etaToPickup = value;
      });
    }
  }

  Future<void> _drawRoute(PasaBuyModel request) async {
    if (_lineAnnotationManager == null) return;

    try {
      List<app_latlng.LatLng> routeGeometry;
      
      if (_navigationService.isNavigating) {
        // Use navigation service route with improved snapping
        routeGeometry = _navigationService.remainingRoutePoints;

        // Get current driver location with better accuracy
        app_latlng.LatLng? driverLoc;
        final navState = _navStateNotifier.value;
        if (navState != null && (navState.currentLocation.latitude != 0 || navState.currentLocation.longitude != 0)) {
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
      } else {
        // Static route display with improved accuracy
        final app_latlng.LatLng origin;
        final app_latlng.LatLng destination;

        if (request.status == PasaBuyStatus.pending || 
            request.status == PasaBuyStatus.accepted ||
            request.status == PasaBuyStatus.arrived_pickup) {
          // Store to Dropoff preview
          origin = app_latlng.LatLng(request.pickupLocation.latitude, request.pickupLocation.longitude);
          destination = app_latlng.LatLng(request.dropoffLocation.latitude, request.dropoffLocation.longitude);
        } else {
          final driverLoc = await _getDriverLatLng();
          if (driverLoc == null) return;
          
          origin = driverLoc;
          // If delivering, go to dropoff. Else (on way to store), go to pickup.
          destination = (request.status == PasaBuyStatus.delivery_in_progress)
              ? app_latlng.LatLng(request.dropoffLocation.latitude, request.dropoffLocation.longitude)
              : app_latlng.LatLng(request.pickupLocation.latitude, request.pickupLocation.longitude);
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
        _routeLine = await _lineAnnotationManager!.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: positions),
            lineColor: color,
            lineWidth: width,
            lineOpacity: 0.9,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      }
    } catch (e) {
      print('❌ Error drawing route: $e');
      _routeLine = null;
    }
  }

  // Helper method to find the nearest point on the route
  app_latlng.LatLng _findNearestRoutePoint(app_latlng.LatLng location, List<app_latlng.LatLng> route) {
    if (route.isEmpty) return location;
    
    double minDistance = double.infinity;
    app_latlng.LatLng nearestPoint = route.first;
    
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
  List<app_latlng.LatLng> _getOptimizedRouteGeometry(List<app_latlng.LatLng> originalRoute) {
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
      final simplifiedRoute = PolylineSimplifier.simplifyAdaptive(
        remainingPoints,
        zoomLevel: _currentZoom,
      );
      
      final navState = _navigationService.currentState;
      final currentLoc = app_latlng.LatLng(navState.currentLocation.latitude, navState.currentLocation.longitude);
      final snapped = _navigationService.snapToRoute(currentLoc);
      
      // Always use snapped point for consistent route drawing
      final routeWithStart = [snapped, ...simplifiedRoute];
      final positions = PolylineDecoder.toMapboxPositions(routeWithStart);

      if (_routeLine != null) {
        _routeLine!.geometry = mapbox.LineString(coordinates: positions);
        await _lineAnnotationManager!.update(_routeLine!);
      } else {
        final color = AppTheme.primaryGreen.value;
        _routeLine = await _lineAnnotationManager!.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: positions),
            lineColor: color,
            lineWidth: 8.0,
            lineOpacity: 0.85,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      }
    } catch (e) {
      // Error updating navigation polyline: $e
    }
  }

  Future<void> _startNavigationToPickup() async {
    try {
      final driverLoc = await _getDriverLatLng();
      if (driverLoc == null) {
         if (mounted) SnackbarHelper.showError(context, 'Could not get current location.');
         return;
      }

      final dest = app_latlng.LatLng(
        _currentRequest.pickupLocation.latitude, 
        _currentRequest.pickupLocation.longitude
      );
      
      await _navigationService.startNavigation(driverLoc, dest, enableVoice: true);
    } catch (e) {
      print('Error starting navigation: $e');
    }
  }

  Future<void> _startNavigationToDropoff() async {
    try {
      final driverLoc = await _getDriverLatLng();
      if (driverLoc == null) {
        if (mounted) SnackbarHelper.showError(context, 'Could not get current location.');
        return;
      }

      final dest = app_latlng.LatLng(
        _currentRequest.dropoffLocation.latitude, 
        _currentRequest.dropoffLocation.longitude
      );
      
      await _navigationService.startNavigation(driverLoc, dest, enableVoice: true);
    } catch (e) {
      print('Error starting navigation: $e');
    }
  }

  Future<void> _setupMarkers() async {
    if (_circleAnnotationManager == null) return;
    
    // Pickup Marker Logic
    // Only show pickup marker if we are NOT in delivery progress (meaning we are going to pickup or at pickup)
    // Once delivery starts, we focus on dropoff, and removing pickup marker prevents "double icon" clutter
    // if the driver is still near the pickup location.
    final bool showPickup = _currentRequest.status != PasaBuyStatus.delivery_in_progress;

    if (showPickup) {
      if (_pickupMarker == null) {
        _pickupMarker = await _circleAnnotationManager!.create(
          mapbox.CircleAnnotationOptions(
            geometry: mapbox.Point(coordinates: mapbox.Position(_currentRequest.pickupLocation.longitude, _currentRequest.pickupLocation.latitude)),
            circleRadius: 8.0,
            circleColor: const Color(0xFF4CAF50).value, // Consistent Green
            circleStrokeWidth: 2.0,
            circleStrokeColor: Colors.white.value,
          ),
        );
      }
    } else {
      if (_pickupMarker != null) {
        await _circleAnnotationManager!.delete(_pickupMarker!);
        _pickupMarker = null;
      }
    }
 
    // Dropoff Marker (Passenger)
    if (_dropoffMarker == null) {
      _dropoffMarker = await _circleAnnotationManager!.create(
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(coordinates: mapbox.Position(_currentRequest.dropoffLocation.longitude, _currentRequest.dropoffLocation.latitude)),
          circleRadius: 8.0,
          circleColor: const Color(0xFFF44336).value, // Consistent Red
          circleStrokeWidth: 2.0,
          circleStrokeColor: Colors.white.value,
        ),
      );
    }
    
    await _drawRoute(_currentRequest);
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

  void _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _lineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _driverAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    
    // Reset marker references as managers are new
    _driverPuck = null;
    _driverPoint = null;
    _pickupMarker = null;
    _dropoffMarker = null;
    _routeLine = null;
    _isCreatingPuck = false;
    
    await _setupMarkers();
    _fitMapBounds();
  }

  void _onCameraChangeListener(mapbox.CameraChangedEventData event) async {
    if (_mapboxMap == null) return;
    final cameraState = await _mapboxMap!.getCameraState();
    _currentZoom = cameraState.zoom;
    _currentBearing = cameraState.bearing;
    _updateMarkerScale();
  }

  Future<void> _updateMarkerScale() async {
    final scale = (_currentZoom / 15.0).clamp(0.3, 1.3);
    
    if (_driverAnnotationManager != null && _driverPoint != null) {
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
        await _driverAnnotationManager!.update(_driverPoint!);
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

  void _fitMapBounds() async {
    if (_mapboxMap == null) return;
    
    final coordinates = <mapbox.Point>[
      mapbox.Point(coordinates: mapbox.Position(_currentRequest.pickupLocation.longitude, _currentRequest.pickupLocation.latitude)),
      mapbox.Point(coordinates: mapbox.Position(_currentRequest.dropoffLocation.longitude, _currentRequest.dropoffLocation.latitude)),
    ];

    final driverLoc = await _getDriverLatLng();
    if (driverLoc != null) {
      coordinates.add(mapbox.Point(coordinates: mapbox.Position(driverLoc.longitude, driverLoc.latitude)));
    }
    
    final camera = await _mapboxMap!.cameraForCoordinates(
      coordinates,
      mapbox.MbxEdgeInsets(top: 100, left: 60, bottom: 250, right: 60),
      null,
      null,
    );
    
    _mapboxMap!.flyTo(
      camera,
      mapbox.MapAnimationOptions(duration: 1000),
    );
  }

  void _fitTripPreview() async {
    if (_mapboxMap == null) return;
    
    final coordinates = <mapbox.Point>[
      mapbox.Point(coordinates: mapbox.Position(_currentRequest.pickupLocation.longitude, _currentRequest.pickupLocation.latitude)),
      mapbox.Point(coordinates: mapbox.Position(_currentRequest.dropoffLocation.longitude, _currentRequest.dropoffLocation.latitude)),
    ];
    
    final camera = await _mapboxMap!.cameraForCoordinates(
      coordinates,
      mapbox.MbxEdgeInsets(top: 120, left: 70, bottom: 300, right: 70),
      null,
      null,
    );
    
    _mapboxMap!.flyTo(
      camera,
      mapbox.MapAnimationOptions(duration: 1200),
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
    final center = loc ?? app_latlng.LatLng(widget.request.pickupLocation.latitude, widget.request.pickupLocation.longitude);
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

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushReplacementNamed('/driver');
        return false;
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              _buildFullScreenMap(),
              
              // Status Chip
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: _buildCompactStatusChip(_currentRequest.status),
              ),

              // Navigation Info
              ValueListenableBuilder<NavigationState?>(
                valueListenable: _navStateNotifier,
                builder: (context, navState, child) {
                  return _buildNavigationInfo(navState);
                },
              ),

              // Map Controls
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).size.height * 0.35 + 20,
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

              // Bottom Sheet
              DraggableScrollableSheet(
                initialChildSize: 0.35,
                minChildSize: 0.25,
                maxChildSize: 0.85,
                builder: (context, scrollController) {
                  _sheetScrollController = scrollController;
                  return _buildCompactBottomSheet(_currentRequest, scrollController);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenMap() {
    return mapbox.MapWidget(
      key: const Key('pasabuy_driver_map'),
      cameraOptions: mapbox.CameraOptions(
        zoom: 14.0,
        pitch: 0.0,
        bearing: 0.0,
      ),
      styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _onStyleLoaded,
      onCameraChangeListener: _onCameraChangeListener,
      onTapListener: _onMapTapped,
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

  Widget _buildCompactStatusChip(PasaBuyStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
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
          Icon(_getStatusIcon(status), color: _getStatusColor(status), size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getStatusText(status),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Text(
                _getStatusSubtext(status),
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationInfo(NavigationState? navState) {
    if (!_navigationService.isNavigating || navState == null) return const SizedBox.shrink();

    return Positioned(
      top: 70,
      left: 0,
      right: 0,
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4285F4),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4285F4).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                navState.currentInstruction != null
                    ? _getManeuverIcon(
                        navState.currentInstruction!.maneuverType,
                        navState.currentInstruction!.maneuverModifier,
                      )
                    : Icons.navigation_rounded,
                color: Colors.white,
                size: 36,
              ),
              if (navState.distanceToNextTurn != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  navState.currentInstruction?.instruction ?? 'Proceed to destination',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.directions_car_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${(navState.remainingDistance / 1000).toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
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
                            color: Colors.white.withOpacity(0.8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${navState.remainingDuration.round()} min',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.9),
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

  Widget _buildCompactBottomSheet(PasaBuyModel request, ScrollController scrollController) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info Chips (no ETA, no PasaBuy label)
                  Row(
                    children: [
                      _buildInfoChip(
                        Icons.account_balance_wallet_outlined,
                        FareService.formatFare(request.budget),
                        Colors.green.shade50,
                        Colors.green.shade700,
                      ),
                      const Spacer(),
                      _buildStatusChip(request.status),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Passenger Info
                  _buildPassengerCard(request),
                  
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),

                  // Items
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
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      request.itemDescription,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  
                  // Locations
                  _buildTripRoute(request),
                  
                  // Action button
                  const SizedBox(height: 24),
                  _buildWorkflowButton(request),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(PasaBuyStatus newStatus, {String? logAction}) async {
    // Capture navigator to close dialog even if widget is unmounted
    final navigator = Navigator.of(context);
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      ),
    );

    try {
      if (logAction != null) {
        await _logAction(logAction);
      }
      
      final authService = Provider.of<AuthService>(context, listen: false);
      final driverId = authService.currentUser?.uid;

      await Provider.of<FirestoreService>(context, listen: false)
          .updatePasaBuyStatus(widget.requestId, newStatus, driverId: driverId);
      
      // Close loading dialog
      if (navigator.canPop()) {
        navigator.pop();
      }

      String message = 'Status updated';
      switch (newStatus) {
        case PasaBuyStatus.driver_on_way: message = 'Heading to pickup location'; break;
        case PasaBuyStatus.arrived_pickup: message = 'Arrived at pickup'; break;
        case PasaBuyStatus.delivery_in_progress: message = 'Items bought! Heading to destination'; break;
        case PasaBuyStatus.completed: message = 'Delivery completed!'; break;
        default: break;
      }

      if (mounted) {
        SnackbarHelper.showSuccess(context, message);
      }
    } catch (e) {
      // Close loading dialog
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to update status: $e');
      }
      print('Error updating PasaBuy status: $e');
    }
  }

  Widget _buildWorkflowButton(PasaBuyModel request) {
    switch (request.status) {
      case PasaBuyStatus.accepted:
        return _buildActionButton(
          label: 'Start Going to Pickup',
          onPressed: () async {
            await _updateStatus(
              PasaBuyStatus.driver_on_way,
              logAction: 'started_to_pickup',
            );
            await _zoomToDriverOnMap();
          },
          color: AppTheme.primaryGreen,
        );

      case PasaBuyStatus.driver_on_way:
        return _buildActionButton(
          label: 'I Have Arrived',
          onPressed: () => _updateStatus(
            PasaBuyStatus.arrived_pickup,
            logAction: 'arrived_at_pickup',
          ),
          color: Colors.orange,
        );

      case PasaBuyStatus.arrived_pickup:
        final canFinish = _canClickDoneBuying();
        if (!_hasStartedStoreTrip) {
          return _buildActionButton(
            label: 'Start Going to Store',
            onPressed: () {
              setState(() {
                _hasStartedStoreTrip = true;
              });
            },
            color: AppTheme.primaryGreen,
          );
        }
        return Column(
          children: [
            _buildChecklistUI(),
            const SizedBox(height: 16),
            _buildActionButton(
              label: 'Done Buying',
              onPressed: canFinish
                  ? () async {
                      await _updateStatus(
                        PasaBuyStatus.delivery_in_progress,
                        logAction: 'finished_buying',
                      );
                      await _zoomToDriverOnMap();
                    }
                  : null,
              color: AppTheme.primaryGreen,
            ),
          ],
        );

      case PasaBuyStatus.delivery_in_progress:
        return _buildActionButton(
          label: 'Mark as Completed',
          onPressed: () async {
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
                          'Complete Delivery?',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Are you sure you want to mark this delivery as completed?',
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

            await _updateStatus(
              PasaBuyStatus.completed,
              logAction: 'completed_delivery',
            );
          },
          color: AppTheme.primaryGreen,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  /* Timer removed
  Widget _buildShoppingTimerUI() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.timer_outlined, color: Colors.green.shade700, size: 20),
          const SizedBox(width: 8),
          Text(
            'Shopping Time: ${_formatDuration(_shoppingTimeElapsed)}',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (_shoppingTimeElapsed < 300)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '(Min 5:00)',
                style: TextStyle(color: Colors.green.shade300, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
  */

  Widget _buildChecklistUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PURCHASE CHECKLIST',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Color(0xFF9E9E9E),
          ),
        ),
        const SizedBox(height: 8),
        ..._checklist.keys.map((item) => CheckboxListTile(
          title: Text(item, style: const TextStyle(fontSize: 14)),
          value: _checklist[item],
          onChanged: (val) {
            setState(() {
              _checklist[item] = val ?? false;
            });
          },
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppTheme.primaryGreen,
        )),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[300],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(PasaBuyStatus status) {
    Color color;
    String text;
    
    switch (status) {
      case PasaBuyStatus.pending:
        color = Colors.orange;
        text = 'PENDING';
        break;
      case PasaBuyStatus.accepted:
        color = Colors.green;
        text = 'ACCEPTED';
        break;
      case PasaBuyStatus.driver_on_way:
        color = Colors.green;
        text = 'ON WAY';
        break;
      case PasaBuyStatus.arrived_pickup:
        color = Colors.purple;
        text = 'AT PICKUP';
        break;
      case PasaBuyStatus.delivery_in_progress:
        color = Colors.indigo;
        text = 'DELIVERING';
        break;
      case PasaBuyStatus.completed:
        color = Colors.green;
        text = 'COMPLETED';
        break;
      case PasaBuyStatus.cancelled:
        color = Colors.red;
        text = 'CANCELLED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 10,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPassengerCard(PasaBuyModel request) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
            child: Text(
              request.passengerName.isNotEmpty ? request.passengerName[0].toUpperCase() : '?',
              style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.passengerName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'Passenger',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => launchUrl(Uri.parse('tel:${request.passengerPhone}')),
            icon: const Icon(Icons.phone_rounded, color: AppTheme.primaryGreen),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen.withOpacity(0.1),
            ),
          ),
          const SizedBox(width: 8),
          if (request.status != PasaBuyStatus.pending)
            ChatButton(
              contextId: widget.requestId,
              collectionPath: 'pasabuy_requests',
              otherUserName: request.passengerName,
              otherUserId: request.passengerId,
              mini: true,
            ),
        ],
      ),
    );
  }

  Widget _buildTripRoute(PasaBuyModel request) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LOCATIONS',
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
                const Icon(Icons.store, size: 16, color: Color(0xFF4CAF50)), // Consistent Green
                Container(width: 2, height: 30, color: Colors.grey[200]),
                const Icon(Icons.location_on, size: 16, color: Color(0xFFF44336)), // Consistent Red
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.pickupAddress,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    request.dropoffAddress,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Logic Helpers ---

  String _getStatusText(PasaBuyStatus status) {
    switch (status) {
      case PasaBuyStatus.pending: return 'New PasaBuy Request';
      case PasaBuyStatus.accepted: return 'PasaBuy Accepted';
      case PasaBuyStatus.driver_on_way: return 'Going to Pickup';
      case PasaBuyStatus.arrived_pickup: return 'Arrived at Pickup';
      case PasaBuyStatus.delivery_in_progress: return 'Delivery In Progress';
      case PasaBuyStatus.completed: return 'Delivery Completed';
      default: return 'PasaBuy Details';
    }
  }

  String _getStatusSubtext(PasaBuyStatus status) {
    switch (status) {
      case PasaBuyStatus.accepted: return 'Head to pickup location';
      case PasaBuyStatus.driver_on_way: return 'Driving to pickup location';
      case PasaBuyStatus.arrived_pickup: return 'Buy the items requested';
      case PasaBuyStatus.delivery_in_progress: return 'Drive safely to passenger';
      case PasaBuyStatus.completed: return 'Thank you for your service';
      default: return 'Trip Information';
    }
  }

  Color _getStatusColor(PasaBuyStatus status) {
    switch (status) {
      case PasaBuyStatus.driver_on_way: return Colors.green;
      case PasaBuyStatus.arrived_pickup: return Colors.orange;
      case PasaBuyStatus.completed: return AppTheme.primaryGreen;
      default: return AppTheme.primaryGreen;
    }
  }

  IconData _getStatusIcon(PasaBuyStatus status) {
    switch (status) {
      case PasaBuyStatus.driver_on_way: return Icons.directions_car_rounded;
      case PasaBuyStatus.arrived_pickup: return Icons.store_rounded;
      case PasaBuyStatus.delivery_in_progress: return Icons.delivery_dining_rounded;
      case PasaBuyStatus.completed: return Icons.verified_rounded;
      default: return Icons.check_circle_rounded;
    }
  }
}
