import 'dart:async';
import 'dart:convert';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/lat_lng.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/fare_service.dart';
import '../../models/ride_model.dart';
import '../../models/user_model.dart';
import '../../widgets/location_helpers.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/chat_button.dart';
import '../../widgets/common/animated_map_button.dart';
import '../../services/navigation_service.dart';
import '../../utils/polyline_decoder.dart';
import '../../utils/app_theme.dart';

class ActiveRideScreen extends StatefulWidget {
  final RideModel ride;

  const ActiveRideScreen({super.key, required this.ride});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleAnnotationManager;
  mapbox.PolylineAnnotationManager? _lineAnnotationManager;
  mapbox.PointAnnotationManager? _pointAnnotationManager;


  mapbox.CircleAnnotation? _driverAnnotation;
  mapbox.CircleAnnotation? _passengerAnnotation;
  mapbox.CircleAnnotation? _passengerPulseCircle;
  mapbox.PointAnnotation? _driverPointAnnotation;
  Uint8List? _driverMarkerImageBytes;
  Timer? _pulseAnimationTimer;
  Timer? _passengerPulseTimer;
  double _pulseAnimationValue = 0.0;
  double _passengerPulseValue = 0.0;
  bool _isPulsing = false;
  bool _isCreatingPulseCircle = false;
  bool _isPassengerPulsing = false;
  bool _isUpdatingDriverMarker = false; // Guard flag to prevent concurrent updates
  double _currentZoom = 14.0;

  StreamSubscription<DocumentSnapshot>? _driverDocSubscription;
  StreamSubscription<DocumentSnapshot>? _rideSubscription;
  RideModel? _currentRide;
  Map<String, dynamic>? _driverDataCache;
  String? _cachedDriverId;
  ImageProvider? _driverImageProvider;
  bool _hasShownCompletionUX = false;
  LatLng? _driverLatLng;
  LatLng? _driverVisualLatLng;
  Timer? _driverMovementTimer;
  double? _driverHeading;
  bool _isDriverMoving = false;
  DateTime? _driverLastSampleTime;
  LatLng? _driverLastSampleLoc;
  mapbox.CircleAnnotation? _driverPulseCircle;
  double _pulseStep = 0.05;
  DateTime? _lastRouteUpdate;
  RideStatus? _lastRideStatus;
  String? _trackingDriverId;
  List<mapbox.Position> _routePoints = [];
  RideModel? _latestRideForRouting;
  bool _declineDialogShown = false;
  bool _isZoomedIn = false;
  Timer? _pollingTimer;
  Timer? _passengerLocationTimer;
  LatLng? _passengerCurrentLocation;
  StreamSubscription<Position>? _passengerLocationSubscription;
  NavigationService _navigationService = NavigationService();
  StreamSubscription<NavigationState>? _navigationSubscription;
  NavigationState? _currentNavState;
  int? _rideEtaMinutes;

