import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../models/pasabuy_model.dart';
import '../../models/lat_lng.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../services/fare_service.dart';
import '../../services/location_service.dart';
import '../../utils/polyline_decoder.dart';
import '../../utils/app_theme.dart';
import '../../widgets/location_helpers.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/chat_button.dart';
import '../../widgets/common/animated_map_button.dart';
import '../../utils/app_theme.dart';
import '../../config/credentials_config.dart';
import '../../main.dart';

class PasaBuyWaitingScreen extends StatefulWidget {
  final String requestId;
  final PasaBuyModel request;

  const PasaBuyWaitingScreen({
    super.key,
    required this.requestId,
    required this.request,
  });

  @override
  State<PasaBuyWaitingScreen> createState() => _PasaBuyWaitingScreenState();
}

class _PasaBuyWaitingScreenState extends State<PasaBuyWaitingScreen> {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleAnnotationManager;
  mapbox.PolylineAnnotationManager? _lineAnnotationManager;
  mapbox.PointAnnotationManager? _driverAnnotationManager;
  mapbox.PointAnnotation? _driverAnnotation;
  mapbox.CircleAnnotation? _driverCircleAnnotation;
  mapbox.CircleAnnotation? _driverPulseCircle;
  Timer? _pulseAnimationTimer;
  double _pulseAnimationValue = 0.0;
  bool _isPulsing = false;
  bool _isUpdatingDriverMarker = false; // Guard flag to prevent concurrent updates
  Uint8List? _driverMarkerImage;
  Uint8List? _driverPuckMarkerBytes;
  bool _driver3DEnabled = false;
  String _driverModelSourceId = 'driver_model_source';
  String _driverModelLayerId = 'driver_model_layer';
  
