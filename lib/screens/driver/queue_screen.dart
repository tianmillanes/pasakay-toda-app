import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/error_handling_service.dart';

import '../../models/driver_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';

class QueueScreen extends StatefulWidget {
  final DriverModel? initialDriverProfile;
  const QueueScreen({super.key, this.initialDriverProfile});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  DriverModel? _driverProfile;
  bool _isCheckingIn = false;
  bool _isCheckingOut = false;
  StreamSubscription<DriverModel?>? _driverProfileSubscription;
  StreamSubscription<Position>? _geofenceMonitoringSubscription;
  bool _isMonitoringGeofence = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDriverProfile != null) {
      _driverProfile = widget.initialDriverProfile;
    }
    // _loadDriverProfile(); // Redundant with listener
    _listenToDriverProfile();
  }

  void _listenToDriverProfile() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    final uid = authService.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    _driverProfileSubscription?.cancel();
    _driverProfileSubscription = firestoreService.getDriverStream(uid).listen((
      profile,
    ) {
      if (!mounted) return;
      setState(() {
        _driverProfile = profile;
      });
    });
  }

  final ValueNotifier<String> _loadingMessage = ValueNotifier('Please wait...');

  @override
  void dispose() {
    _driverProfileSubscription?.cancel();
    _loadingMessage.dispose();
    _stopGeofenceMonitoring();
    super.dispose();
  }

  Future<void> _loadDriverProfile() async {
    print('🔄 [QueueScreen._loadDriverProfile] Loading driver profile...');
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    if (authService.currentUser != null) {
      final profile = await firestoreService.getDriverProfile(
        authService.currentUser!.uid,
      );
      print(
        '   Profile loaded: isInQueue=${profile?.isInQueue}, queuePosition=${profile?.queuePosition}',
      );
      
      if (mounted) {
        print('   Setting state with new profile');
        setState(() {
          _driverProfile = profile;
        });
        print('[QueueScreen._loadDriverProfile] Profile updated successfully');
      } else {
        print(
          '[QueueScreen._loadDriverProfile] Widget not mounted, skipping setState',
        );
      }
    }
  }

  Future<void> _checkInToQueue() async {
    if (_driverProfile == null) return;

    if (_driverProfile!.isPaid == false) {
      SnackbarHelper.showError(
        context,
        'Your account is unpaid. Please settle your payment to check in to the queue.',
        seconds: 5,
      );
      return;
    }

    // Show loading dialog
    _loadingMessage.value = 'Preparing check-in...';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: _loadingMessage,
                builder: (context, message, child) {
                  return Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    setState(() {
      _isCheckingIn = true;
    });

    try {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );

      // Get driver's barangayId for geofence loading
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Ensure user model is loaded to get barangayId
      if (authService.currentUserModel == null) {
        _loadingMessage.value = 'Loading profile...';
        try {
          await authService.refreshUserData();
        } catch (e) {
          throw Exception(
            'Unable to load your profile. Please check your internet connection and try again.',
          );
        }
      }
      
      final driverBarangayId = authService.currentUserModel?.barangayId;
      
      if (driverBarangayId == null) {
        throw Exception(
          'Unable to load driver profile or barangay information.\n'
          'Please check your internet connection and try again.',
        );
      }
      
      _loadingMessage.value = 'Checking location...';

      // Parallelize location fetching and geofence loading with timeout
      try {
        final futures = await Future.wait([
          locationService.getCurrentLocation(),
          // Always attempt to load the correct barangay geofence
          // LocationService will handle caching if the correct ID is already loaded
          locationService.loadGeofences(
            barangayId: driverBarangayId,
            forceReload: false,
          ),
        ]).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw Exception(
            'Connection timeout. Please check your internet connection and try again.',
          ),
        );

        final position = futures[0] as Position?;

        if (position == null) {
          throw Exception(
            'Unable to get current location. Please enable location services.',
          );
        }

        // Log GPS accuracy for debugging but don't block check-in
        if (position.accuracy > 100.0) {
          print(
            'INFO: GPS accuracy is low (${position.accuracy.toStringAsFixed(1)}m) but proceeding with geofence check',
          );
        } else if (position.accuracy > 50.0) {
          print(
            'INFO: GPS accuracy is moderate (${position.accuracy.toStringAsFixed(1)}m)',
          );
        } else {
          print(
            'INFO: GPS accuracy is good (${position.accuracy.toStringAsFixed(1)}m)',
          );
        }

        _loadingMessage.value = 'Verifying location...';

        // Check if driver is within TODA terminal geofence
        bool isInGeofence = false;
        try {
          print('Checking geofence for driver location:');
          print(
            '   Coordinates: (${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)})',
          );
          print('   GPS Accuracy: ${position.accuracy.toStringAsFixed(1)}m');

          isInGeofence = locationService.isInTodaTerminalGeofence(
            position.latitude,
            position.longitude,
          );

          print('Geofence check result: ${isInGeofence ? "INSIDE" : "OUTSIDE"}');
        } catch (e) {
          print('Geofence validation error: ${e.toString()}');
          print('Attempting to reload geofences...');

          _loadingMessage.value = 'Retrying verification...';
          // Try reloading geofences once
          try {
            await locationService.loadGeofences(forceReload: true).timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw Exception(
                'Geofence verification timeout. Please check your internet connection.',
              ),
            );
            isInGeofence = locationService.isInTodaTerminalGeofence(
              position.latitude,
              position.longitude,
            );
            print(
              'Geofence check result after reload: ${isInGeofence ? "INSIDE" : "OUTSIDE"}',
            );
          } catch (reloadError) {
            // Check if it's a network/connection error
            final errorStr = reloadError.toString().toLowerCase();
            if (errorStr.contains('timeout') || 
                errorStr.contains('connection') || 
                errorStr.contains('network') ||
                errorStr.contains('socket') ||
                errorStr.contains('failed host lookup')) {
              throw Exception(
                'Unable to verify your location. Please check your internet connection and try again.',
              );
            }
            throw Exception(
              'Unable to verify your location. Please check your internet connection and try again.',
            );
          }
        }

        if (!isInGeofence) {
          final terminalGeofence = locationService.getTerminalGeofence();

          // Calculate distance to terminal center for user feedback
          double centerLat = 0, centerLng = 0;
          if (terminalGeofence != null && terminalGeofence.isNotEmpty) {
            centerLat =
                terminalGeofence.map((p) => p[0]).reduce((a, b) => a + b) /
                terminalGeofence.length;
            centerLng =
                terminalGeofence.map((p) => p[1]).reduce((a, b) => a + b) /
                terminalGeofence.length;
          }

          double distanceToTerminal = locationService.calculateDistance(
            position.latitude,
            position.longitude,
            centerLat,
            centerLng,
          );

          throw Exception(
            'You must be inside the TODA terminal to check in.\n'
            'Please move to the TODA terminal and try again.',
          );
        }

        // Check availability before adding to queue
        _loadingMessage.value = 'Checking availability...';
        print('Checking driver availability before queueing...');
        try {
          final isAvailable = await firestoreService.checkDriverAvailability(_driverProfile!.id).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Connection timeout while checking availability. Please try again.',
            ),
          );
          if (!isAvailable) {
            throw Exception(
              'You have an active ride or PasaBuy request.\n'
              'Please complete or cancel it before checking in.',
            );
          }
        } catch (e) {
          if (e.toString().contains('timeout') || e.toString().contains('Connection')) {
            throw Exception(
              'Unable to check your availability. Please check your internet connection and try again.',
            );
          }
          rethrow;
        }

        // Add driver to queue
        _loadingMessage.value = 'Joining queue...';
        try {
          await firestoreService.addDriverToQueue(_driverProfile!.id).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception(
              'Connection timeout while joining queue. Please try again.',
            ),
          );
        } catch (e) {
          if (e.toString().contains('timeout') || e.toString().contains('Connection')) {
            throw Exception(
              'Unable to join queue. Please check your internet connection and try again.',
            );
          }
          rethrow;
        }

        if (mounted) {
          // Close loading dialog
          Navigator.of(context).pop();

          SnackbarHelper.showSuccess(
            context,
            'Successfully checked in to queue!',
            seconds: 3,
          );
          
          // Start geofence monitoring to auto-checkout if driver leaves terminal
          _startGeofenceMonitoring();
          
          _loadDriverProfile(); // Refresh driver profile
        }
      } on TimeoutException catch (e) {
        throw Exception(
          'Connection timeout. Please check your internet connection and try again.',
        );
      }
    } on LocationServiceException catch (e) {
      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();
        _showLocationDisabledDialog(e.toString());
      }
    } on LocationPermissionException catch (e) {
      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();
        _showPermissionDeniedDialog(e.toString());
      }
    } catch (e) {
      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();

        // Use ErrorHandlingService for consistent error messages
        String errorMessage = ErrorHandlingService.getUserFriendlyMessage(e);
        
        SnackbarHelper.showError(context, errorMessage, seconds: 5);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingIn = false;
        });
      }
    }
  }

  /// Start monitoring geofence - auto-checkout if driver leaves terminal
  void _startGeofenceMonitoring() {
    if (_isMonitoringGeofence || _driverProfile == null) {
      print('⚠️ Geofence monitoring already active or no driver profile');
      return;
    }

    _isMonitoringGeofence = true;
    print('📍 Starting geofence monitoring for driver ${_driverProfile!.id}');

    final locationService = Provider.of<LocationService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    // Monitor location every 10 seconds
    _geofenceMonitoringSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // Get updates for any movement
        timeLimit: Duration(seconds: 30),
      ),
    ).listen(
      (Position position) async {
        try {
          // Check if driver is still in terminal geofence
          final isInGeofence = locationService.isInTodaTerminalGeofence(
            position.latitude,
            position.longitude,
          );

          if (!isInGeofence) {
            print('🚨 Driver left terminal geofence! Auto-checking out...');
            print('   Location: (${position.latitude}, ${position.longitude})');

            // Stop monitoring first
            _stopGeofenceMonitoring();

            // Auto-checkout from queue
            if (mounted && _driverProfile != null) {
              try {
                await firestoreService.removeDriverFromQueue(_driverProfile!.id);
                
                // Update driver status
                await firestoreService.updateDriverOnlineStatus(_driverProfile!.id, false);

                if (mounted) {
                  // Refresh driver profile
                  await _loadDriverProfile();

                  // Show notification
                  SnackbarHelper.showWarning(
                    context,
                    'You have been automatically checked out from the queue because you left the terminal area.',
                    seconds: 5,
                  );
                }
              } catch (e) {
                print('❌ Error auto-checking out: $e');
              }
            }
          }
        } catch (e) {
          print('❌ Error in geofence monitoring: $e');
        }
      },
      onError: (error) {
        print('❌ Geofence monitoring error: $error');
        _stopGeofenceMonitoring();
      },
    );
  }

  /// Stop monitoring geofence
  void _stopGeofenceMonitoring() {
    if (!_isMonitoringGeofence) return;

    _geofenceMonitoringSubscription?.cancel();
    _geofenceMonitoringSubscription = null;
    _isMonitoringGeofence = false;
    print('📍 Geofence monitoring stopped');
  }

  Future<void> _checkOutFromQueue() async {
    print('[QueueScreen._checkOutFromQueue] Starting checkout process...');
    if (_driverProfile == null) {
      print('No driver profile, aborting');
      return;
    }

    print('   Showing confirmation dialog...');
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (dialogContext) => ConfirmationDialog(
        title: 'Check Out?',
        message:
            'Are you sure you want to check out from the queue? You will need to check in again to receive ride requests.',
        confirmText: 'Check Out',
        cancelText: 'Stay in Queue',
        icon: Icons.logout,
        isDangerous: true,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );

    print('   User confirmed: $confirmed');
    if (confirmed != true) {
      print('   User cancelled checkout or dialog dismissed');
      return;
    }

    // Check if still mounted before proceeding
    if (!mounted) {
      print('Widget not mounted after confirmation, aborting');
      return;
    }

    // Small delay to ensure dialog is fully dismissed
    await Future.delayed(const Duration(milliseconds: 100));

    // Set flag to prevent unwanted navigation during checkout
    print('   Setting _isCheckingOut flag...');
    setState(() {
      _isCheckingOut = true;
    });

    // Store navigator reference BEFORE async operations
    final navigator = Navigator.of(context);
    print('Navigator stored');

    // Show loading dialog
    _loadingMessage.value = 'Preparing check-out...';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: _loadingMessage,
                builder: (context, message, child) {
                  return Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    try {
      print('   Calling removeDriverFromQueue...');
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );
      
      _loadingMessage.value = 'Removing from queue...';
      await firestoreService.removeDriverFromQueue(_driverProfile!.id);

      print('   Refreshing driver profile...');
      // Refresh driver profile
      _loadingMessage.value = 'Updating profile...'; 
      await _loadDriverProfile();

      print('   Checkout complete, closing loading dialog...');
      // Close loading dialog using stored navigator
      if (mounted) {
        navigator.pop();
      }

      // Small delay before showing snackbar to avoid rendering issues
      await Future.delayed(const Duration(milliseconds: 50));

      if (!mounted) {
        print('Widget disposed after checkout, aborting UI updates');
        return;
      }

      SnackbarHelper.showSuccess(
        context,
        'Successfully checked out from queue!',
        seconds: 3,
      );

      // Stop geofence monitoring
      _stopGeofenceMonitoring();

      // Reset flag
      if (mounted) {
        print('   Resetting _isCheckingOut flag');
        setState(() {
          _isCheckingOut = false;
        });
      }

      print('[QueueScreen._checkOutFromQueue] Checkout completed successfully');
    } catch (e) {
      print('[QueueScreen._checkOutFromQueue] Error during checkout: $e');

      // Close loading dialog using stored navigator
      if (mounted) {
        navigator.pop();
      }

      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Check-out failed. Please try again.',
          seconds: 4,
        );

        // Reset flag even on error
        setState(() {
          _isCheckingOut = false;
        });
      }
    }
  }

  Widget _buildSkeleton(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header Skeleton
            Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, left: 28, right: 28, bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.circle,
                    size: 40,
                    color: Colors.grey.shade200,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 24,
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),

          // Action Button Skeleton
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),

          // Info Box Skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.grey.shade100, width: 2),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    if (_driverProfile == null) {
      return _buildSkeleton(context);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Premium Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 60, left: 28, right: 28, bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (_driverProfile!.isInQueue ? AppTheme.primaryGreenLight : Colors.grey.shade50),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _driverProfile!.isInQueue ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 40,
                    color: _driverProfile!.isInQueue ? AppTheme.primaryGreen : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _driverProfile!.isInQueue ? 'You are in queue' : 'You are not in queue',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: -0.5,
                  ),
                ),
                if (_driverProfile!.isInQueue) ...[
                  const SizedBox(height: 12),
                  StreamBuilder<int>(
                    stream: Provider.of<FirestoreService>(context, listen: false)
                        .getDriverQueuePositionStream(_driverProfile!.id),
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? _driverProfile!.queuePosition;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryGreen.withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Text(
                          'QUEUE POSITION #$position',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          // Action Button
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCheckingIn || _isCheckingOut
                    ? null
                    : _driverProfile!.isInQueue
                        ? _checkOutFromQueue
                        : _checkInToQueue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _driverProfile!.isInQueue ? Colors.red : AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: (_driverProfile!.isInQueue ? Colors.red : AppTheme.primaryGreen).withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isCheckingIn || _isCheckingOut)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      )
                    else ...[
                      Icon(_driverProfile!.isInQueue ? Icons.power_settings_new_rounded : Icons.check_circle_rounded),
                      const SizedBox(width: 12),
                      Text(
                        _driverProfile!.isInQueue ? 'Check out in queue' : 'Check in queue',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Information when offline
          if (!_driverProfile!.isInQueue)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.grey.shade100, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.amber.shade50, shape: BoxShape.circle),
                          child: const Icon(Icons.tips_and_updates_rounded, color: Colors.amber, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Queue Guidelines',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A1A1A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _InfoRow(icon: Icons.location_on_rounded, text: 'Must be within the TODA terminal geofence'),
                    const SizedBox(height: 12),
                    _InfoRow(icon: Icons.access_time_filled_rounded, text: 'First-in, first-out assignment system'),
                    const SizedBox(height: 12),
                    _InfoRow(icon: Icons.notifications_active_rounded, text: 'Automatically receive nearby requests'),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 32),

          // Queue List Section - Only show when driver is in queue
          if (_driverProfile!.isInQueue)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50.withOpacity(0.5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      child: Text(
                        'Queue Status',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -0.5),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<String>>(
                      stream: _driverProfile != null
                          ? firestoreService.getQueueStreamForBarangay(_driverProfile!.barangayId)
                          : Stream.value([]),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
                        }

                        final queue = snapshot.data ?? [];

                        if (queue.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_alt_rounded, size: 80, color: Colors.grey.shade200),
                                const SizedBox(height: 16),
                                Text(
                                  'Queue is Empty',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.grey.shade400),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Be the first to go in queue!',
                                  style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 40),
                          itemCount: queue.length,
                          itemBuilder: (context, index) {
                            final driverId = queue[index];
                            final isCurrentDriver = driverId == _driverProfile!.id;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isCurrentDriver ? AppTheme.primaryGreen.withOpacity(0.05) : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isCurrentDriver ? AppTheme.primaryGreen.withOpacity(0.3) : Colors.grey.shade100,
                                  width: 1.5,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isCurrentDriver ? AppTheme.primaryGreen : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: isCurrentDriver ? Colors.white : Colors.grey.shade600,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ),
                                title: FutureBuilder<String>(
                                  future: isCurrentDriver ? Future.value('You') : _getDriverName(driverId),
                                  builder: (context, snapshot) {
                                    return Text(
                                      snapshot.data ?? 'Loading...',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: isCurrentDriver ? AppTheme.primaryGreen : const Color(0xFF1A1A1A),
                                        fontSize: 16,
                                      ),
                                    );
                                  },
                                ),
                                subtitle: Text(
                                  isCurrentDriver ? 'Your current slot' : 'Waiting in line',
                                  style: TextStyle(
                                    color: isCurrentDriver ? AppTheme.primaryGreen.withOpacity(0.7) : Colors.grey.shade500,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: isCurrentDriver
                                    ? Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryGreen.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.person_rounded, color: AppTheme.primaryGreen, size: 20),
                                      )
                                    : null,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fetch driver name from Firestore
  Future<String> _getDriverName(String driverId) async {
    try {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final userData = await firestoreService.getUserProfile(driverId);

      if (userData != null) {
        final name = userData['name'] as String?;
        if (name != null && name.isNotEmpty) {
          return name;
        }
      }
      return 'Driver';
    } catch (e) {
      return 'Driver';
    }
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
              // Try checking in again after settings are opened
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _checkInToQueue();
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
              // Try checking in again after settings are opened
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _checkInToQueue();
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