  void _updateRideEtaFromDriver(double driverLat, double driverLng) {
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
    double originLat = driverLat;
    double originLng = driverLng;

    if (status == RideStatus.inProgress) {
      // ETA from passenger puck (current location) to drop off as requested
      // The driver location is the passenger location during the ride
      originLat = driverLat;
      originLng = driverLng;
    }

    final distance = Geolocator.distanceBetween(
      originLat,
      originLng,
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
  
  // Expiration Timer
  Timer? _expirationTimer;
  Duration _timeRemaining = Duration.zero;
  
  // Scroll controller reference for the draggable sheet
  ScrollController? _sheetScrollController;

  @override
  void initState() {
    super.initState();
    print('🚀 Passenger ActiveRideScreen initState with rideId: ${widget.ride.id}');
    _currentRide = widget.ride;
    _lastRideStatus = widget.ride.status;
    _latestRideForRouting = widget.ride;
    
    _listenToDeclineNotifications();

    
    _navigationSubscription = _navigationService.navigationStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _currentNavState = state;
        });
        _updateMapForNavigation(state);
      }
    });

    // Listen to ride updates from Firestore (Direct subscription for reliability)
    _initRideListener();
    
    // Start timer if pending
    if (widget.ride.status == RideStatus.pending) {
      _startExpirationTimer();
    }
    
    // Fallback polling every 5 seconds to ensure status updates are caught
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollRideStatus());
    
    // Start passenger location tracking for real-time navigation
    _startPassengerLocationTracking();
  }

  @override
  void didUpdateWidget(ActiveRideScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent widget passes a new ride object with different status/driver,
    // we must update our local state to reflect that change.
    if (widget.ride.status != oldWidget.ride.status || 
        widget.ride.driverId != oldWidget.ride.driverId ||
        widget.ride.assignedDriverId != oldWidget.ride.assignedDriverId) {
      print('🔄 ActiveRideScreen received update from parent: ${widget.ride.status}');
      setState(() {
        _currentRide = widget.ride;
        _latestRideForRouting = widget.ride;
      });
      _handleRideUpdate(widget.ride);
    }
  }

  void _initRideListener() {
    _rideSubscription = FirebaseFirestore.instance
        .collection('rides')
        .doc(widget.ride.id)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        try {
          final ride = RideModel.fromFirestore(snapshot);
          print('📥 Passenger received ride stream update: ${ride.status} at ${DateTime.now()}');
          
          setState(() {
            _currentRide = ride;
            _latestRideForRouting = ride;
          });
          
          _handleRideUpdate(ride);
          _maybeUpdateRoutePolyline(ride, force: false);
        } catch (e) {
          print('Error parsing ride update: $e');
        }
      }
    }, onError: (e) {
      print('Error in ride stream: $e');
    });
  }

  Future<void> _pollRideStatus() async {
    if (!mounted) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('rides').doc(widget.ride.id).get();
      if (doc.exists && mounted) {
        final ride = RideModel.fromFirestore(doc);
        // Only update if status changed or data changed significantly
        if (ride.status != _currentRide?.status || 
            ride.driverId != _currentRide?.driverId) {
          print('🔄 Polling found update: ${ride.status}');
          setState(() {
            _currentRide = ride;
            _latestRideForRouting = ride;
          });
          _handleRideUpdate(ride);
        }
      }
    } catch (e) {
      print('Polling error: $e');
    }
  }

  @override
  void dispose() {
    _navigationSubscription?.cancel();
    _rideSubscription?.cancel();
    _driverDocSubscription?.cancel();
    _pollingTimer?.cancel();
    _stopPulseAnimation();
    _stopPassengerPulseAnimation();
    _passengerLocationTimer?.cancel();
    _passengerLocationSubscription?.cancel();
    _navigationService.stopNavigation();
    
    // Cleanup Mapbox managers
    _circleAnnotationManager = null;
    _lineAnnotationManager = null;

    _mapboxMap = null;
    _expirationTimer?.cancel();
    
    super.dispose();
  }



  void _listenToDeclineNotifications() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.uid;
    
    if (userId == null) return;
    
    FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('rideId', isEqualTo: widget.ride.id)
        .where('type', isEqualTo: 'ride_declined')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.docs.isNotEmpty && mounted && !_declineDialogShown) {
              _declineDialogShown = true;
              
              // Mark notifications as read
              for (var doc in snapshot.docs) {
                doc.reference.update({'read': true});
              }
              
              _showDriverDeclinedDialog(context);
            }
          },
        );
  }

  void _showDriverDeclinedDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
              ),
              const SizedBox(height: 24),
              const Text(
                'Driver Declined',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The assigned driver declined your ride request. Would you like to find another driver for you?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        
                        // Show loading indicator
                        if (mounted) {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (c) => const Center(child: CircularProgressIndicator()),
                          );
                        }
                        
                        try {
                          final firestoreService = Provider.of<FirestoreService>(context, listen: false);
                          await firestoreService.cancelRideByPassenger(widget.ride.id, widget.ride.passengerId);
                        } catch (e) {
                          print('Error cancelling ride: $e');
                        }

                        if (mounted) {
                          // Pop loading dialog
                          Navigator.of(context).pop();
                          Navigator.of(context).pushReplacementNamed('/passenger');
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _findAnotherDriver(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const StadiumBorder(),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Find Another',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _findAnotherDriver(BuildContext context) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const Center(child: CircularProgressIndicator()),
      );

      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final found = await firestoreService.requestAnotherDriver(widget.ride.id);

      if (mounted) Navigator.pop(context);

      if (found) {
        // Snackbar removed as requested
      } else {
        if (mounted) {
          final passengerDashboardContext = Navigator.of(context).context;
          showDialog(
            context: passengerDashboardContext,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                   Icon(Icons.error_outline_rounded, color: Colors.red),
                   SizedBox(width: 12),
                   Expanded(child: Text('No Drivers Available')),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Sorry, there are no other drivers available right now. Please try again later.'),
                  SizedBox(height: 24),
                  Text('Redirecting to dashboard...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  SizedBox(height: 12),
                  LinearProgressIndicator(),
                ],
              ),
            ),
          );

          // Wait 3-5 seconds then redirect
          await Future.delayed(const Duration(seconds: 4));
          // Best-effort: cancel the ride so dashboard no longer shows ActiveRideScreen
          try {
            final firestoreService = Provider.of<FirestoreService>(context, listen: false);
            await firestoreService.cancelRideByPassenger(widget.ride.id, widget.ride.passengerId);
          } catch (e) {
            debugPrint('Error cancelling ride: $e');
          }
          if (mounted) {
            // Clear all dialogs/screens and go to dashboard
            Navigator.of(context).pushNamedAndRemoveUntil('/passenger', (route) => false);
          }
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      // Snackbar removed as requested
    }
  }

  Future<void> _setupMarkers() async {
    if (_circleAnnotationManager == null) return;
    
    await _circleAnnotationManager!.deleteAll();
    await _pointAnnotationManager?.deleteAll();
    
    // Reset annotation references after deleteAll
    _driverAnnotation = null;
    _passengerAnnotation = null;
    _driverPointAnnotation = null;
    _driverPulseCircle = null;
    _isPulsing = false;
    
    // Only show pickup marker if not in progress
    if (_currentRide?.status != RideStatus.inProgress) {
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
    
    await _circleAnnotationManager!.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(widget.ride.dropoffLocation.longitude, widget.ride.dropoffLocation.latitude)),
        circleRadius: 8.0,
        circleColor: const Color(0xFFF44336).value, // Consistent Red
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    // Re-add dynamic markers if we have their locations
    if (_passengerCurrentLocation != null) {
      await _updatePassengerMarker(_passengerCurrentLocation!);
    }
    await _updateDriverMarker();
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _lineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _pointAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    
    await _setupMarkers();
    await _maybeUpdateRoutePolyline(widget.ride, force: true);
    _fitMapBounds();
  }

  void _onStyleLoaded(mapbox.StyleLoadedEventData data) async {
    if (_mapboxMap == null) return;
    await _mapboxMap!.location.updateSettings(
      mapbox.LocationComponentSettings(
        enabled: false,
        pulsingEnabled: false,
        showAccuracyRing: false,
      ),
    );
  }

  void _onCameraChangeListener(mapbox.CameraChangedEventData event) async {
    if (_mapboxMap == null) return;
    final cameraState = await _mapboxMap!.getCameraState();
    _currentZoom = cameraState.zoom;
    _updateMarkerScale();
  }

  Future<void> _updateMarkerScale() async {
    final scale = (_currentZoom / 15.0).clamp(0.3, 1.3);
    
    // Update driver marker scale
    if (_pointAnnotationManager != null && _driverPointAnnotation != null) {
      if ((_driverPointAnnotation!.iconSize! - scale).abs() > 0.05) {
        _driverPointAnnotation!.iconSize = scale;
        await _pointAnnotationManager!.update(_driverPointAnnotation!);
      }
    }
    
    // Update driver circle scale
    if (_circleAnnotationManager != null && _driverAnnotation != null) {
       final radius = (8.0 * scale).clamp(3.0, 12.0);
       if ((_driverAnnotation!.circleRadius! - radius).abs() > 0.5) {
         _driverAnnotation!.circleRadius = radius;
         await _circleAnnotationManager!.update(_driverAnnotation!);
       }
    }
  }

  String? _resolveDriverId(RideModel ride) {
    final driverId = ride.driverId ?? ride.assignedDriverId;
    if (driverId == null || driverId.isEmpty) return null;
    return driverId;
  }

  bool _shouldShowDriverRoute(RideStatus status) {
    return status == RideStatus.pending ||
        status == RideStatus.accepted ||
        status == RideStatus.driverOnWay ||
        status == RideStatus.driverArrived ||
        status == RideStatus.inProgress;
  }

  bool _shouldRouteToDropoff(RideStatus status) {
    return status == RideStatus.pending ||
        status == RideStatus.driverArrived ||
        status == RideStatus.inProgress ||
        status == RideStatus.completed;
  }

  void _startExpirationTimer() {
    _stopExpirationTimer();
    
    final ride = _currentRide ?? widget.ride;
    final expiresAt = ride.expiresAt;
    
    if (expiresAt == null) return;
    
    // Initial update
    final now = DateTime.now();
    if (now.isBefore(expiresAt)) {
      setState(() {
        _timeRemaining = expiresAt.difference(now);
      });
    } else {
      setState(() {
        _timeRemaining = Duration.zero;
      });
    }

    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final currentRide = _currentRide ?? widget.ride;
      if (currentRide.status != RideStatus.pending) {
        timer.cancel();
        return;
      }
      
      final expiration = currentRide.expiresAt;
      if (expiration == null) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      if (now.isAfter(expiration)) {
        setState(() {
          _timeRemaining = Duration.zero;
        });
        timer.cancel();
      } else {
        setState(() {
          _timeRemaining = expiration.difference(now);
        });
      }
    });
  }

  void _stopExpirationTimer() {
    _expirationTimer?.cancel();
    _expirationTimer = null;
  }

  void _showStatusChangeFeedback(RideStatus status) {
    if (!mounted) return;
    
    String? message;
    bool isSuccess = true;

    switch (status) {
      case RideStatus.accepted:
        message = widget.ride.isPasaBuy ? 'PasaBuy request accepted!' : 'Driver accepted your ride!';
        break;
      case RideStatus.driverOnWay:
        message = widget.ride.isPasaBuy ? 'Driver is heading to the store!' : 'Driver is on the way!';
        break;
      case RideStatus.driverArrived:
        message = widget.ride.isPasaBuy ? 'Driver arrived at the store!' : 'Driver has arrived!';
        break;
      case RideStatus.inProgress:
        message = widget.ride.isPasaBuy ? 'Delivery in progress!' : 'Ride started!';
        break;
      default:
        return; // No feedback for other states
    }

    if (message != null) {
      // Snackbar notifications removed as requested
    }
  }

  void _showRideCompletedUX(RideModel ride) {
    if (!mounted) return;
    if (_hasShownCompletionUX) return;

    _hasShownCompletionUX = true;

    final bool isPasaBuy = ride.isPasaBuy;
    final String title = isPasaBuy ? 'Delivery Completed' : 'Trip Completed';
    final String message = isPasaBuy
        ? 'Your items have been delivered. Thank you for using PasaBuy.'
        : 'Your trip has been completed. Thank you for riding with us.';

    showDialog(
      context: context,
      barrierDismissible: false,
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
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Color(0xFF757575), fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // Navigate to dashboard after OK is clicked
                      if (mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil('/passenger', (route) => false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleRideUpdate(RideModel ride) async {
    if (!mounted) return;
    
    print('🔄 Passenger ride update: ${ride.status} at ${DateTime.now()}');
    print('🔄 Driver ID: ${_resolveDriverId(ride)}');
    
    _latestRideForRouting = ride;
    final driverId = _resolveDriverId(ride);
    if (driverId != _trackingDriverId) {
      await _startTrackingDriver(driverId);
      
      // If driver changed while pending (requeue), restart timer
      if (ride.status == RideStatus.pending) {
        _startExpirationTimer();
      }
    }

    if (_lastRideStatus != ride.status) {
      _lastRideStatus = ride.status;
      
      // Manage timer based on status
      if (ride.status == RideStatus.pending) {
        _startExpirationTimer();
      } else {
        _stopExpirationTimer();
      }
      
      // Show feedback for status changes
      _showStatusChangeFeedback(ride.status);

      // Adjust map bounds for specific status changes
      if (ride.status == RideStatus.driverOnWay || 
          ride.status == RideStatus.driverArrived ||
          ride.status == RideStatus.accepted) {
        _fitMapBounds();
      }

      // If ride is completed, cancelled, or failed, stop navigation and return
      if (ride.status == RideStatus.completed || 
          ride.status == RideStatus.cancelled ||
          ride.status == RideStatus.failed) {
        if (_navigationService.isNavigating) {
          await _navigationService.stopNavigation();
        }
        
        // Show completion UX if ride is completed
        if (mounted) {
          final isCompleted = ride.status == RideStatus.completed;
          final isCancelled = ride.status == RideStatus.cancelled;
          final isFailed = ride.status == RideStatus.failed;

          if (isCompleted) {
            _showRideCompletedUX(ride);
          } else if (isCancelled) {
            // For cancelled rides, navigate back after a short delay
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/passenger', (route) => false);
              }
            });
          } else if (isFailed) {
            // For failed rides, navigate back after a short delay
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/passenger', (route) => false);
              }
            });
          }
        }
        return;
      }

      await _maybeUpdateRoutePolyline(ride, force: true);
      await _setupMarkers(); // Refresh markers when status changes
    }
  }

  Future<void> _startTrackingDriver(String? driverId) async {
    _driverDocSubscription?.cancel();
    _trackingDriverId = driverId;

    if (driverId == null) {
      return;
    }

    _driverDocSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(driverId)
        .snapshots()
        .listen((doc) async {
      if (!mounted) return;

      final data = doc.data() as Map<String, dynamic>?;
      final gp = data?['currentLocation'] as GeoPoint?;
      final headingVal = data?['heading'];
      if (gp == null) {
        return;
      }

      setState(() {
        _driverLatLng = LatLng(gp.latitude, gp.longitude);
        if (headingVal is num) {
          _driverHeading = headingVal.toDouble();
        }
      });
      final now = DateTime.now();
      if (_driverLastSampleLoc != null && _driverLastSampleTime != null) {
        final dtMs = now.difference(_driverLastSampleTime!).inMilliseconds.clamp(1, 1000000);
        final dist = Geolocator.distanceBetween(
          gp.latitude,
          gp.longitude,
          _driverLastSampleLoc!.latitude,
          _driverLastSampleLoc!.longitude,
        );
        final speed = dist / (dtMs / 1000.0);
        final moving = speed > 0.5;
        if (moving != _isDriverMoving) {
          setState(() {
            _isDriverMoving = moving;
            _pulseStep = moving ? 0.08 : 0.03;
          });
        }
      }
      _driverLastSampleLoc = LatLng(gp.latitude, gp.longitude);
      _driverLastSampleTime = now;

      _animateDriverMovement(LatLng(gp.latitude, gp.longitude));
      final ride = _latestRideForRouting ?? widget.ride;
      await _maybeUpdateRoutePolyline(ride, force: false);
      _updateRideEtaFromDriver(gp.latitude, gp.longitude);
    });
  }

  void _animateDriverMovement(LatLng newTarget) {
    if (_driverVisualLatLng == null) {
      _driverVisualLatLng = newTarget;
      _updateDriverMarkerGeometry(newTarget);
      return;
    }

    final start = _driverVisualLatLng!;
    final end = newTarget;
    final startTime = DateTime.now();
    final duration = const Duration(milliseconds: 2000); // 2 seconds for smooth movement

    _driverMovementTimer?.cancel();
    _driverMovementTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final elapsed = now.difference(startTime).inMilliseconds;
      final t = (elapsed / duration.inMilliseconds).clamp(0.0, 1.0);

      if (t >= 1.0) {
        timer.cancel();
        _driverVisualLatLng = end;
        _updateDriverMarkerGeometry(end);
      } else {
        final lat = start.latitude + (end.latitude - start.latitude) * t;
        final lng = start.longitude + (end.longitude - start.longitude) * t;
        _driverVisualLatLng = LatLng(lat, lng);
        _updateDriverMarkerGeometry(_driverVisualLatLng!);
      }
    });
  }

  Future<void> _updateDriverMarkerGeometry(LatLng position) async {
    // Guard against concurrent updates
    if (_isUpdatingDriverMarker) return;
    _isUpdatingDriverMarker = true;
    
    try {
      if (_mapboxMap == null || (_circleAnnotationManager == null && _pointAnnotationManager == null)) return;

      final rideStatus = _currentRide?.status;
      final shouldShowMarker = rideStatus == RideStatus.driverOnWay || 
                               rideStatus == RideStatus.driverArrived;

      if (shouldShowMarker) {
        final point = mapbox.Point(coordinates: mapbox.Position(position.longitude, position.latitude));
        
        // Determine which marker type to use
        final usePointAnnotation = _driverMarkerImageBytes != null && _pointAnnotationManager != null;
        
        // Clean up wrong marker type if it exists
        if (usePointAnnotation && _driverAnnotation != null && _circleAnnotationManager != null) {
          try {
            await _circleAnnotationManager!.delete(_driverAnnotation!);
          } catch (_) {}
          _driverAnnotation = null;
        } else if (!usePointAnnotation && _driverPointAnnotation != null && _pointAnnotationManager != null) {
          try {
            await _pointAnnotationManager!.delete(_driverPointAnnotation!);
          } catch (_) {}
          _driverPointAnnotation = null;
          
          // Also clean up pulse circle if switching to circle marker
          if (_driverPulseCircle != null && _circleAnnotationManager != null) {
            try {
              await _circleAnnotationManager!.delete(_driverPulseCircle!);
            } catch (_) {}
            _driverPulseCircle = null;
          }
        }
        
        // Update or create the appropriate marker type
        if (usePointAnnotation) {
          // Use point annotation with pulse circle
          if (_driverPointAnnotation != null) {
            // Update existing point annotation
            _driverPointAnnotation!.geometry = point;
            _driverPointAnnotation!.iconSize = (_currentZoom / 15.0).clamp(0.3, 1.3);
            try {
              await _pointAnnotationManager!.update(_driverPointAnnotation!);
            } catch (_) {}
          } else {
            // Create new point annotation
            try {
              _driverPointAnnotation = await _pointAnnotationManager!.create(
                mapbox.PointAnnotationOptions(
                  geometry: point,
                  image: _driverMarkerImageBytes!,
                  iconSize: (_currentZoom / 15.0).clamp(0.3, 1.3),
                  iconAnchor: mapbox.IconAnchor.BOTTOM,
                ),
              );
            } catch (e) {
              print('Error creating point annotation: $e');
            }
          }
          
          // Update or create pulse circle
          if (_driverPulseCircle != null && _circleAnnotationManager != null) {
            _driverPulseCircle!.geometry = point;
            try {
              await _circleAnnotationManager!.update(_driverPulseCircle!);
            } catch (_) {}
          } else if (_circleAnnotationManager != null) {
            try {
              _driverPulseCircle = await _circleAnnotationManager!.create(
                mapbox.CircleAnnotationOptions(
                  geometry: point,
                  circleRadius: 14.0,
                  circleColor: AppTheme.primaryGreen.value,
                  circleOpacity: 0.25,
                  circleStrokeWidth: 0.0,
                ),
              );
            } catch (e) {
              print('Error creating pulse circle: $e');
            }
          }
        } else {
          // Use circle marker only
          if (_driverAnnotation != null) {
            // Update existing circle annotation
            _driverAnnotation!.geometry = point;
            try {
              await _circleAnnotationManager!.update(_driverAnnotation!);
            } catch (_) {}
          } else {
            // Create new circle annotation
            try {
              _driverAnnotation = await _circleAnnotationManager!.create(
                mapbox.CircleAnnotationOptions(
                  geometry: point,
                  circleColor: AppTheme.primaryGreen.value,
                  circleRadius: 8.0,
                  circleStrokeWidth: 2.0,
                  circleStrokeColor: Colors.white.value,
                ),
              );
            } catch (e) {
              print('Error creating circle annotation: $e');
            }
          }
        }

        // Start pulsing animation if not already running
        if (!_isPulsing) {
          _startPulseAnimation();
        }

      } else {
        // Hide all driver markers
        if (_driverAnnotation != null && _circleAnnotationManager != null) {
          try {
            await _circleAnnotationManager!.delete(_driverAnnotation!);
          } catch (_) {}
          _driverAnnotation = null;
        }
        if (_driverPointAnnotation != null && _pointAnnotationManager != null) {
          try {
            await _pointAnnotationManager!.delete(_driverPointAnnotation!);
          } catch (_) {}
          _driverPointAnnotation = null;
        }
        if (_driverPulseCircle != null && _circleAnnotationManager != null) {
          try {
            await _circleAnnotationManager!.delete(_driverPulseCircle!);
          } catch (_) {}
          _driverPulseCircle = null;
        }
        
        // Stop pulsing animation
        _stopPulseAnimation();
      }
    } finally {
      _isUpdatingDriverMarker = false;
    }
  }

  Future<void> _updateDriverMarker() async {
    // Legacy method call, redirect to geometry update with current visual pos
    if (_driverVisualLatLng != null) {
      await _updateDriverMarkerGeometry(_driverVisualLatLng!);
    } else if (_driverLatLng != null) {
       _driverVisualLatLng = _driverLatLng;
       await _updateDriverMarkerGeometry(_driverLatLng!);
    }
  }

  void _startPulseAnimation() {
    _isPulsing = true;
    _pulseAnimationTimer?.cancel();
    _pulseAnimationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isPulsing || _circleAnnotationManager == null) {
        timer.cancel();
        return;
      }
      
      _pulseAnimationValue = (_pulseAnimationValue + 0.05) % 1.0;
      
      // Calculate pulsing effect (expanding wave)
      final scale = (_currentZoom / 15.0).clamp(0.5, 1.5);
      final int colorValue = AppTheme.primaryGreen.value;

      if (_driverPointAnnotation != null && _driverPulseCircle != null) {
        // Wave animation for point annotation
        final pulseRadius = (14.0 + 20.0 * _pulseAnimationValue) * scale;
        final opacity = 0.5 * (1.0 - _pulseAnimationValue);
        
        _driverPulseCircle!
          ..circleRadius = pulseRadius
          ..circleOpacity = opacity
          ..circleColor = colorValue;
        
        try {
          await _circleAnnotationManager!.update(_driverPulseCircle!);
        } catch (_) {}
      } else if (_driverAnnotation != null) {
        // Pulse animation for circle marker
        final pulseRadius = (8.0 + 4.0 * _pulseAnimationValue) * scale;
        
        _driverAnnotation!
          ..circleRadius = pulseRadius
          ..circleColor = colorValue;
        
        try {
          await _circleAnnotationManager!.update(_driverAnnotation!);
        } catch (_) {}
      }
    });
  }

  void _stopPulseAnimation() {
    _isPulsing = false;
    _pulseAnimationTimer?.cancel();
    _pulseAnimationTimer = null;
    _pulseAnimationValue = 0.0;
  }

  Future<void> _startPassengerLocationTracking() async {
    // Stop any existing tracking
    _passengerLocationSubscription?.cancel();
    _passengerLocationTimer?.cancel();

    final locationService = Provider.of<LocationService>(context, listen: false);
    
    // Get initial location
    final initialPosition = await locationService.getCurrentLocation();
    if (initialPosition != null && mounted) {
      setState(() {
        _passengerCurrentLocation = LatLng(initialPosition.latitude, initialPosition.longitude);
      });
      _handlePassengerLocationUpdate(_passengerCurrentLocation!);
    }

    // Start location tracking with the service
    locationService.startLocationTracking(
      onLocationUpdate: (position) {
        if (mounted) {
          setState(() {
            _passengerCurrentLocation = LatLng(position.latitude, position.longitude);
          });
          _handlePassengerLocationUpdate(_passengerCurrentLocation!);
        }
      },
    );

    // Fallback timer for periodic updates
    _passengerLocationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final position = await locationService.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          _passengerCurrentLocation = LatLng(position.latitude, position.longitude);
        });
        _handlePassengerLocationUpdate(_passengerCurrentLocation!);
      }
    });
  }

  void _handlePassengerLocationUpdate(LatLng location) {
    final ride = _latestRideForRouting ?? widget.ride;
    
    final displayLocation = location; // Use real GPS position (no snapping)

    // Update passenger marker whenever location changes
    _updatePassengerMarker(displayLocation);
    
    // Only handle route updates during in-progress trips
    if (ride.status == RideStatus.inProgress) {
      _updateMapViewForPassenger(displayLocation);
      // Update ETA based on passenger location
      _updateRideEtaFromDriver(displayLocation.latitude, displayLocation.longitude);
    }
  }

  LatLng _getSnappedLocation(LatLng location) {
    if (_routePoints.isEmpty || _routePoints.length < 2) return location;

    double minDistance = double.infinity;
    LatLng snappedPoint = location;

    // Use Euclidean distance on lat/lng as approximation for snapping logic
    // This is faster and sufficient for visual snapping on small scales
    for (int i = 0; i < _routePoints.length - 1; i++) {
      final p1 = LatLng(_routePoints[i].lat.toDouble(), _routePoints[i].lng.toDouble());
      final p2 = LatLng(_routePoints[i + 1].lat.toDouble(), _routePoints[i + 1].lng.toDouble());
      
      final projected = _projectPointOnSegment(location, p1, p2);
      
      // Calculate squared Euclidean distance for faster comparison
      final dLat = location.latitude - projected.latitude;
      final dLng = location.longitude - projected.longitude;
      final distSq = dLat * dLat + dLng * dLng;

      if (distSq < minDistance) {
        minDistance = distSq;
        snappedPoint = projected;
      }
    }

    // Only snap if within reasonable distance (approx. 0.0003 degrees ~ 30 meters)
    if (minDistance > 0.000009) return location;

    return snappedPoint;
  }

  LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final apLat = p.latitude - a.latitude;
    final apLng = p.longitude - a.longitude;
    final abLat = b.latitude - a.latitude;
    final abLng = b.longitude - a.longitude;

    final ab2 = abLat * abLat + abLng * abLng;
    if (ab2 == 0) return a;

    final t = ((apLat * abLat + apLng * abLng) / ab2).clamp(0.0, 1.0);
    return LatLng(a.latitude + abLat * t, a.longitude + abLng * t);
  }

  Future<void> _updatePassengerMarker(LatLng location) async {
    if (_mapboxMap == null || _circleAnnotationManager == null) return;

    final rideStatus = _currentRide?.status;
    final shouldShowMarker = rideStatus != RideStatus.driverArrived && 
                             rideStatus != RideStatus.pending &&
                             rideStatus != RideStatus.accepted &&
                             rideStatus != RideStatus.driverOnWay;

    if (shouldShowMarker) {
      final point = mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude));
      
      if (_passengerAnnotation != null) {
        _passengerAnnotation!.geometry = point;
        await _circleAnnotationManager!.update(_passengerAnnotation!);
      } else {
        _passengerAnnotation = await _circleAnnotationManager!.create(
          mapbox.CircleAnnotationOptions(
            geometry: point,
            circleColor: Colors.green.value,
            circleRadius: 8.0,
            circleStrokeWidth: 2.0,
            circleStrokeColor: Colors.white.value,
          ),
        );
      }

      // Update pulse circle position if it exists
      if (_passengerPulseCircle != null) {
        _passengerPulseCircle!.geometry = point;
        await _circleAnnotationManager!.update(_passengerPulseCircle!);
      }

      // Start pulsing animation if not already running
      if (!_isPassengerPulsing) {
        _startPassengerPulseAnimation();
      }
    } else {
      // Hide marker if it exists and shouldn't be shown
      if (_passengerAnnotation != null) {
        await _circleAnnotationManager!.delete(_passengerAnnotation as mapbox.CircleAnnotation);
        _passengerAnnotation = null;
      }
      if (_passengerPulseCircle != null) {
        await _circleAnnotationManager!.delete(_passengerPulseCircle as mapbox.CircleAnnotation);
        _passengerPulseCircle = null;
      }
      
      // Stop pulsing animation
      _stopPassengerPulseAnimation();
    }
  }

  void _startPassengerPulseAnimation() {
    _isPassengerPulsing = true;
    _passengerPulseTimer?.cancel();
    _passengerPulseTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (!_isPassengerPulsing || _passengerAnnotation == null || _circleAnnotationManager == null) {
        timer.cancel();
        return;
      }
      
      _passengerPulseValue = (_passengerPulseValue + 0.05) % 1.0;
      
      // Calculate pulsing effect (expanding wave)
      final scale = (_currentZoom / 15.0).clamp(0.5, 1.5);
      final pulseRadius = (8.0 + 20.0 * _passengerPulseValue) * scale;
      final opacity = 0.5 * (1.0 - _passengerPulseValue);
      
      final point = _passengerAnnotation!.geometry;
      
      // Update the passenger annotation with pulsing effect
      if (_passengerPulseCircle == null) {
         // Create separate circle for wave effect
         _passengerPulseCircle = await _circleAnnotationManager!.create(
           mapbox.CircleAnnotationOptions(
             geometry: point,
             circleColor: Colors.green.value,
             circleRadius: pulseRadius,
             circleOpacity: opacity,
             circleStrokeWidth: 0.0,
           ),
         );
      } else {
        _passengerPulseCircle!
           ..geometry = point
           ..circleRadius = pulseRadius
           ..circleOpacity = opacity;
        await _circleAnnotationManager!.update(_passengerPulseCircle!);
      }
    });
  }

  void _stopPassengerPulseAnimation() {
    _isPassengerPulsing = false;
    _passengerPulseTimer?.cancel();
    _passengerPulseTimer = null;
    _passengerPulseValue = 0.0;
    if (_passengerPulseCircle != null && _circleAnnotationManager != null) {
      _circleAnnotationManager!.delete(_passengerPulseCircle!);
      _passengerPulseCircle = null;
    }
  }

  Future<void> _zoomIn() async {
     if (_mapboxMap == null) return;
     final camera = await _mapboxMap!.getCameraState();
     setState(() {
       _currentZoom = (camera.zoom + 1).clamp(2.0, 20.0);
     });
     _mapboxMap!.flyTo(
       mapbox.CameraOptions(zoom: _currentZoom, center: camera.center),
       mapbox.MapAnimationOptions(duration: 300),
     );
   }
 
   Future<void> _zoomOut() async {
     if (_mapboxMap == null) return;
     final camera = await _mapboxMap!.getCameraState();
     setState(() {
       _currentZoom = (camera.zoom - 1).clamp(2.0, 20.0);
     });
     _mapboxMap!.flyTo(
       mapbox.CameraOptions(zoom: _currentZoom, center: camera.center),
       mapbox.MapAnimationOptions(duration: 300),
     );
   }

  mapbox.PolylineAnnotation? _routeLine;

  Future<void> _updateRouteForPassengerMovement(LatLng passengerLocation, RideModel ride) async {
    if (_lineAnnotationManager == null || _routePoints.isEmpty) return;

    try {
      // Find the closest point on the route to the passenger's current location
      final closestIndex = _findClosestPointIndex(_routePoints, passengerLocation);
      
      if (closestIndex != -1) {
        // Trim passed points from our reference list
        // Only trim if we've clearly passed a vertex (index > 0)
        if (closestIndex > 0) {
           _routePoints = _routePoints.sublist(closestIndex);
        }

        // Construct display route starting from user location to ensure continuity
        // This ensures the line is always "intact" with the passenger puck
        final displayRoute = [
          mapbox.Position(passengerLocation.longitude, passengerLocation.latitude),
          ..._routePoints
        ];
          
        if (_routeLine != null) {
          _routeLine!.geometry = mapbox.LineString(coordinates: displayRoute);
          await _lineAnnotationManager!.update(_routeLine!);
        } else {
             _routeLine = await _lineAnnotationManager!.create(
                mapbox.PolylineAnnotationOptions(
                  geometry: mapbox.LineString(coordinates: displayRoute),
                  lineColor: AppTheme.primaryGreen.value,
                  lineWidth: 6.0,
                ),
              );
          }
      }
    } catch (e) {
      print('Error updating route for passenger movement: $e');
    }
  }

  void _updateMapViewForPassenger(LatLng passengerLocation) async {
    if (_mapboxMap == null) return;
    
    final currentCamera = await _mapboxMap!.getCameraState();
    
    // Center map on passenger location during trip
    final camera = mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(passengerLocation.longitude, passengerLocation.latitude),
      ),
      zoom: currentCamera.zoom,
      pitch: currentCamera.pitch,
    );
    
    _mapboxMap!.setCamera(camera);
  }

  void _handleGPSSignalLoss() {
    // GPS signal loss handling - snackbar removed as requested
  }

  Future<void> _maybeUpdateRoutePolyline(
    RideModel ride, {
    required bool force,
  }) async {
    if (_lineAnnotationManager == null) return;
    if (!_shouldShowDriverRoute(ride.status)) {
      await _lineAnnotationManager!.deleteAll();
      _routeLine = null;
      _routePoints = [];
      return;
    }

    final driver = _driverLatLng;
    
    if (ride.status != RideStatus.pending && ride.status != RideStatus.accepted && driver == null) return;

    final now = DateTime.now();
    final last = _lastRouteUpdate;
    if (!force && last != null && now.difference(last).inSeconds < 10 && _routePoints.isNotEmpty) {
      // For driverOnWay, always force update to show only driver->pickup route
      if (ride.status == RideStatus.driverOnWay) {
        _lastRouteUpdate = null; // Force update
        return;
      }
      
      // Only trim route for specific statuses where it makes sense
      if (ride.status == RideStatus.accepted || ride.status == RideStatus.pending) {
        // Don't trim route during accepted/pending - show full pickup to dropoff route
        return;
      }
      
      // Even if we don't fetch a new route, we might need to trim the existing one
      LatLng? tracker;
      if (ride.status == RideStatus.inProgress && _passengerCurrentLocation != null) {
        tracker = _passengerCurrentLocation;
      }

      if (tracker != null) {
        final closestIndex = _findClosestPointIndex(_routePoints, tracker);
        if (closestIndex != -1 && closestIndex < _routePoints.length - 1) {
          final remainingRoute = _routePoints.sublist(closestIndex);
          
          if (_routeLine != null) {
            _routeLine!.geometry = mapbox.LineString(coordinates: remainingRoute);
            await _lineAnnotationManager!.update(_routeLine!);
          } else {
            _routeLine = await _lineAnnotationManager!.create(
              mapbox.PolylineAnnotationOptions(
                geometry: mapbox.LineString(coordinates: remainingRoute),
                lineColor: AppTheme.primaryGreen.value,
                lineWidth: 6.0,
              ),
            );
          }
          _routePoints = remainingRoute;
        }
      }
      return;
    }
    _lastRouteUpdate = now;

    final LatLng origin;
    final LatLng destination;

    if (ride.status == RideStatus.pending || 
        ride.status == RideStatus.accepted || 
        ride.status == RideStatus.driverArrived) {
      origin = LatLng(ride.pickupLocation.latitude, ride.pickupLocation.longitude);
      destination = LatLng(ride.dropoffLocation.latitude, ride.dropoffLocation.longitude);
    } else if (ride.status == RideStatus.driverOnWay && driver != null) {
      // Show route ONLY from driver's REAL-TIME location to pickup (not to dropoff)
      origin = driver;
      destination = LatLng(ride.pickupLocation.latitude, ride.pickupLocation.longitude);
    } else if (ride.status == RideStatus.inProgress && _passengerCurrentLocation != null) {
      // During in-progress trip, route from passenger's current location to destination
      origin = _passengerCurrentLocation!;
      destination = LatLng(ride.dropoffLocation.latitude, ride.dropoffLocation.longitude);
    } else if (driver != null) {
      origin = driver;
      destination = _shouldRouteToDropoff(ride.status)
          ? LatLng(ride.dropoffLocation.latitude, ride.dropoffLocation.longitude)
          : LatLng(ride.pickupLocation.latitude, ride.pickupLocation.longitude);
    } else {
      // Fallback if no driver location is available for routing
      return;
    }

    try {
      final routeGeometry = await FareService.getRouteGeometry(
        originLat: origin.latitude,
        originLng: origin.longitude,
        destLat: destination.latitude,
        destLng: destination.longitude,
        includeTraffic: true,
      );

      if (routeGeometry.isEmpty) {
        _routePoints = [];
        await _lineAnnotationManager!.deleteAll();
        _routeLine = null;
        return;
      }

      _routePoints = PolylineDecoder.toMapboxPositions(routeGeometry);
      
      if (_routeLine != null) {
        _routeLine!.geometry = mapbox.LineString(coordinates: _routePoints);
        await _lineAnnotationManager!.update(_routeLine!);
      } else {
        _routeLine = await _lineAnnotationManager!.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: _routePoints),
            lineColor: AppTheme.primaryGreen.value,
            lineWidth: 6.0,
          ),
        );
      }
    } catch (e) {
      // Ignore routing failures.
    }
  }

  int _findClosestPointIndex(List<mapbox.Position> route, LatLng point) {
    if (route.isEmpty) return -1;

    double minDistance = double.infinity;
    int closestIndex = -1;

    for (int i = 0; i < route.length; i++) {
      final distance = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        route[i].lat.toDouble(),
        route[i].lng.toDouble(),
      );

      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return closestIndex;
  }

  void _fitMapBounds() async {
    if (_mapboxMap == null) return;
    
    final coordinates = [
      mapbox.Point(coordinates: mapbox.Position(widget.ride.pickupLocation.longitude, widget.ride.pickupLocation.latitude)),
      mapbox.Point(coordinates: mapbox.Position(widget.ride.dropoffLocation.longitude, widget.ride.dropoffLocation.latitude)),
    ];

    // Also include driver's current location if available
    if (_driverLatLng != null) {
      coordinates.add(mapbox.Point(coordinates: mapbox.Position(_driverLatLng!.longitude, _driverLatLng!.latitude)));
    }
    
    final camera = await _mapboxMap!.cameraForCoordinates(
      coordinates,
      mapbox.MbxEdgeInsets(top: 80, left: 80, bottom: 80, right: 80),
      null,
      null,
    );
    
    _mapboxMap!.flyTo(
      camera,
      mapbox.MapAnimationOptions(duration: 1000),
    );
  }

  Future<void> _centerOnUserLocation() async {
    if (_mapboxMap == null) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) await LocationHelpers.showLocationDisabledDialog(context);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        // Snackbar removed as requested
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      _mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(position.longitude, position.latitude)),
          zoom: 16.0,
        ),
        mapbox.MapAnimationOptions(duration: 800),
      );
    } catch (e) {
      // Snackbar removed as requested
    }
  }

  Future<void> _toggleMapZoom() async {
    if (_mapboxMap == null) return;

    if (_isZoomedIn) {
      setState(() {
        _isZoomedIn = false;
      });
      _fitMapBounds();
      return;
    }

    final center = _driverLatLng ?? LatLng(widget.ride.pickupLocation.latitude, widget.ride.pickupLocation.longitude);
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

  String _getStatusText(RideStatus status) {
    final isPasaBuy = widget.ride.isPasaBuy;
    switch (status) {
      case RideStatus.pending: return 'Waiting driver to accept';
      case RideStatus.accepted: return isPasaBuy ? 'PasaBuy Accepted' : 'Driver Accepted';
      case RideStatus.driverOnWay: return isPasaBuy ? 'Driver Going to Pickup' : 'Driver On The Way';
      case RideStatus.driverArrived: return isPasaBuy ? 'Driver at Pickup' : 'Driver Arrived';
      case RideStatus.inProgress: return isPasaBuy ? 'Delivery In Progress' : 'Trip In Progress';
      case RideStatus.completed: return isPasaBuy ? 'Delivery Completed' : 'Trip Completed';
      case RideStatus.cancelled: return isPasaBuy ? 'PasaBuy Cancelled' : 'Ride Cancelled';
      case RideStatus.failed: return isPasaBuy ? 'No PasaBuy Drivers' : 'No Drivers Available';
    }
  }

  Color _getStatusColor(RideStatus status) {
    switch (status) {
      case RideStatus.pending: return const Color(0xFFFF9800);
      case RideStatus.accepted:
      case RideStatus.driverOnWay: return const Color(0xFF2196F3);
      case RideStatus.driverArrived: return const Color(0xFF9C27B0);
      case RideStatus.inProgress: return const Color(0xFF00BCD4);
      case RideStatus.completed: return const Color(0xFF4CAF50);
      case RideStatus.cancelled:
      case RideStatus.failed: return const Color(0xFFFF5252);
    }
  }

  IconData _getStatusIcon(RideStatus status) {
    switch (status) {
      case RideStatus.pending: return Icons.hourglass_empty;
      case RideStatus.accepted: return Icons.check_circle;
      case RideStatus.driverOnWay: return Icons.local_shipping;
      case RideStatus.driverArrived: return Icons.location_on;
      case RideStatus.inProgress: return Icons.directions_car;
      case RideStatus.completed: return Icons.check_circle_outline;
      case RideStatus.cancelled:
      case RideStatus.failed: return Icons.cancel;
    }
  }

  String _getStatusSubtext(RideStatus status) {
    final isPasaBuy = widget.ride.isPasaBuy;
    switch (status) {
      case RideStatus.pending: return isPasaBuy ? 'Searching for PasaBuy drivers...' : 'Searching for nearby drivers...';
      case RideStatus.accepted: return isPasaBuy ? 'Your PasaBuy driver has been assigned' : 'Your driver has been assigned and is preparing to pick you up';
      case RideStatus.driverOnWay: return isPasaBuy ? 'Driver is heading to the store' : 'Driver is heading to your location';
      case RideStatus.driverArrived: return isPasaBuy ? 'Driver is buying your items' : 'Driver is waiting at pickup location';
      case RideStatus.inProgress: return isPasaBuy ? 'Driver is delivering your items' : 'Enjoy your ride!';
      case RideStatus.completed: return isPasaBuy ? 'Your items have been delivered' : 'Thank you for riding with us';
      case RideStatus.cancelled: return isPasaBuy ? 'This PasaBuy request has been cancelled' : 'This ride has been cancelled';
      case RideStatus.failed: return 'Please try booking again';
    }
  }

  void _showBackConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Active Ride'),
        content: const Text('An active ride is in progress. Do you want to return to the home screen? You can still monitor your ride there.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Stay')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(this.context).pushReplacementNamed('/passenger');
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D2D2D), foregroundColor: Colors.white),
            child: const Text('Go Home'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = _currentRide ?? widget.ride;

    return WillPopScope(
      onWillPop: () async {
        _showBackConfirmationDialog(context);
        return false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Full screen map
            _buildFullScreenMap(ride),
            // Compact status chip (Google Maps style)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: _buildCompactStatusChip(ride.status),
            ),
            // Google Maps style draggable bottom sheet
            DraggableScrollableSheet(
              initialChildSize: 0.28,
              minChildSize: 0.15,
              maxChildSize: 0.6,
              snap: true,
              builder: (context, scrollController) {
                return _buildCompactBottomSheet(ride, scrollController);
              },
            ),
            
            // Map Controls (Center on Driver and Refresh)
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).size.height * 0.3 + 20,
              child: Column(
                children: [
                  // ChatButton moved to driver card
                  AnimatedMapButton(
                    onPressed: () {
                      _centerOnUserLocation();
                    },
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1A1A1A),
                    heroTag: 'center_on_driver_passenger',
                    child: const Icon(Icons.my_location_rounded),
                  ),

                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String heroTag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: const Color(0xFF1A1A1A),
          size: 24,
        ),
      ),
    );
  }

  Widget _buildCompactStatusChip(RideStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getStatusColor(status),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getStatusText(status),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
      child: mapbox.MapWidget(
        key: const ValueKey("mapbox_active_ride_full"),
        onMapCreated: _onMapCreated,
        onStyleLoadedListener: _onStyleLoaded,
        onCameraChangeListener: _onCameraChangeListener,
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(widget.ride.pickupLocation.longitude, widget.ride.pickupLocation.latitude)),
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primary Info Row (ETA + Fare)
                  Row(
                    children: [
                      _buildInfoChip(
                        Icons.access_time_rounded,
                        () {
                          final isAccepted = ride.status == RideStatus.accepted;
                          if (isAccepted) {
                            final dropoffEta = ride.estimatedDuration > 0 ? ride.estimatedDuration : null;
                            if (dropoffEta != null) {
                              return '$dropoffEta min';
                            }
                            return '--';
                          } else {
                            if (_rideEtaMinutes != null) {
                              return '$_rideEtaMinutes min';
                            }
                            if (ride.estimatedDuration > 0) {
                              return '${ride.estimatedDuration} min';
                            }
                            return '--';
                          }
                        }(),
                        Colors.green.shade50,
                        Colors.green.shade700,
                      ),
                      const SizedBox(width: 8),
                      _buildInfoChip(
                        Icons.payments_rounded,
                        FareService.formatFare(ride.fare),
                        Colors.green.shade50,
                        Colors.green.shade700,
                      ),
                      const Spacer(),
                      _buildStatusChip(ride.status),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Status & Driver Info
                  _buildCompactDriverCard(ride),
                  
                  const SizedBox(height: 20),
                  
                  // Expanded Content (visible when swiped up)
                  const Divider(height: 1),
                  const SizedBox(height: 20),
                  
                  _buildTripRoute(ride),
                  
                  ...(ride.notes != null && ride.notes!.isNotEmpty ? [
                    const SizedBox(height: 24),
                    _buildRideNotes(ride.notes!),
                  ] : []),
                  
                  const SizedBox(height: 24),
                  _buildFareInfo(ride),
                  
                  const SizedBox(height: 24),
                  
                  // Action button
                  ...(ride.status == RideStatus.pending || ride.status == RideStatus.failed ? [
                    _buildCompactCancelButton(ride),
                  ] : []),
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
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: iconColor.withOpacity(0.9),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(RideStatus status) {
    Color color;
    String text;

    switch (status) {
      case RideStatus.pending:
        color = Colors.orange;
        text = 'Searching';
        break;
      case RideStatus.accepted:
        color = Colors.green;
        text = 'Accepted';
        break;
      case RideStatus.driverOnWay:
        color = Colors.indigo;
        text = 'Coming';
        break;
      case RideStatus.driverArrived:
        color = Colors.teal;
        text = 'Arrived';
        break;
      case RideStatus.inProgress:
        color = Colors.green;
        text = 'On Trip';
        break;
      case RideStatus.completed:
        color = Colors.grey;
        text = 'Finished';
        break;
      case RideStatus.cancelled:
        color = Colors.red;
        text = 'Cancelled';
        break;
      default:
        color = Colors.grey;
        text = status.toString().split('.').last;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _updateDriverCache(String driverId) async {
    if (driverId == _cachedDriverId && _driverDataCache != null) {
      return; // Already cached
    }
    
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(driverId).get();
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data();
        ImageProvider? provider;
        final photoUrl = data?['photoUrl'];
        if (photoUrl is String && photoUrl.isNotEmpty) {
          if (photoUrl.startsWith('data:image')) {
            try {
              final bytes = base64Decode(photoUrl.split(',').last);
              provider = MemoryImage(bytes);
            } catch (_) {}
          } else if (photoUrl.startsWith('http')) {
            provider = NetworkImage(photoUrl);
          }
        }
        final String? name = data?['name'];
        final String? initial = (name != null && name.isNotEmpty) ? name.substring(0, 1) : null;
        Uint8List? markerBytes;
        try {
          markerBytes = await LocationHelpers.getProfilePuckMarkerImage(
            photoUrl: photoUrl is String ? photoUrl : null,
            initial: initial,
            size: 150,
            pinColor: const Color(0xFFE53935),
          );
        } catch (_) {}
        setState(() {
          _driverDataCache = data;
          _cachedDriverId = driverId;
          _driverImageProvider = provider;
          _driverMarkerImageBytes = markerBytes;
        });
        try {
          await _updateDriverMarker();
        } catch (_) {}
      }
    } catch (e) {
      print('Error caching driver data: $e');
    }
  }

  Widget _buildCompactDriverCard(RideModel ride) {
    if (ride.status == RideStatus.pending) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange[700]),
            ),
            const SizedBox(width: 12),
            Text(
              'Waiting driver to accept',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange[700]),
            ),
          ],
        ),
      );
    }

    final driverId = ride.driverId ?? ride.assignedDriverId;
    if (driverId == null || driverId.isEmpty) {
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
            Text('Driver unavailable', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          ],
        ),
      );
    }

    // Update cache if driver changed
    if (driverId != _cachedDriverId) {
      _updateDriverCache(driverId);
    }

    // Use cached data if available
    if (_driverDataCache != null) {
      final driverData = _driverDataCache!;
      final driverName = driverData['name'] ?? 'Unknown Driver';
      final plateNumber = driverData['plateNumber'] ?? 'No Plate';
      final photoUrl = driverData['photoUrl'] as String?;
      final vehicleType = driverData['vehicleType'] ?? 'Motorcycle';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildDriverAvatar(photoUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driverName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '$vehicleType • $plateNumber',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ChatButton(
              contextId: ride.id,
              collectionPath: 'rides',
              otherUserName: driverName,
              otherUserId: driverId,
              mini: true,
            ),
          ],
        ),
      );
    }

    // Loading state while fetching
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

  Widget _buildCompactCancelButton(RideModel ride) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: () => _showCancelConfirmation(ride.id),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.zero,
        ),
        child: const Text(
          'Cancel Ride',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    ride.dropoffAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
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
            color: isTotal ? const Color(0xFF4CAF50) : const Color(0xFF1A1A1A),
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

  Future<void> _showCancelConfirmation(String rideId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Ride'),
        content: const Text('Are you sure you want to cancel this ride request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No, Keep It')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252), foregroundColor: Colors.white), child: const Text('Yes, Cancel')),
        ],
      )
    );

    if (confirmed == true && mounted) {
      try {
        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
        final result = await firestoreService.cancelRideByPassenger(rideId, widget.ride.passengerId);
        
        if (mounted) {
          if (result['success'] == true) {
            Navigator.pop(context);
          } else {
            // Snackbar removed as requested
          }
        }
      } catch (e) {
        // Snackbar removed as requested
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    try {
      // Clean the phone number to ensure it's in the correct format
      final cleanPhoneNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      final Uri launchUri = Uri(scheme: 'tel', path: cleanPhoneNumber);
      
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to launch phone app. Please check if you have a phone app installed.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error launching phone app: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateMapForNavigation(NavigationState state) async {
    if (_mapboxMap == null || !state.isNavigating) return;

    // Center map on current location with heading
    final camera = mapbox.CameraOptions(
      center: mapbox.Point(
        coordinates: mapbox.Position(
          state.currentLocation.longitude,
          state.currentLocation.latitude,
        ),
      ),
      zoom: 16.0,
      bearing: state.heading,
      pitch: 0.0,
    );
    
    _mapboxMap!.setCamera(camera);

    // Update current location marker
    await _updateCurrentLocationMarker(state.currentLocation);
  }

  Future<void> _updateCurrentLocationMarker(LatLng location) async {
    // Current location marker removed as requested
  }
}

// Compact Design Methods
extension _ActiveRideScreenCompactDesign on _ActiveRideScreenState {
  Widget _buildCompactRoute(RideModel ride) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  height: 1,
                  color: Colors.grey.shade300,
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ride.pickupAddress.length > 35 
                    ? '${ride.pickupAddress.substring(0, 35)}...'
                    : ride.pickupAddress,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ride.dropoffAddress.length > 35
                    ? '${ride.dropoffAddress.substring(0, 35)}...'
                    : ride.dropoffAddress,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFareDuration(RideModel ride) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.payments_rounded, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Text(
                  FareService.formatFare(ride.fare),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, color: Colors.grey.shade600, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${ride.estimatedDuration} min',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactNotes(String notes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.note_alt_rounded, color: Colors.green.shade700, size: 14),
              const SizedBox(width: 6),
              Text(
                'Notes',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            notes.length > 80 ? '${notes.substring(0, 80)}...' : notes,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDriverInfo(RideModel ride) {
    if (ride.status == RideStatus.pending) return _buildSearchingDriverCard();
    final driverId = ride.driverId ?? ride.assignedDriverId;
    if (driverId == null || driverId.isEmpty) return _buildSearchingDriverCard();

    // Update cache if driver changed
    if (driverId != _cachedDriverId) {
      _updateDriverCache(driverId);
    }

    // Use cached data if available
    if (_driverDataCache != null) {
      final driverData = _driverDataCache!;
      final driverName = driverData['name'] ?? 'Unknown';
      final driverPhone = driverData['phone'] ?? '';
      final driverPlate = driverData['plateNumber'] ?? '';
      final photoUrl = driverData['photoUrl'] as String?;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _buildSmallDriverAvatar(photoUrl, driverName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverName.length > 20 ? '${driverName.substring(0, 20)}...' : driverName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      if (driverPlate.isNotEmpty)
                        Text(
                          driverPlate,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                if (driverPhone.isNotEmpty)
                  IconButton(
                    onPressed: () => _makePhoneCall(driverPhone),
                    icon: Icon(Icons.call_rounded, size: 18, color: Colors.orange),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.orange.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    // Loading state
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
          ),
          SizedBox(width: 12),
          Text('Loading driver...', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildDriverAvatar(String? photoUrl) {
    if (_driverImageProvider != null) {
      return ClipOval(
        child: Image(
          image: _driverImageProvider!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
        ),
      );
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          final bytes = base64Decode(photoUrl.split(',').last);
          return ClipOval(
            child: Image.memory(
              bytes,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {}
      } else if (photoUrl.startsWith('http')) {
        return ClipOval(
          child: Image.network(
            photoUrl,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.person, size: 40, color: Colors.grey[400]),
          ),
        );
      }
    }
    return Icon(Icons.person, size: 40, color: Colors.grey[400]);
  }

  Widget _buildSmallDriverAvatar(String? photoUrl, String driverName) {
    if (_driverImageProvider != null) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.orange.withOpacity(0.1),
        child: ClipOval(
          child: Image(
            image: _driverImageProvider!,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          final bytes = base64Decode(photoUrl.split(',').last);
          return CircleAvatar(
            radius: 16,
            backgroundColor: Colors.orange.withOpacity(0.1),
            child: ClipOval(
              child: Image.memory(
                bytes,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
          );
        } catch (_) {}
      } else if (photoUrl.startsWith('http')) {
        return CircleAvatar(
          radius: 16,
          backgroundImage: NetworkImage(photoUrl),
          backgroundColor: Colors.orange.withOpacity(0.1),
        );
      }
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          driverName.substring(0, 1).toUpperCase(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.orange,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(RideModel ride) {
    if (ride.status == RideStatus.pending || ride.status == RideStatus.failed) {
      return _buildCancelButton(ride);
    }
    return const SizedBox.shrink(); // No action buttons for active rides
  }

  Widget _buildCancelButton(RideModel ride) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _showCancelConfirmation(ride.id),
        icon: const Icon(Icons.cancel_rounded, size: 18),
        label: const Text('Cancel Ride', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 2,
          shadowColor: Colors.red.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildSearchingDriverCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting driver to accept',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade700,
                  ),
                ),
                Text(
                  'Searching for available drivers...',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