  StreamSubscription<PasaBuyModel?>? _pasaBuySubscription;
  StreamSubscription<DocumentSnapshot>? _driverLocationSubscription;
  PasaBuyModel? _currentRequest;
  PasaBuyStatus? _lastStatus;
  String? _currentDriverId;
  LatLng? _driverLatLng;
  double? _driverHeading;
  int? _estimatedETA;
  bool _declineDialogShown = false;
  bool _isZoomedIn = false;
  double _currentZoom = 15.0;
  bool _skipCancelAutoNav = false;
  bool _isFindingAnotherDriver = false; // New flag to track driver search
  String? _driverProfileDriverId;
  Map<String, dynamic>? _driverProfileData;
  ImageProvider? _driverProfileImageProvider;
  bool _isDriverMoving = false;
  DateTime? _driverLastSampleTime;
  LatLng? _driverLastSampleLoc;
  LatLng? _driverVisualLatLng;
  Timer? _driverMovementTimer;
  double _pulseStep = 0.05;
  bool _hasShownCompletionUX = false;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.request;
    _lastStatus = widget.request.status;
    _calculatePickupToDropoffETAForPending();
    _loadDriverMarkerImage();
    _initPasaBuyListener();
    _listenToDeclineNotifications();
  }

  @override
  void dispose() {
    _pasaBuySubscription?.cancel();
    _driverLocationSubscription?.cancel();
    _pulseAnimationTimer?.cancel();
    _circleAnnotationManager = null;
    _lineAnnotationManager = null;
    _driverAnnotationManager = null;
    _mapboxMap = null;
    super.dispose();
  }

  void _listenToDeclineNotifications() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.uid;
    
    if (userId == null) return;
    
    FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('requestId', isEqualTo: widget.requestId)
        .where('type', isEqualTo: 'pasabuy_declined')
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

  Future<void> _updateDriverProfileCache(String driverId) async {
    if (driverId == _driverProfileDriverId && _driverProfileData != null) {
      return;
    }

    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(driverId).get();
      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
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
          _driverProfileDriverId = driverId;
          _driverProfileData = data;
          _driverProfileImageProvider = provider;
          _driverPuckMarkerBytes = markerBytes;
        });
        try {
          await _updateDriverMarker();
        } catch (_) {}
      }
    } catch (e) {
      print('Error loading driver profile: $e');
    }
  }

  void _calculatePickupToDropoffETAForPending() {
    final request = _currentRequest ?? widget.request;
    if (request.status != PasaBuyStatus.pending) return;

    final pickup = request.pickupLocation;
    final dropoff = request.dropoffLocation;

    final distance = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      dropoff.latitude,
      dropoff.longitude,
    );

    final adjustedDistance = distance * 1.4;
    final etaMinutes = (adjustedDistance / 416.6).round();

    setState(() {
      _estimatedETA = (etaMinutes == 0 && distance > 100) ? 1 : etaMinutes;
    });
  }

  void _showDriverDeclinedDialog(BuildContext context) {
    showDialog(
      context: PasakayApp.navigatorKey.currentContext ?? context,
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
                'The assigned driver declined your PasaBuy request. Would you like to find another driver for you?',
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
                            context: PasakayApp.navigatorKey.currentContext ?? context,
                            barrierDismissible: false,
                            builder: (c) => const Center(child: CircularProgressIndicator()),
                          );
                        }
                        
                        try {
                          final firestoreService = Provider.of<FirestoreService>(context, listen: false);
                          await firestoreService.cancelPasaBuyRequest(widget.requestId);
                        } catch (e) {
                          print('Error cancelling PasaBuy: $e');
                        }

                        if (mounted) {
                          // Pop loading dialog
                          Navigator.of(context).pop();
                          Navigator.of(context).pushNamedAndRemoveUntil('/passenger', (route) => false);
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
    ).then((_) {
      // Reset flag when dialog is closed
      _declineDialogShown = false;
    });
  }

  Future<void> _findAnotherDriver(BuildContext context) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const Center(child: CircularProgressIndicator()),
      );

      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final found = await firestoreService.requestAnotherPasaBuyDriver(widget.requestId);

      if (mounted) Navigator.pop(context); // Pop loading dialog

      if (found) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Found another driver! Waiting for acceptance...'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          // Show "No Drivers Available" dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_outline, color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No Drivers Nearby',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'We couldn\'t find any available drivers at the moment. Please wait a few minutes and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  const Text('Returning to dashboard...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
          );

          // Wait 10 seconds then redirect
          await Future.delayed(const Duration(seconds: 10));
          
          if (mounted) {
            // Clear all dialogs/screens and go to dashboard
            Navigator.of(context).pushNamedAndRemoveUntil('/passenger', (route) => false);
          }
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error finding another driver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadDriverMarkerImage() async {
    try {
      // Use Waze-style marker
      final bytes = await LocationHelpers.get3DUserMarkerImage(size: 70); // Reduced size from 100 to 70
      if (!mounted) return;
      setState(() {
        _driverMarkerImage = bytes;
      });
    } catch (e) {
      // Fallback
    }
  }

  void _initPasaBuyListener() {
    _pasaBuySubscription = Provider.of<FirestoreService>(context, listen: false)
        .getPasaBuyStream(widget.requestId)
        .listen((request) {
      if (request != null && mounted) {
        setState(() {
          _currentRequest = request;
        });
        _handleStatusUpdate(request);
        
        // Start tracking driver location if driver is assigned
        if (request.driverId != null) {
          if (_currentDriverId != request.driverId) {
            _currentDriverId = request.driverId;
            _initDriverLocationListener(request.driverId!);
          }
          _updateDriverProfileCache(request.driverId!);
        }
      }
    });
  }

  void _initDriverLocationListener(String driverId) {
    _driverLocationSubscription?.cancel();
    _driverLocationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(driverId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final data = doc.data() as Map<String, dynamic>?;
      final gp = data?['currentLocation'] as GeoPoint?;
      final headingVal = data?['heading'];
      if (gp == null) return;
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
      _calculateETA(gp.latitude, gp.longitude);
      _updateRoutePolyline();
    });
  }

  Future<void> _updateRoutePolyline() async {
    if (_lineAnnotationManager == null) return;

    final request = _currentRequest ?? widget.request;
    final status = request.status;

    double originLat;
    double originLng;
    double destLat;
    double destLng;

    if (status == PasaBuyStatus.driver_on_way && _driverLatLng != null) {
      originLat = _driverLatLng!.latitude;
      originLng = _driverLatLng!.longitude;
      destLat = request.pickupLocation.latitude;
      destLng = request.pickupLocation.longitude;
    } else if (status == PasaBuyStatus.delivery_in_progress && _driverLatLng != null) {
      originLat = _driverLatLng!.latitude;
      originLng = _driverLatLng!.longitude;
      destLat = request.dropoffLocation.latitude;
      destLng = request.dropoffLocation.longitude;
    } else {
      originLat = request.pickupLocation.latitude;
      originLng = request.pickupLocation.longitude;
      destLat = request.dropoffLocation.latitude;
      destLng = request.dropoffLocation.longitude;
    }

    try {
      final routeGeometry = await FareService.getRouteGeometry(
        originLat: originLat,
        originLng: originLng,
        destLat: destLat,
        destLng: destLng,
        includeTraffic: true,
      );

      if (routeGeometry.isEmpty) return;

      final positions = PolylineDecoder.toMapboxPositions(routeGeometry);
      await _lineAnnotationManager!.deleteAll();
      await _lineAnnotationManager!.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: positions),
          lineColor: AppTheme.primaryGreen.value,
          lineWidth: 5.0,
          lineJoin: mapbox.LineJoin.ROUND,
        ),
      );
    } catch (e) {
      print('Error drawing PasaBuy route: $e');
    }
  }

  void _calculateETA(double driverLat, double driverLng) {
    final request = _currentRequest ?? widget.request;
    
    double targetLat;
    double targetLng;
    
    if (request.status == PasaBuyStatus.delivery_in_progress) {
      targetLat = request.dropoffLocation.latitude;
      targetLng = request.dropoffLocation.longitude;
    } else if (request.status == PasaBuyStatus.accepted || 
               request.status == PasaBuyStatus.driver_on_way) {
      targetLat = request.pickupLocation.latitude;
      targetLng = request.pickupLocation.longitude;
    } else {
      setState(() => _estimatedETA = null);
      return;
    }

    final distance = Geolocator.distanceBetween(
      driverLat,
      driverLng,
      targetLat,
      targetLng,
    );

    // Assume 25 km/h
    final adjustedDistance = distance * 1.4;
    final etaMinutes = (adjustedDistance / 416.6).round();

    setState(() {
      _estimatedETA = (etaMinutes == 0 && distance > 100) ? 1 : etaMinutes;
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
      if (_mapboxMap == null) return;

      final request = _currentRequest ?? widget.request;
      final status = request.status;

      final shouldShowPuck = status == PasaBuyStatus.driver_on_way ||
          status == PasaBuyStatus.arrived_pickup ||
          status == PasaBuyStatus.delivery_in_progress;

      if (!shouldShowPuck) {
        if (_driverCircleAnnotation != null && _circleAnnotationManager != null) {
          try {
            await _circleAnnotationManager!.delete(_driverCircleAnnotation!);
          } catch (_) {}
          _driverCircleAnnotation = null;
        }
        if (_driverAnnotation != null && _driverAnnotationManager != null) {
          try {
            await _driverAnnotationManager!.delete(_driverAnnotation!);
          } catch (_) {}
          _driverAnnotation = null;
        }
        if (_driverPulseCircle != null && _circleAnnotationManager != null) {
          try {
            await _circleAnnotationManager!.delete(_driverPulseCircle!);
          } catch (_) {}
          _driverPulseCircle = null;
        }
        _stopPulseAnimation();
        return;
      }
      
      if (_driver3DEnabled) {
        try {
          final point = mapbox.Point(coordinates: mapbox.Position(position.longitude, position.latitude));
          await _mapboxMap!.style.updateGeoJSONSourceFeatures(
            _driverModelSourceId,
            'driver',
            [mapbox.Feature(id: 'driver', geometry: point)],
          );
          if (_driverHeading != null) {
            await _mapboxMap!.style.setStyleLayerProperty(
              _driverModelLayerId,
              "model-rotation",
              [0.0, 0.0, _driverHeading!],
            );
          }
        } catch (_) {}
        return;
      }
      
      final point = mapbox.Point(coordinates: mapbox.Position(position.longitude, position.latitude));
      
      // Determine which marker type to use
      final usePointAnnotation = _driverPuckMarkerBytes != null && _driverAnnotationManager != null;
      
      // Clean up wrong marker type if it exists
      if (usePointAnnotation && _driverAnnotation == null && _driverCircleAnnotation != null && _circleAnnotationManager != null) {
        // If we're switching to point annotation but only have circle, clean up circle
        try {
          await _circleAnnotationManager!.delete(_driverCircleAnnotation!);
        } catch (_) {}
        _driverCircleAnnotation = null;
      } else if (!usePointAnnotation && _driverAnnotation != null && _driverAnnotationManager != null) {
        // If we're switching to circle marker but have point annotation, clean it up
        try {
          await _driverAnnotationManager!.delete(_driverAnnotation!);
        } catch (_) {}
        _driverAnnotation = null;
        
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
        if (_driverAnnotation != null) {
          // Update existing point annotation
          _driverAnnotation!.geometry = point;
          _driverAnnotation!.iconSize = (_currentZoom / 15.0).clamp(0.3, 1.3);
          try {
            await _driverAnnotationManager!.update(_driverAnnotation!);
          } catch (_) {}
        } else {
          // Create new point annotation
          try {
            _driverAnnotation = await _driverAnnotationManager!.create(
              mapbox.PointAnnotationOptions(
                geometry: point,
                image: _driverPuckMarkerBytes!,
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
                circleRadius: 12.0,
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
        if (_driverCircleAnnotation != null) {
          // Update existing circle annotation
          _driverCircleAnnotation!.geometry = point;
          try {
            await _circleAnnotationManager!.update(_driverCircleAnnotation!);
          } catch (_) {}
        } else if (_circleAnnotationManager != null) {
          // Create new circle annotation
          try {
            _driverCircleAnnotation = await _circleAnnotationManager!.create(
              mapbox.CircleAnnotationOptions(
                geometry: point,
                circleRadius: 8.0,
                circleColor: AppTheme.primaryGreen.value,
                circleStrokeWidth: 2.0,
                circleStrokeColor: Colors.white.value,
              ),
            );
          } catch (e) {
            print('Error creating circle annotation: $e');
          }
        }
      }

      if (!_isPulsing) {
        _startPulseAnimation();
      }
    } finally {
      _isUpdatingDriverMarker = false;
    }
  }

  Future<void> _updateDriverMarker() async {
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

      _pulseAnimationValue = (_pulseAnimationValue + _pulseStep) % 1.0;
      final scale = (_currentZoom / 15.0).clamp(0.3, 1.3);
      final pulseFactor = 0.5 + 0.5 * sin(_pulseAnimationValue * 2 * pi);
      final int colorValue = AppTheme.primaryGreen.value;

      if (_driverAnnotation != null && _driverPulseCircle != null) {
        // Wave animation for point annotation
        final pulseRadius = (12.0 + 8.0 * pulseFactor) * scale;
        final opacity = 0.5 * (1.0 - _pulseAnimationValue);
        
        _driverPulseCircle!
          ..circleRadius = pulseRadius
          ..circleOpacity = opacity
          ..circleColor = colorValue;
        
        try {
          await _circleAnnotationManager!.update(_driverPulseCircle!);
        } catch (_) {}
      } else if (_driverCircleAnnotation != null) {
        // Pulse animation for circle marker
        final pulseRadius = (10.0 + 4.0 * pulseFactor) * scale;
        
        _driverCircleAnnotation!
          ..circleRadius = pulseRadius
          ..circleColor = colorValue;
        
        try {
          await _circleAnnotationManager!.update(_driverCircleAnnotation!);
        } catch (_) {}
      }
    });
  }

  void _stopPulseAnimation() {
    _isPulsing = false;
    _pulseAnimationTimer?.cancel();
    _pulseAnimationTimer = null;
    _pulseAnimationValue = 0.0;
    if (_driverCircleAnnotation != null && _circleAnnotationManager != null) {
      final scale = (_currentZoom / 15.0).clamp(0.3, 1.3);
      try {
        _circleAnnotationManager!.update(
          _driverCircleAnnotation!..circleRadius = 8.0 * scale,
        );
      } catch (_) {}
    }
  }

  Future<void> _handleStatusUpdate(PasaBuyModel request) async {
    if (_lastStatus != request.status) {
      final oldStatus = _lastStatus;
      _lastStatus = request.status;
      
      print('🔄 Passenger PasaBuy status updated: $oldStatus -> ${request.status}');
      print('🔄 _skipCancelAutoNav flag: $_skipCancelAutoNav');
      print('🔄 _isFindingAnotherDriver flag: $_isFindingAnotherDriver');
      
      // Skip automatic navigation if we're in the process of finding another driver
      if (_isFindingAnotherDriver) {
        print('🔄 Skipping automatic navigation because we are finding another driver');
        return;
      }

      await _updateRoutePolyline();
      
      if (request.status == PasaBuyStatus.completed) {
        _showPasaBuyCompletedUX();
        // User must click OK button to navigate to dashboard
      } else if (request.status == PasaBuyStatus.cancelled) {
        print('🔄 Status cancelled, checking _skipCancelAutoNav: $_skipCancelAutoNav');
        if (_skipCancelAutoNav) {
          print('🔄 Skipping automatic navigation due to _skipCancelAutoNav flag');
          return;
        }
        if (mounted) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              print('� Navigating to passenger dashboard');
              Navigator.of(context).pushNamedAndRemoveUntil('/passenger', (route) => false);
            }
          });
        }
      }
    }
  }

  void _showPasaBuyCompletedUX() {
    if (!mounted) return;
    if (_hasShownCompletionUX) return;
    _hasShownCompletionUX = true;

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
                const Text(
                  'Delivery Completed',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your items have been delivered. Thank you for using PasaBuy.',
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

  Future<void> _setupMarkers() async {
    if (_circleAnnotationManager == null) return;
    
    await _circleAnnotationManager!.deleteAll();
    await _driverAnnotationManager?.deleteAll();
    
    // Reset driver marker references
    _driverAnnotation = null;
    _driverCircleAnnotation = null;
    _driverPulseCircle = null;
    _isPulsing = false;
    
    // Pickup (Store)
    await _circleAnnotationManager!.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(widget.request.pickupLocation.longitude, widget.request.pickupLocation.latitude)),
        circleRadius: 8.0,
        circleColor: const Color(0xFF4CAF50).value, // Consistent Green
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );
    
    // Dropoff
    await _circleAnnotationManager!.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(widget.request.dropoffLocation.longitude, widget.request.dropoffLocation.latitude)),
        circleRadius: 8.0,
        circleColor: const Color(0xFFF44336).value, // Consistent Red
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    await _updateRoutePolyline();
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _lineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    _driverAnnotationManager = await mapboxMap.annotations.createPointAnnotationManager();
    
    await _setupMarkers();
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
    if (_driverAnnotationManager != null && _driverAnnotation != null) {
      if ((_driverAnnotation!.iconSize! - scale).abs() > 0.05) {
        _driverAnnotation!.iconSize = scale;
        await _driverAnnotationManager!.update(_driverAnnotation!);
      }
    }
    
    // Update driver circle scale
    if (_circleAnnotationManager != null && _driverCircleAnnotation != null) {
       final radius = (12.0 * scale).clamp(4.0, 18.0);
       if ((_driverCircleAnnotation!.circleRadius! - radius).abs() > 0.5) {
         _driverCircleAnnotation!.circleRadius = radius;
         await _circleAnnotationManager!.update(_driverCircleAnnotation!);
       }
    }
  }

  Widget _buildDriverAvatar(String name, String? photoUrl) {
    if (_driverProfileImageProvider != null) {
      return CircleAvatar(
        radius: 18,
        backgroundColor: Colors.white,
        child: ClipOval(
          child: Image(
            image: _driverProfileImageProvider!,
            width: 36,
            height: 36,
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
            radius: 18,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: Image.memory(
                bytes,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
          );
        } catch (_) {}
      } else if (photoUrl.startsWith('http')) {
        return CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white,
          backgroundImage: NetworkImage(photoUrl),
        );
      }
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF4285F4).withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'D',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }

  void _fitMapBounds() async {
    if (_mapboxMap == null) return;
    
    final coordinates = [
      mapbox.Point(coordinates: mapbox.Position(widget.request.pickupLocation.longitude, widget.request.pickupLocation.latitude)),
      mapbox.Point(coordinates: mapbox.Position(widget.request.dropoffLocation.longitude, widget.request.dropoffLocation.latitude)),
    ];

    if (_driverLatLng != null) {
      coordinates.add(mapbox.Point(coordinates: mapbox.Position(_driverLatLng!.longitude, _driverLatLng!.latitude)));
    }
    
    final camera = await _mapboxMap!.cameraForCoordinates(
      coordinates,
      mapbox.MbxEdgeInsets(top: 80, left: 80, bottom: 250, right: 80),
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
        if (mounted) SnackbarHelper.showError(context, 'Location permission denied.');
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
      if (mounted) SnackbarHelper.showError(context, 'Could not get current location.');
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

    final center = _driverLatLng ?? LatLng(widget.request.pickupLocation.latitude, widget.request.pickupLocation.longitude);
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

  String _getStatusText(PasaBuyStatus status) {
    switch (status) {
      case PasaBuyStatus.pending: return 'Waiting driver to accept';
      case PasaBuyStatus.accepted: return 'Driver Assigned';
      case PasaBuyStatus.driver_on_way: return 'Driver Going to Pickup';
      case PasaBuyStatus.arrived_pickup: return 'Driver at Pickup';
      case PasaBuyStatus.delivery_in_progress: return 'Items Bought - Delivering';
      case PasaBuyStatus.completed: return 'Delivery Completed';
      case PasaBuyStatus.cancelled: return 'Cancelled';
    }
  }

  Color _getStatusColor(PasaBuyStatus status) {
    switch (status) {
      case PasaBuyStatus.pending: return const Color(0xFFFF9800);
      case PasaBuyStatus.accepted:
      case PasaBuyStatus.driver_on_way: return const Color(0xFF2196F3);
      case PasaBuyStatus.arrived_pickup: return const Color(0xFF9C27B0);
      case PasaBuyStatus.delivery_in_progress: return const Color(0xFF00BCD4);
      case PasaBuyStatus.completed: return const Color(0xFF4CAF50);
      case PasaBuyStatus.cancelled: return const Color(0xFFFF5252);
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  void _showCancelConfirmation(String requestId) {
    showDialog(
      context: PasakayApp.navigatorKey.currentContext ?? context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: const Text('Are you sure you want to cancel your PasaBuy request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final firestoreService = Provider.of<FirestoreService>(context, listen: false);
                await firestoreService.updatePasaBuyStatus(requestId, PasaBuyStatus.cancelled);
                // Navigation handled by stream listener
              } catch (e) {
                if (mounted) SnackbarHelper.showError(context, 'Error cancelling request: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = _currentRequest ?? widget.request;

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushNamedAndRemoveUntil('/passenger', (route) => false);
        return false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Full screen map
            _buildFullScreenMap(request),
            // Compact status chip
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: _buildCompactStatusChip(request.status),
            ),
            // Draggable bottom sheet
            DraggableScrollableSheet(
              initialChildSize: 0.35,
              minChildSize: 0.20,
              maxChildSize: 0.7,
              snap: true,
              builder: (context, scrollController) {
                return _buildCompactBottomSheet(request, scrollController);
              },
            ),
            
            // Map Controls
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).size.height * 0.35 + 20,
              child: Column(
                children: [
                  // ChatButton moved to driver card
                  AnimatedMapButton(
                    onPressed: _centerOnUserLocation,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1A1A1A),
                    heroTag: 'center_on_driver_pasabuy',
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

  Widget _buildFullScreenMap(PasaBuyModel request) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: mapbox.MapWidget(
        key: const ValueKey("mapbox_pasabuy_active_full"),
        onMapCreated: _onMapCreated,
        onStyleLoadedListener: _onStyleLoaded,
        onCameraChangeListener: _onCameraChangeListener,
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(widget.request.pickupLocation.longitude, widget.request.pickupLocation.latitude)),
          zoom: 15.0,
        ),
      ),
    );
  }

  Widget _buildCompactStatusChip(PasaBuyStatus status) {
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
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info Row
                  Row(
                    children: [
                      if (request.status == PasaBuyStatus.driver_on_way || 
                          request.status == PasaBuyStatus.delivery_in_progress) ...[
                        _buildInfoChip(
                          Icons.access_time_rounded,
                          _estimatedETA != null ? '$_estimatedETA min' : '--',
                          Colors.green.shade50,
                          Colors.green.shade700,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _buildInfoChip(
                        Icons.account_balance_wallet_outlined,
                        FareService.formatFare(request.fare),
                        Colors.green.shade50,
                        Colors.green.shade700,
                      ),
                      const Spacer(),
                      _buildStatusChip(request.status),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Driver Info
                  _buildCompactDriverCard(request),
                  
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),
                  
                  // Items List
                  const Text(
                    'ITEMS TO BUY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(child: Text(request.itemDescription, style: const TextStyle(fontSize: 14))),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Locations
                  _buildTripRoute(request),
                  
                  const SizedBox(height: 24),
                  
                  // Cancel Button
                  if (request.status == PasaBuyStatus.pending)
                    _buildCompactCancelButton(request),
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

  Widget _buildStatusChip(PasaBuyStatus status) {
    final color = _getStatusColor(status);
    final text = status.toString().split('.').last.replaceAll('_', ' ').toUpperCase();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCompactDriverCard(PasaBuyModel request) {
    if (request.status == PasaBuyStatus.pending) {
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

    final driverId = request.driverId;
    if (driverId == null || driverId.isEmpty) return const SizedBox.shrink();

    if (driverId != _driverProfileDriverId || _driverProfileData == null) {
      _updateDriverProfileCache(driverId);
    }

    final data = _driverProfileData;
    if (data == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Loading driver...',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ],
        ),
      );
    }

    final name = data['name'] ?? 'Driver';
    final phone = data['phone'] ?? '';
    final photoUrl = data['photoUrl'] as String?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildDriverAvatar(name, photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (data['plateNumber'] != null)
                  Text(
                    data['plateNumber'],
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          if (phone.isNotEmpty)
            IconButton(
              onPressed: () => _makePhoneCall(phone),
              icon: const Icon(Icons.call, size: 20),
              color: Colors.green,
            ),
          const SizedBox(width: 4),
          ChatButton(
            contextId: widget.requestId,
            collectionPath: 'pasabuy_requests',
            otherUserName: name,
            otherUserId: request.driverId!,
            mini: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCancelButton(PasaBuyModel request) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: () => _showCancelConfirmation(widget.requestId),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.zero,
        ),
        child: const Text(
          'Cancel Request',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
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
                const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF4CAF50)), // Consistent Green
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
}
