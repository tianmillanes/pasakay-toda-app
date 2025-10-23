import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/ride_model.dart';
import '../../utils/app_theme.dart';
import '../../widgets/passenger/stats_card.dart';
import '../../widgets/passenger/recent_destinations_card.dart';
import '../../widgets/common/animated_page_transition.dart';
import '../../widgets/usability_helpers.dart';
import 'book_ride_screen.dart';
import 'ride_history_screen.dart';
import 'active_ride_screen.dart';

class PassengerDashboard extends StatefulWidget {
  const PassengerDashboard({super.key});

  @override
  State<PassengerDashboard> createState() => _PassengerDashboardState();
}

class _PassengerDashboardState extends State<PassengerDashboard> {
  int _currentIndex = 0;
  RideModel? _activeRide;
  List<Map<String, dynamic>> _onlineDrivers = [];
  bool _isCheckingDrivers = false;
  bool _isMaintenanceMode = false;

  // Stream subscriptions for proper disposal
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _checkActiveRide();
    _checkOnlineDrivers();
    _listenToNotifications();
    _checkMaintenanceMode();
  }

  @override
  void dispose() {
    // Cancel all stream subscriptions to prevent memory leaks
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  /// Notification services removed - using Firestore listeners
  void _initializeNotifications() async {
    // No notification initialization needed
    _listenToPassengerNotifications();
  }

  void _checkMaintenanceMode() {
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
    final subscription = firestoreService.getMaintenanceModeStream().listen((
      maintenance,
    ) {
      if (mounted) {
        setState(() {
          _isMaintenanceMode = maintenance;
        });
      }
    });
    _subscriptions.add(subscription);
  }

  void _checkActiveRide() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    final currentUser = authService.currentUser;
    if (currentUser == null) return; // Null safety check

    final subscription = firestoreService.getUserRides(currentUser.uid).listen((
      rides,
    ) {
      final activeRides = rides
          .where(
            (ride) =>
                ride.status != RideStatus.completed &&
                ride.status != RideStatus.cancelled &&
                ride.status != RideStatus.failed,
          )
          .toList();

      if (mounted) {
        setState(() {
          _activeRide = activeRides.isNotEmpty ? activeRides.first : null;
        });
      }
    });
    _subscriptions.add(subscription);
  }

  // Check for online drivers
  Future<void> _checkOnlineDrivers() async {
    setState(() {
      _isCheckingDrivers = true;
    });

    try {
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );
      final drivers = await firestoreService.getOnlineDrivers();

      setState(() {
        _onlineDrivers = drivers;
        _isCheckingDrivers = false;
      });
    } catch (e) {
      setState(() {
        _onlineDrivers = [];
        _isCheckingDrivers = false;
      });
    }
  }

  // Listen to notifications for ride declines and no drivers available
  void _listenToNotifications() {
    final authService = Provider.of<AuthService>(context, listen: false);

    final currentUser = authService.currentUser;
    if (currentUser == null) return; // Null safety check

    // Listen for ride declined notifications
    final declinedSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: currentUser.uid)
        .where('type', isEqualTo: 'ride_declined')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          for (var doc in snapshot.docs) {
            final data = doc.data();
            _showDriverDeclineDialog(data['rideId'], doc.id);
          }
        });
    _subscriptions.add(declinedSub);

    // Listen for no drivers available notifications
    final noDriversSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: currentUser.uid)
        .where('type', isEqualTo: 'no_drivers_available')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          for (var doc in snapshot.docs) {
            final data = doc.data();
            _showNoDriversAvailableDialog(data['rideId'], doc.id);
          }
        });
    _subscriptions.add(noDriversSub);
  }

  /// Listen to ride changes directly (notifications removed)
  void _listenToPassengerNotifications() {
    final authService = Provider.of<AuthService>(context, listen: false);

    final currentUser = authService.currentUser;
    if (currentUser == null) return; // Null safety check

    // Listen directly to rides collection for real-time updates
    final ridesSub = FirebaseFirestore.instance
        .collection('rides')
        .where('passengerId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.modified) {
              final rideData = change.doc.data();
              if (rideData == null) continue;

              final status = rideData['status'] as String?;

              // Handle ride status changes
              if (status == 'accepted') {
                print('✅ Ride accepted by driver');
              } else if (status == 'started') {
                print('🚗 Ride started');
              } else if (status == 'completed') {
                print('🎉 Ride completed');
              }
            }
          }
        });
    _subscriptions.add(ridesSub);
  }

  // Notification methods removed - using direct ride listening

  // Show dialog when driver declines ride
  Future<void> _showDriverDeclineDialog(
    String rideId,
    String notificationId,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text('Driver Declined'),
            ],
          ),
          content: const Text(
            'The assigned driver declined your ride request. Would you like us to find another driver for you?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel Ride'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Find Another Driver'),
            ),
          ],
        );
      },
    );

    // Mark notification as read
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});

    if (result == true) {
      // Passenger wants to find another driver - monitor the ride status
      if (mounted) {
        SnackbarHelper.showInfo(context, 'Looking for another driver...');

        // Monitor ride status for reassignment or failure
        _monitorRideReassignment(rideId);
      }
    } else if (result == false) {
      // Passenger wants to cancel the ride
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );
      await firestoreService.updateRideStatus(rideId, RideStatus.cancelled);

      if (mounted) {
        SnackbarHelper.showSuccess(context, 'Ride cancelled successfully');
      }
    }
  }

  // Show dialog when no drivers are available
  Future<void> _showNoDriversAvailableDialog(
    String rideId,
    String notificationId,
  ) async {
    // Mark notification as read first (if notificationId is provided)
    if (notificationId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.infoColor),
              const SizedBox(width: 8),
              const Text('No Drivers Available'),
            ],
          ),
          content: const Text(
            'Sorry, there are no drivers available at the moment. Please try booking again later.',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to home tab
                setState(() {
                  _currentIndex = 0;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    // Show notification message
    if (mounted) {
      SnackbarHelper.showWarning(
        context,
        'No drivers available. Please try again later.',
        seconds: 3,
      );
    }
  }

  // Monitor ride reassignment after passenger chooses to find another driver
  void _monitorRideReassignment(String rideId) {
    // Listen to ride status changes for a limited time (30 seconds)
    late StreamSubscription<DocumentSnapshot> subscription;
    Timer? timeoutTimer;

    subscription = FirebaseFirestore.instance
        .collection('rides')
        .doc(rideId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists || !mounted) {
            subscription.cancel();
            timeoutTimer?.cancel();
            return;
          }

          final rideData = snapshot.data() as Map<String, dynamic>;
          final status = rideData['status'] as String?;

          if (status == 'failed') {
            // Ride failed - no drivers available
            subscription.cancel();
            timeoutTimer?.cancel();

            if (mounted) {
              _showNoDriversAvailableDialog(rideId, '');
            }
          } else if (status == 'pending' && rideData.containsKey('driverId')) {
            // Successfully reassigned to another driver
            subscription.cancel();
            timeoutTimer?.cancel();

            if (mounted) {
              SnackbarHelper.showSuccess(
                context,
                'Found another driver! Your ride is confirmed.',
                seconds: 3,
              );
            }
          }
        });

    // Set timeout to stop monitoring after 30 seconds
    timeoutTimer = Timer(const Duration(seconds: 30), () {
      subscription.cancel();
      if (mounted) {
        SnackbarHelper.showInfo(
          context,
          'Still looking for drivers. Please wait...',
          seconds: 3,
        );
      }
    });
  }

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
              Icon(Icons.logout, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              const Text('Confirm Logout'),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out of your  account?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Color(0xFF757575),
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

  // Check driver availability before booking
  Future<void> _checkDriverAvailabilityAndBook() async {
    setState(() {
      _isCheckingDrivers = true;
    });

    await _checkOnlineDrivers();

    if (_onlineDrivers.isEmpty) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  const Text('No Drivers Available'),
                ],
              ),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sorry, there are currently no drivers online in your area.',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Please try again in a few minutes or contact TODA support.',
                    style: TextStyle(fontSize: 14, color: Colors.black),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Try Again',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _checkOnlineDrivers(); // Refresh driver list
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Refresh',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      }
    } else {
      // Drivers available, proceed to booking
      if (mounted) {
        Navigator.of(context).push(
          SlidePageRoute(
            child: const BookRideScreen(),
            direction: AxisDirection.left,
          ),
        );
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

    // If there's an active ride, show the active ride screen
    if (_activeRide != null) {
      return ActiveRideScreen(ride: _activeRide!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passenger Dashboard'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
      ),
      drawer: Drawer(child: _ProfileDrawer(onLogout: _showLogoutConfirmation)),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HomeTab(
            onTabChange: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            onBookRide: _checkDriverAvailabilityAndBook,
            onlineDrivers: _onlineDrivers,
            isCheckingDrivers: _isCheckingDrivers,
            onRefreshDrivers: _checkOnlineDrivers,
          ),
          const RideHistoryScreen(),
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
            // Gradient effect for selected item
            if (_currentIndex == 0)
              Positioned(
                left: 0,
                right: MediaQuery.of(context).size.width / 2,
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
              )
            else if (_currentIndex == 1)
              Positioned(
                left: MediaQuery.of(context).size.width / 2,
                right: 0,
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
                  icon: Icon(Icons.home_outlined),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Color(0xFF0D7CFF), Color(0xFF0052CC)],
                    ).createShader(bounds),
                    child: Icon(Icons.home, color: Colors.white),
                  ),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history_outlined),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [Color(0xFF0D7CFF), Color(0xFF0052CC)],
                    ).createShader(bounds),
                    child: Icon(Icons.history, color: Colors.white),
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

