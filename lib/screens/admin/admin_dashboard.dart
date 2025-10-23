import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/driver_model.dart';
import '../../models/ride_model.dart';
import '../../widgets/usability_helpers.dart';
import 'driver_management_screen.dart';
import 'ride_monitoring_screen.dart';
import 'geofence_management_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  bool _isMaintenanceMode = false;

  @override
  void initState() {
    super.initState();
    _checkMaintenanceMode();
    _listenToAdminNotifications();
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

  Future<void> _toggleMaintenanceMode() async {
    try {
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );
      await firestoreService.setMaintenanceMode(!_isMaintenanceMode);

      if (mounted) {
        SnackbarHelper.showSuccess( // Replace SnackBar call
          context,
          _isMaintenanceMode
              ? 'Maintenance mode enabled'
              : 'Maintenance mode disabled',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error toggling maintenance mode: $e'); // Replace SnackBar call
      }
    }
  }

  /// Listen to admin-specific notifications
  void _listenToAdminNotifications() {
    final authService = Provider.of<AuthService>(context, listen: false);

    if (authService.currentUser != null) {
      // Listen for new driver registration notifications
      FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: authService.currentUser!.uid)
          .where('type', isEqualTo: 'new_driver_registration')
          .where('read', isEqualTo: false)
          .snapshots()
          .listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                // Driver registration notification handled by WebSocket service automatically
                _markNotificationAsRead(change.doc.id);
              }
            }
          });

      // Listen for system alert notifications
      FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: authService.currentUser!.uid)
          .where('type', isEqualTo: 'system_alert')
          .where('read', isEqualTo: false)
          .snapshots()
          .listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                // System alert notification handled by WebSocket service automatically
                _markNotificationAsRead(change.doc.id);
              }
            }
          });
    }
  }

  /// Mark notification as read
  Future<void> _markNotificationAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (e) {
      print('Error marking notification as read: $e');
    }
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
              Icon(Icons.logout, color: const Color(0xFF2D2D2D)),
              const SizedBox(width: 8),
              const Text('Confirm Logout'),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out of your account?',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.black,
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
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('TODA Admin'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            // Modern drawer header
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF2D2D2D),
              ),
              accountName: Text(
                user.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              accountEmail: Text(
                user.email,
                style: const TextStyle(fontSize: 14),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.admin_panel_settings,
                  size: 40,
                  color: const Color(0xFF2D2D2D),
                ),
              ),
            ),

            // System controls section
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SizedBox(height: 16),

                  // System controls section
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: const Text(
                      'System Controls',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),

                  // Maintenance mode toggle
                  ListTile(
                    leading: Icon(
                      _isMaintenanceMode ? Icons.build : Icons.build_outlined,
                      color: _isMaintenanceMode
                          ? const Color(0xFFFF3B30)
                          : const Color(0xFF2D2D2D),
                    ),
                    title: Text(
                      'Maintenance Mode',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: _isMaintenanceMode
                            ? FontWeight.bold
                            : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _isMaintenanceMode
                          ? 'System is under maintenance'
                          : 'System is operational',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black,
                      ),
                    ),
                    trailing: Switch(
                      value: _isMaintenanceMode,
                      onChanged: (value) => _toggleMaintenanceMode(),
                      activeColor: const Color(0xFFFF3B30),
                    ),
                    onTap: _toggleMaintenanceMode,
                  ),

                  const SizedBox(height: 16),

                  // App info section
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: const Text(
                      'Application Info',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),

                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Color(0xFF2D2D2D)),
                    title: const Text(
                      'About',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'TODA Transport Management System',
                      style: TextStyle(color: Colors.black),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      SnackbarHelper.showInfo(context, 'TODA Admin v1.0.0');
                    },
                  ),
                ],
              ),
            ),

            // Bottom section with logout
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFF2D2D2D)),
              title: const Text(
                'Sign Out',
                style: TextStyle(
                  color: Color(0xFF2D2D2D),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showLogoutConfirmation();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _DashboardTab(),
          DriverManagementScreen(),
          RideMonitoringScreen(),
          GeofenceManagementScreen(),
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
              left: _currentIndex * (MediaQuery.of(context).size.width / 4),
              right: MediaQuery.of(context).size.width - ((_currentIndex + 1) * (MediaQuery.of(context).size.width / 4)),
              bottom: 0,
              child: Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF0D7CFF),
                      Color(0xFF0052CC),
                    ],
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
              selectedFontSize: 11,
              unselectedFontSize: 10,
              elevation: 0,
              items: [
                BottomNavigationBarItem(
                  icon: const Icon(Icons.dashboard_outlined),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFF0D7CFF),
                        Color(0xFF0052CC),
                      ],
                    ).createShader(bounds),
                    child: const Icon(Icons.dashboard, color: Colors.white),
                  ),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.people_outline),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFF0D7CFF),
                        Color(0xFF0052CC),
                      ],
                    ).createShader(bounds),
                    child: const Icon(Icons.people, color: Colors.white),
                  ),
                  label: 'Drivers',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.monitor_outlined),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFF0D7CFF),
                        Color(0xFF0052CC),
                      ],
                    ).createShader(bounds),
                    child: const Icon(Icons.monitor, color: Colors.white),
                  ),
                  label: 'Rides',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.map_outlined),
                  activeIcon: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Color(0xFF0D7CFF),
                        Color(0xFF0052CC),
                      ],
                    ).createShader(bounds),
                    child: const Icon(Icons.map, color: Colors.white),
                  ),
                  label: 'Geofence',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Container(
      color: Colors.grey[50],
      child: CustomScrollView(
        slivers: [
          // System status card
          SliverToBoxAdapter(
            child: StreamBuilder<bool>(
              stream: firestoreService.getMaintenanceModeStream(),
              builder: (context, snapshot) {
                final isMaintenanceMode = snapshot.data ?? false;

                return Container(
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMaintenanceMode
                        ? const Color(0xFFFF3B30)
                        : const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          isMaintenanceMode
                              ? Icons.construction
                              : Icons.check_circle,
                          size: 32,
                          color: isMaintenanceMode
                              ? Colors.white
                              : const Color(0xFF34C759),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isMaintenanceMode
                                    ? 'MAINTENANCE MODE'
                                    : 'SYSTEM ONLINE',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isMaintenanceMode
                                    ? 'System under maintenance'
                                    : 'All systems operational',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Quick stats header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.analytics_outlined,
                    color: Color(0xFF2D2D2D),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Quick Stats',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Stats cards grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverToBoxAdapter(
              child: StreamBuilder<List<DriverModel>>(
                stream: firestoreService.getAllDrivers(),
                builder: (context, driverSnapshot) {
                  return StreamBuilder<List<RideModel>>(
                    stream: firestoreService.getAllActiveRides(),
                    builder: (context, rideSnapshot) {
                      final drivers = driverSnapshot.data ?? [];
                      final activeRides = rideSnapshot.data ?? [];
                      final approvedDrivers = drivers
                          .where((d) => d.isApproved)
                          .length;
                      final pendingDrivers = drivers
                          .where((d) => !d.isApproved)
                          .length;
                      final onlineDrivers = drivers
                          .where((d) => d.isApproved && d.isInQueue)
                          .length;

                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  title: 'Active Rides',
                                  value: activeRides.length.toString(),
                                  icon: Icons.electric_rickshaw,
                                  color: const Color(0xFF2D2D2D),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  title: 'Online Drivers',
                                  value: onlineDrivers.toString(),
                                  icon: Icons.person_outline,
                                  color: const Color(0xFF34C759),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  title: 'Approved',
                                  value: approvedDrivers.toString(),
                                  icon: Icons.verified_outlined,
                                  color: const Color(0xFF5856D6),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  title: 'Pending',
                                  value: pendingDrivers.toString(),
                                  icon: Icons.pending_outlined,
                                  color: const Color(0xFFFF9500),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF0D7CFF), Color(0xFF0052CC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Icon(
                icon,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D2D2D),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF757575),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
