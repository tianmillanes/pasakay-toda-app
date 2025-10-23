import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../models/driver_model.dart';
import '../../widgets/usability_helpers.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  DriverModel? _driverProfile;
  bool _isCheckingIn = false;

  @override
  void initState() {
    super.initState();
    _loadDriverProfile();
  }

  Future<void> _loadDriverProfile() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    if (authService.currentUser != null) {
      final profile = await firestoreService.getDriverProfile(
        authService.currentUser!.uid,
      );
      if (mounted) {
        setState(() {
          _driverProfile = profile;
        });
      }
    }
  }

  Future<void> _checkInToQueue() async {
    if (_driverProfile == null) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: ProgressIndicatorWithMessage(
            message: 'Checking in...',
            subtitle: 'Verifying your location',
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

      // Check if geofences are loaded first, reload if necessary
      if (!locationService.areGeofencesLoaded()) {
        if (kDebugMode) {
          print('Geofences not loaded, attempting to reload...');
        }
        await locationService.loadGeofences(forceReload: true);

        // Check again after reload attempt
        if (!locationService.areGeofencesLoaded()) {
          throw Exception(
            'Failed to load geofence data from server.\n'
            'Please check your internet connection and try again.',
          );
        }
      }

      // Get current location
      final position = await locationService.getCurrentLocation();
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

      // Ensure geofences are loaded before checking
      print('Ensuring geofences are loaded...');
      await locationService.loadGeofences(forceReload: false);

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

        // Try reloading geofences once
        try {
          await locationService.loadGeofences(forceReload: true);
          isInGeofence = locationService.isInTodaTerminalGeofence(
            position.latitude,
            position.longitude,
          );
          print(
            'Geofence check result after reload: ${isInGeofence ? "INSIDE" : "OUTSIDE"}',
          );
        } catch (reloadError) {
          throw Exception(
            'Geofence system error: ${reloadError.toString()}. Please restart the app.',
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
          'ACCESS DENIED: You must be inside the TODA terminal to check in.\n\n'
          'Please move to the TODA terminal and try again.',
        );
      }

      // Add driver to queue
      await firestoreService.addDriverToQueue(_driverProfile!.id);

      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();

        SnackbarHelper.showSuccess(
          context,
          'Successfully checked in to queue!',
          seconds: 3,
        );
        _loadDriverProfile(); // Refresh driver profile
      }
    } catch (e) {
      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();

        SnackbarHelper.showError(
          context,
          'Check-in failed: ${e.toString()}',
          seconds: 5,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingIn = false;
        });
      }
    }
  }

  Future<void> _checkOutFromQueue() async {
    if (_driverProfile == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Check Out?',
        message:
            'Are you sure you want to check out from the queue? You will need to check in again to receive ride requests.',
        confirmText: 'Check Out',
        cancelText: 'Stay in Queue',
        icon: Icons.logout,
        isDangerous: true,
        onConfirm: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: ProgressIndicatorWithMessage(
            message: 'Checking out...',
            subtitle: 'Please wait',
          ),
        ),
      ),
    );

    try {
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );
      await firestoreService.removeDriverFromQueue(_driverProfile!.id);

      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();

        SnackbarHelper.showSuccess(
          context,
          'Successfully checked out from queue!',
          seconds: 3,
        );
        _loadDriverProfile(); // Refresh driver profile
      }
    } catch (e) {
      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();

        SnackbarHelper.showError(
          context,
          'Check-out failed. Please try again.',
          seconds: 4,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    if (_driverProfile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Enhanced queue status header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      _driverProfile!.isInQueue
                          ? Icons.check_circle
                          : Icons.pending_outlined,
                      size: 48,
                      color: _driverProfile!.isInQueue
                          ? const Color(0xFF34C759)
                          : const Color(0xFF757575),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _driverProfile!.isInQueue ? 'IN QUEUE' : 'NOT IN QUEUE',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D2D2D),
                        letterSpacing: 1.0,
                      ),
                    ),
                    if (_driverProfile!.isInQueue) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D2D2D),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.format_list_numbered,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Position #${_driverProfile!.queuePosition}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Modern check in/out button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isCheckingIn
                    ? null
                    : _driverProfile!.isInQueue
                    ? _checkOutFromQueue
                    : _checkInToQueue,
                icon: _isCheckingIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        _driverProfile!.isInQueue ? Icons.logout : Icons.login,
                        size: 20,
                      ),
                label: Text(
                  _driverProfile!.isInQueue
                      ? 'Check Out from Queue'
                      : 'Check In to Queue',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _driverProfile!.isInQueue
                      ? const Color(0xFF757575)
                      : const Color(0xFF0D7CFF),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: _driverProfile!.isInQueue
                      ? Colors.grey.withOpacity(0.3)
                      : const Color(0xFF0D7CFF).withOpacity(0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),

          // Enhanced queue information
          if (!_driverProfile!.isInQueue)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info,
                        color: Color(0xFF2D2D2D),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'How Queue Works',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.location_on,
                    text: 'You must be at the TODA terminal to check in',
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.format_list_numbered,
                    text:
                        'Rides are assigned in queue order (first come, first served)',
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.notifications_active,
                    text: 'Stay online to receive ride requests',
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.refresh,
                    text:
                        'Return to terminal after completing a ride to rejoin queue',
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Current queue display
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Current Queue',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<List<String>>(
                    stream: firestoreService.getQueueStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final queue = snapshot.data ?? [];

                      if (queue.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.queue, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Queue is empty',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Be the first to check in!',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: queue.length,
                        itemBuilder: (context, index) {
                          final driverId = queue[index];
                          final isCurrentDriver =
                              driverId == _driverProfile!.id;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isCurrentDriver
                                  ? const Color(0xFFF5F5F5)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCurrentDriver
                                    ? const Color(0xFF2D2D2D)
                                    : const Color(0xFFE0E0E0),
                                width: isCurrentDriver ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              leading: SizedBox(
                                width: 40,
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: isCurrentDriver
                                        ? const Color(0xFF0D7CFF)
                                        : const Color(0xFF757575),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              title: FutureBuilder<String>(
                                future: isCurrentDriver
                                    ? Future.value('You')
                                    : _getDriverName(driverId),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return Text(
                                      isCurrentDriver ? 'You' : 'Loading...',
                                      style: TextStyle(
                                        fontWeight: isCurrentDriver
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    );
                                  }

                                  return Text(
                                    snapshot.data ??
                                        (isCurrentDriver
                                            ? 'You'
                                            : 'Driver ${index + 1}'),
                                    style: TextStyle(
                                      fontWeight: isCurrentDriver
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: Color(0xFF2D2D2D),
                                    ),
                                  );
                                },
                              ),
                              subtitle: Text(
                                isCurrentDriver
                                    ? 'Your position in queue'
                                    : 'Waiting for ride',
                                style: const TextStyle(
                                  color: Color(0xFF2D2D2D),
                                ),
                              ),
                              trailing: isCurrentDriver
                                  ? Icon(Icons.person, color: Colors.blue[600])
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
        ],
      ),
    );
  }

  /// Fetch driver name from Firestore
  Future<String> _getDriverName(String driverId) async {
    try {
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );
      final userData = await firestoreService.getUserProfile(driverId);

      if (userData != null) {
        final name = userData['name'] as String?;
        if (name != null && name.isNotEmpty) {
          return name;
        }
      }

      // Fallback to generic name if no name found
      return 'Driver';
    } catch (e) {
      print('Error fetching driver name: $e');
      return 'Driver';
    }
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
        Icon(icon, size: 20, color: const Color(0xFF757575)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF2D2D2D),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