class _HomeTab extends StatelessWidget {
  final Function(int) onTabChange;
  final VoidCallback onBookRide;
  final List<Map<String, dynamic>> onlineDrivers;
  final bool isCheckingDrivers;
  final VoidCallback onRefreshDrivers;

  const _HomeTab({
    required this.onTabChange,
    required this.onBookRide,
    required this.onlineDrivers,
    required this.isCheckingDrivers,
    required this.onRefreshDrivers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: CustomScrollView(
        slivers: [
          // Main Action Card - Book a Ride
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBDBDBD), width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFF2D2D2D),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.local_taxi,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ready to go?',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D2D2D),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Book a ride now',
                                style: TextStyle(
                                  color: Color(0xFF757575),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: isCheckingDrivers ? null : onBookRide,
                        icon: isCheckingDrivers
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_location_alt, size: 20),
                        label: Text(
                          isCheckingDrivers ? 'Checking...' : 'Book a Ride',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D2D2D),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Driver Availability Status
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    onlineDrivers.isNotEmpty
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                    color: onlineDrivers.isNotEmpty
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF9500),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          onlineDrivers.isNotEmpty
                              ? '${onlineDrivers.length} Drivers Online'
                              : 'No Drivers Available',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          onlineDrivers.isNotEmpty
                              ? 'Ready to serve you'
                              : 'Try again later',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onRefreshDrivers,
                    icon: const Icon(Icons.refresh, size: 20),
                    color: const Color(0xFF757575),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // Stats Card
          const SliverToBoxAdapter(child: StatsCard()),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // Recent Destinations
          const SliverToBoxAdapter(child: RecentDestinationsCard()),

          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }
}

