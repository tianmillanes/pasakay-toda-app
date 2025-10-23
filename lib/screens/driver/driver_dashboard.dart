import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/fcm_notification_service.dart';
import '../../models/driver_model.dart';
import '../../models/ride_model.dart';
import '../../widgets/usability_helpers.dart';
import 'driver_registration_screen.dart';
import 'queue_screen.dart';
import 'active_trip_screen.dart';
import 'trip_history_screen.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  int _currentIndex = 0;
  DriverModel? _driverProfile;
  RideModel? _activeRide;
  bool _isMaintenanceMode = false;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadDriverProfile();
    _checkMaintenanceMode();
    _checkActiveRide();
    _listenToDriverNotifications();
  }

  /// Initialize FCM notifications for this driver
  void _initializeNotifications() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser != null) {
      final fcmService = FCMNotificationService();
      // Save FCM token to Firestore for this driver
      await fcmService.updateUserFCMToken(authService.currentUser!.uid);
    }
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

  void _checkMaintenanceMode() {
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
    firestoreService.getMaintenanceModeStream().listen((maintenance) {
      if (mounted) {
        setState(() {
          _isMaintenanceMode = maintenance;
        });
      }
    });
  }

  void _checkActiveRide() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    if (authService.currentUser != null) {
      firestoreService
          .getUserRides(authService.currentUser!.uid, isDriver: true)
          .listen((rides) {
            final activeRides = rides
                .where(
                  (ride) =>
                      ride.status == RideStatus.accepted ||
                      ride.status == RideStatus.driverOnWay ||
                      ride.status == RideStatus.driverArrived ||
                      ride.status == RideStatus.inProgress,
                )
                .toList();

            if (mounted) {
              setState(() {
                _activeRide = activeRides.isNotEmpty ? activeRides.first : null;
              });
            }
          });
    }
  }

  /// Listen to ride assignments directly (notifications removed)
  void _listenToDriverNotifications() {
    final authService = Provider.of<AuthService>(context, listen: false);

    if (authService.currentUser != null) {
      // Listen directly to rides assigned to this driver
      FirebaseFirestore.instance
          .collection('rides')
          .where('assignedDriverId', isEqualTo: authService.currentUser!.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final rideData = change.doc.data() as Map<String, dynamic>;
                print('New ride assigned: ${change.doc.id}');
                print('From: ${rideData['pickupAddress']}');
                print('To: ${rideData['destinationAddress']}');
                // Driver will see this in their dashboard automatically
              }
            }
          });

      // Listen to driver profile changes (approval status, etc.)
      FirebaseFirestore.instance
          .collection('users')
          .doc(authService.currentUser!.uid)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists) {
              final userData = snapshot.data() as Map<String, dynamic>;
              final isApproved = userData['isApproved'] as bool? ?? false;
              final isActive = userData['isActive'] as bool? ?? true;

              if (isApproved) {
                print('Driver account is approved');
              }
              if (!isActive) {
                print('Driver account has been suspended');
              }
            }
          });
    }
  }

  // Notification handling methods removed - using direct Firestore listeners

  // Show logout confirmation dialog
  Future<void> _showLogoutConfirmation() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.logout, color: const Color(0xFF2D2D2D)),
              const SizedBox(width: 8),
              const Text('Confirm Logout'),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out of your account?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D2D2D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true && mounted) {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUserModel;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Show maintenance mode notice
    if (_isMaintenanceMode) {
      return _MaintenanceModeScreen();
    }

    // If driver profile doesn't exist, show registration
    if (_driverProfile == null) {
      return const DriverRegistrationScreen();
    }

    // If driver is not approved, show pending approval screen
    if (!_driverProfile!.isApproved) {
      return _PendingApprovalScreen(driverProfile: _driverProfile!);
    }

    // If there's an active ride, show the active trip screen
    if (_activeRide != null) {
      return ActiveTripScreen(ride: _activeRide!);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
      ),
      drawer: Drawer(
        child: _ProfileDrawer(
          driverProfile: _driverProfile!,
          onLogout: _showLogoutConfirmation,
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HomeTab(driverProfile: _driverProfile!),
          const QueueScreen(),
          const TripHistoryScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Gradient indicator for selected item
            Positioned(
              left: _currentIndex * (MediaQuery.of(context).size.width / 3),
              right:
                  MediaQuery.of(context).size.width -
                  ((_currentIndex + 1) *
                      (MediaQuery.of(context).size.width / 3)),
              bottom: 0,
              child: Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D7CFF), Color(0xFF0052CC)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              selectedItemColor: const Color(0xFF0D7CFF),
              unselectedItemColor: const Color(0xFF2D2D2D),
              selectedFontSize: 12,
              unselectedFontSize: 11,
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.home_outlined),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF0D7CFF), Color(0xFF0052CC)],
                    ).createShader(bounds),
                    child: const Icon(Icons.home, color: Colors.white),
                  ),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.queue_outlined),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF0D7CFF), Color(0xFF0052CC)],
                    ).createShader(bounds),
                    child: const Icon(Icons.queue, color: Colors.white),
                  ),
                  label: 'Queue',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.history_outlined),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF0D7CFF), Color(0xFF0052CC)],
                    ).createShader(bounds),
                    child: const Icon(Icons.history, color: Colors.white),
                  ),
                  label: 'History',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  final DriverModel driverProfile;

  const _HomeTab({required this.driverProfile});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  Widget _buildRideRequestCard(
    BuildContext context,
    Map<String, dynamic> request,
    FirestoreService firestoreService,
  ) {
    final rideId = request['rideId'] as String? ?? '';
    final passengerName = request['passengerName'] as String? ?? 'Passenger';
    final passengerPhone = request['passengerPhone'] as String? ?? '';
    final pickupAddress =
        request['pickupAddress'] as String? ?? 'Pickup location';
    final destinationAddress =
        request['destinationAddress'] as String? ?? 'Destination';
    final fare = (request['fare'] ?? 0.0).toDouble();

    final expiresAt = request['expiresAt'] != null
        ? (request['expiresAt'] as Timestamp).toDate()
        : DateTime.now().add(const Duration(minutes: 3));
    final timeLeft = expiresAt.difference(DateTime.now());

    // Skip invalid requests
    if (rideId.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD0D0D0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Ride Request',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: timeLeft.inSeconds > 60
                        ? const Color(0xFF2D2D2D)
                        : const Color(0xFFFF3B30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${timeLeft.inMinutes}:${(timeLeft.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Passenger Information
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          passengerName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                        if (passengerPhone.isNotEmpty)
                          Text(
                            passengerPhone,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF757575),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Route information
            Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        pickupAddress,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 2,
                        height: 16,
                        color: const Color(0xFFE0E0E0),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFF5252),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        destinationAddress,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Fare display
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.payments_outlined,
                  color: Color(0xFF000000),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '₱${fare.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000000),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _declineRide(context, rideId, firestoreService),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text(
                      'Decline',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5252),
                      side: const BorderSide(color: Color(0xFFFF5252)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        _acceptRide(context, rideId, firestoreService),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text(
                      'Accept Ride',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptRide(
    BuildContext context,
    String rideId,
    FirestoreService firestoreService,
  ) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final driverId = authService.currentUser?.uid;
      if (driverId == null) {
        if (mounted) {
          SnackbarHelper.showError(context, 'Error: Not logged in');
        }
        return;
      }

      // First check if ride is still available
      final rideStream = firestoreService.getRideStream(rideId);
      final rideSnapshot = await rideStream.first;

      if (rideSnapshot?.status != RideStatus.pending) {
        if (mounted) {
          SnackbarHelper.showWarning(
            context,
            'Ride is no longer available (status: ${rideSnapshot?.status.toString().split('.').last ?? 'unknown'})',
          );
        }
        return;
      }

      await firestoreService.acceptRideRequest(rideId, driverId);
      if (mounted) {
        SnackbarHelper.showSuccess(context, 'Ride accepted successfully!');
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        SnackbarHelper.showError(
          context,
          'Failed to accept ride: $errorMessage',
          seconds: 4,
        );
      }
    }
  }

  Future<void> _declineRide(
    BuildContext context,
    String rideId,
    FirestoreService firestoreService,
  ) async {
    try {
      print('Decline button pressed for ride: $rideId');

      final authService = Provider.of<AuthService>(context, listen: false);
      final driverId = authService.currentUser?.uid;

      print('Current driver ID: $driverId');

      if (driverId == null) {
        print('Error: Driver not logged in');
        if (mounted) {
          SnackbarHelper.showError(context, 'Error: Not logged in');
        }
        return;
      }

      print('Calling declineRideRequest...');
      await firestoreService.declineRideRequest(rideId, driverId);
      print('declineRideRequest completed successfully');

      if (mounted) {
        SnackbarHelper.showSuccess(context, 'Ride declined successfully');
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString().replaceAll('Exception: ', '');
        SnackbarHelper.showError(
          context,
          'Failed to decline ride: $errorMessage',
          seconds: 4,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);
    final driverId = authService.currentUser?.uid;

    // PERFORMANCE: Stream only current driver's data instead of all drivers
    return StreamBuilder<DriverModel?>(
      stream: firestoreService.getDriverStream(widget.driverProfile.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final driverData = snapshot.data ?? widget.driverProfile;
        final isInQueue = driverData.isInQueue;

        return Container(
          color: Colors.white,
          child: CustomScrollView(
            slivers: [
              // Status Header
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          isInQueue
                              ? Icons.check_circle_outline
                              : Icons.pending_outlined,
                          size: 28,
                          color: isInQueue
                              ? const Color(0xFF34C759)
                              : const Color(0xFFFF9500),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isInQueue ? 'ONLINE' : 'OFFLINE',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D2D2D),
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isInQueue
                                    ? 'Ready to receive rides'
                                    : 'Join queue to go online',
                                style: const TextStyle(
                                  color: Color(0xFF757575),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isInQueue && driverData.queuePosition > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${driverData.queuePosition}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const Text(
                                  'in queue',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Ride requests section (only when online)
              if (isInQueue && driverId != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.notifications_active,
                              color: Color(0xFF007AFF),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Ride Requests',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D2D2D),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              if (isInQueue && driverId != null)
                SliverToBoxAdapter(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: firestoreService.getDriverNotifications(driverId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 8),
                              Text('Loading ride requests...'),
                            ],
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error,
                                color: Colors.red,
                                size: 48,
                              ),
                              const SizedBox(height: 8),
                              Text('Error: ${snapshot.error}'),
                            ],
                          ),
                        );
                      }

                      final rideRequests = snapshot.data ?? [];

                      if (rideRequests.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.notifications_none,
                                  size: 40,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No ride requests',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D2D2D),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Waiting for passengers...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF2D2D2D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: rideRequests.map((request) {
                            return _buildRideRequestCard(
                              context,
                              request,
                              firestoreService,
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileDrawer extends StatelessWidget {
  final DriverModel driverProfile;
  final VoidCallback onLogout;

  const _ProfileDrawer({required this.driverProfile, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUserModel;

    return Column(
      children: [
        // Drawer Header
        UserAccountsDrawerHeader(
          decoration: const BoxDecoration(color: Color(0xFF2D2D2D)),
          currentAccountPicture: CircleAvatar(
            backgroundColor: Colors.white,
            child: Text(
              driverProfile.name.isNotEmpty
                  ? driverProfile.name.substring(0, 1).toUpperCase()
                  : 'D',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D2D),
              ),
            ),
          ),
          accountName: Text(
            driverProfile.name.isNotEmpty ? driverProfile.name : 'Driver',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          accountEmail: Text(
            user?.email ?? '',
            style: const TextStyle(fontSize: 14),
          ),
        ),

        // Profile Section
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Vehicle Details',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.confirmation_number,
                      color: Color(0xFF757575),
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverProfile.plateNumber,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Plate Number',
                            style: TextStyle(color: Colors.black, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.credit_card,
                      color: Color(0xFF757575),
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverProfile.licenseNumber,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'License Number',
                            style: TextStyle(color: Colors.black, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Logout Button
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout, color: Color(0xFFFF3B30)),
          title: const Text(
            'Sign Out',
            style: TextStyle(
              color: Color(0xFFFF3B30),
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () {
            Navigator.pop(context);
            onLogout();
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _MaintenanceModeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.construction,
                size: 80,
                color: Color(0xFFFF3B30),
              ),
              const SizedBox(height: 24),
              const Text(
                'Maintenance Mode',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D2D2D),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'yourapp is currently under maintenance. Please check back later.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Color(0xFF2D2D2D)),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacementNamed('/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3B30),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Okay',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingApprovalScreen extends StatelessWidget {
  final DriverModel driverProfile;

  const _PendingApprovalScreen({required this.driverProfile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pending, size: 80, color: Colors.blue[600]),
              const SizedBox(height: 24),
              const Text(
                'Pending Approval',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your driver application is being reviewed by our admin team. You will be notified once approved.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  final state = context
                      .findAncestorStateOfType<_DriverDashboardState>();
                  state?._showLogoutConfirmation();
                },
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