class _ProfileDrawer extends StatelessWidget {
  final VoidCallback onLogout;

  const _ProfileDrawer({required this.onLogout});

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
              user?.name.substring(0, 1).toUpperCase() ?? 'P',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D2D),
              ),
            ),
          ),
          accountName: Text(
            user?.name ?? 'Passenger',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          accountEmail: Text(
            user?.email ?? '',
            style: const TextStyle(fontSize: 14),
          ),
        ),

        // Profile Options
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Color(0xFF757575)),
                title: const Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: Color(0xFF2D2D2D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Color(0xFF757575),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EditProfileScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings, color: Color(0xFF757575)),
                title: const Text(
                  'Settings',
                  style: TextStyle(
                    color: Color(0xFF2D2D2D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Color(0xFF757575),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.help, color: Color(0xFF757575)),
                title: const Text(
                  'Help & Support',
                  style: TextStyle(
                    color: Color(0xFF2D2D2D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Color(0xFF757575),
                ),
                onTap: () {
                  Navigator.pop(context);
                  SnackbarHelper.showInfo(
                    context,
                    'Help & Support feature coming soon!',
                  );
                },
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

// Edit Profile Screen
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUserModel;

    if (user != null) {
      _nameController.text = user.name;
      _phoneController.text = user.phone;
      _emailController.text = user.email;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );

      if (authService.currentUser != null) {
        await firestoreService.updateUserProfile(authService.currentUser!.uid, {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'updatedAt': Timestamp.now(),
        });

        await authService.refreshUserData();

        if (mounted) {
          setState(() {
            _isEditing = false;
          });

          SnackbarHelper.showSuccess(context, 'Profile updated successfully!');
        }
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error updating profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Edit Profile',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Profile Picture Section
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFBDBDBD),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFFF5F5F5),
                        child: const Icon(
                          Icons.person_outline,
                          size: 40,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () {
                        SnackbarHelper.showInfo(
                          context,
                          'Photo upload feature coming soon!',
                        );
                      },
                      icon: const Icon(
                        Icons.camera_alt_outlined,
                        size: 14,
                        color: Color(0xFF757575),
                      ),
                      label: const Text(
                        'Change Photo',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Form Fields - Clean and Minimal
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const Text(
                        'Personal Information',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Full Name
                    Container(
                      decoration: BoxDecoration(
                        color: _isEditing
                            ? Colors.white
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFBDBDBD),
                          width: 1.5,
                        ),
                      ),
                      child: TextFormField(
                        controller: _nameController,
                        enabled: _isEditing,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          labelStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.black,
                          ),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            size: 18,
                            color: Color(0xFF757575),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your full name';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Phone Number
                    Container(
                      decoration: BoxDecoration(
                        color: _isEditing
                            ? Colors.white
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFBDBDBD),
                          width: 1.5,
                        ),
                      ),
                      child: TextFormField(
                        controller: _phoneController,
                        enabled: _isEditing,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          labelStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.black,
                          ),
                          prefixIcon: Icon(
                            Icons.phone_outlined,
                            size: 18,
                            color: Color(0xFF757575),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your phone number';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Email Address
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFBDBDBD),
                          width: 1.5,
                        ),
                      ),
                      child: TextFormField(
                        controller: _emailController,
                        enabled: false,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.black,
                          ),
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            size: 18,
                            color: Color(0xFF757575),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Text(
                          'Email cannot be changed',
                          style: TextStyle(fontSize: 11, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom Action Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: const Color(0xFFBDBDBD), width: 1.5),
              ),
            ),
            child: Row(
              children: [
                if (_isEditing) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _isEditing = false;
                                _loadUserData();
                              });
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF757575),
                        side: const BorderSide(
                          color: Color(0xFFBDBDBD),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D2D2D),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
                if (!_isEditing) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isEditing = true;
                        });
                      },
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D2D2D),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Settings Screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _locationEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          // Notifications Section
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBDBDBD), width: 1.5),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: const Text(
                'Push Notifications',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              subtitle: const Text(
                'Receive ride updates and alerts',
                style: TextStyle(fontSize: 12, color: Colors.black),
              ),
              value: _notificationsEnabled,
              activeColor: const Color(0xFF4CAF50),
              onChanged: (value) {
                setState(() {
                  _notificationsEnabled = value;
                });
                SnackbarHelper.showInfo(
                  context,
                  _notificationsEnabled
                      ? 'Notifications enabled'
                      : 'Notifications disabled',
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Privacy Section
          const Text(
            'Privacy & Location',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBDBDBD), width: 1.5),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              title: const Text(
                'Location Services',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              subtitle: const Text(
                'Allow location access for ride booking',
                style: TextStyle(fontSize: 12, color: Colors.black),
              ),
              value: _locationEnabled,
              activeColor: const Color(0xFF4CAF50),
              onChanged: (value) {
                setState(() {
                  _locationEnabled = value;
                });
                SnackbarHelper.showInfo(
                  context,
                  _locationEnabled
                      ? 'Location services enabled'
                      : 'Location services disabled',
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // About Section
          const Text(
            'About',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBDBDBD), width: 1.5),
            ),
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: const Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Color(0xFF757575),
                  ),
                  title: const Text(
                    'App Version',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  subtitle: const Text(
                    '1.0.0',
                    style: TextStyle(fontSize: 12, color: Colors.black),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Color(0xFF757575),
                  ),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'yourapp',
                      applicationVersion: '1.0.0',
                      applicationLegalese: '© 2024 yourapp TODA System',
                    );
                  },
                ),
                Divider(height: 1, thickness: 1, color: Colors.white),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: const Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: Color(0xFF757575),
                  ),
                  title: const Text(
                    'Change Password',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Color(0xFF757575),
                  ),
                  onTap: () {
                    SnackbarHelper.showInfo(
                      context,
                      'Password change feature coming soon!',
                    );
                  },
                ),
                Divider(height: 1, thickness: 1, color: Colors.white),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.privacy_tip_outlined,
                      size: 18,
                      color: Color(0xFF757575),
                    ),
                  ),
                  title: const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Color(0xFF757575),
                  ),
                  onTap: () {
                    SnackbarHelper.showInfo(
                      context,
                      'Privacy policy feature coming soon!',
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceModeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFF3B30).withOpacity(0.05),
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
