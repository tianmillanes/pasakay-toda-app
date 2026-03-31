import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/driver_model.dart';
import '../../models/ride_model.dart';
import '../../models/user_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import 'global_user_management_screen.dart';
import 'global_driver_approval_screen.dart';
import 'global_geofence_management_screen.dart';
import 'global_driver_payment_screen.dart';
import 'gcash_qr_management_screen.dart';
import 'global_fare_management_screen.dart';
import 'passenger_id_verification_screen.dart';
import '../../services/fare_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  bool _isMaintenanceMode = false;
  late StreamSubscription<bool> _maintenanceModeSubscription;
  late StreamSubscription<QuerySnapshot> _driverRegistrationSubscription;
  late StreamSubscription<QuerySnapshot> _systemAlertSubscription;

  @override
  void initState() {
    super.initState();
    _checkMaintenanceMode();
    _listenToAdminNotifications();
  }

  @override
  void dispose() {
    _maintenanceModeSubscription.cancel();
    _driverRegistrationSubscription.cancel();
    _systemAlertSubscription.cancel();
    super.dispose();
  }

  void _checkMaintenanceMode() {
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
    _maintenanceModeSubscription = firestoreService.getMaintenanceModeStream().listen((maintenance) {
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
        SnackbarHelper.showSuccess(
          context,
          _isMaintenanceMode
              ? 'Maintenance mode enabled'
              : 'Maintenance mode disabled',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error toggling maintenance mode: $e');
      }
    }
  }

  void _listenToAdminNotifications() {
    final authService = Provider.of<AuthService>(context, listen: false);

    if (authService.currentUser != null) {
      _driverRegistrationSubscription = FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: authService.currentUser!.uid)
          .where('type', isEqualTo: 'new_driver_registration')
          .where('read', isEqualTo: false)
          .snapshots()
          .listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                _markNotificationAsRead(change.doc.id);
              }
            }
          });

      _systemAlertSubscription = FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: authService.currentUser!.uid)
          .where('type', isEqualTo: 'system_alert')
          .where('read', isEqualTo: false)
          .snapshots()
          .listen((snapshot) {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                _markNotificationAsRead(change.doc.id);
              }
            }
          });
    }
  }

  Future<void> _markNotificationAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> _showLogoutConfirmation() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: AppTheme.backgroundWhite,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout, color: AppTheme.errorRed, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Confirm Logout', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          content: const Text(
            'Are you sure you want to log out of your admin account?',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorRed,
                foregroundColor: Colors.white,
                shadowColor: AppTheme.errorRed.withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUserModel;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen)));
    }

    if (user.role != UserRole.admin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          authService.getRedirectRoute(),
          (route) => false,
        );
        SnackbarHelper.showError(context, 'Unauthorized access. You do not have admin privileges.');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: _currentIndex == 0
          ? AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: AppTheme.backgroundWhite,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: Builder(
                builder: (context) => IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreenLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.menu, color: AppTheme.primaryGreen, size: 20),
                  ),
                ),
              ),
              actions: [
                const SizedBox(width: 8),
              ],
            )
          : null,
      drawer: _buildDrawer(user),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _DashboardTab(user: user),
          const UserManagementScreen(),
          const DriverApprovalScreen(),
          const PassengerIdVerificationScreen(),
          const GeofenceManagementScreen(),
          const DriverPaymentScreen(),
          const GlobalFareManagementScreen(),
          const GcashQrManagementScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: AppTheme.primaryGreen,
          unselectedItemColor: AppTheme.textHint,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          elevation: 0,
          backgroundColor: Colors.white,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outlined), activeIcon: Icon(Icons.people), label: 'Users'),
            BottomNavigationBarItem(icon: Icon(Icons.verified_user_outlined), activeIcon: Icon(Icons.verified_user), label: 'Drivers'),
            BottomNavigationBarItem(icon: Icon(Icons.badge_outlined), activeIcon: Icon(Icons.badge), label: 'ID'),
            BottomNavigationBarItem(icon: Icon(Icons.map_outlined), activeIcon: Icon(Icons.map), label: 'Geo'),
            BottomNavigationBarItem(icon: Icon(Icons.payment_outlined), activeIcon: Icon(Icons.payment), label: 'Pay'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Fare'),
            BottomNavigationBarItem(icon: Icon(Icons.qr_code_2_outlined), activeIcon: Icon(Icons.qr_code_2), label: 'QR'),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(UserModel user) {
    return Drawer(
      backgroundColor: AppTheme.backgroundWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topRight: Radius.circular(30), bottomRight: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            decoration: BoxDecoration(
              gradient: AppTheme.getPrimaryGradient(),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.primaryGreenLight,
                    child: Icon(Icons.admin_panel_settings, size: 30, color: AppTheme.primaryGreen),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Pasakay Administrator',
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
              children: [
                _buildDrawerHeader('SYSTEM CONTROL'),
                SwitchListTile(
                  value: _isMaintenanceMode,
                  onChanged: (v) => _toggleMaintenanceMode(),
                  activeColor: AppTheme.errorRed,
                  title: const Text('Maintenance Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(_isMaintenanceMode ? 'System is locked' : 'System is live', style: const TextStyle(fontSize: 12)),
                  secondary: Icon(Icons.build_circle, color: _isMaintenanceMode ? AppTheme.errorRed : AppTheme.textSecondary),
                ),
                
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _showLogoutConfirmation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorRed.withOpacity(0.1),
                foregroundColor: AppTheme.errorRed,
                elevation: 0,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout, size: 18),
                  SizedBox(width: 8),
                  Text('Logout Account', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textHint, letterSpacing: 1.2)),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, String? trailing, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppTheme.textSecondary, size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      trailing: trailing != null ? Text(trailing, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)) : const Icon(Icons.chevron_right, size: 18, color: AppTheme.textHint),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  final UserModel user;
  const _DashboardTab({required this.user});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 1),
          
           
             _buildMaintenanceStatus(firestoreService),
          
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('System Statistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              TextButton(onPressed: () {}, child: const Text('')),
            ],
          ),
          const SizedBox(height: 15),
          _buildAdminStats(firestoreService),
        ],
      ),
    );
  }


  Widget _buildMaintenanceStatus(FirestoreService firestoreService) {
    return StreamBuilder<bool>(
      stream: firestoreService.getMaintenanceModeStream(),
      builder: (context, snapshot) {
        final isMaintenance = snapshot.data ?? false;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: isMaintenance 
              ? const LinearGradient(colors: [Color(0xFFFF5252), Color(0xFFFF1744)])
              : const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)]),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (isMaintenance ? Colors.red : Colors.green).withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                child: Icon(isMaintenance ? Icons.warning_amber_rounded : Icons.verified_user_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isMaintenance ? 'Maintenance Active' : 'System Operational',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isMaintenance ? 'Access is restricted to admins only' : 'System is running smoothly',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdminStats(FirestoreService firestoreService) {
    return StreamBuilder<int>(
      stream: firestoreService.getTotalUsers(),
      builder: (context, totalUsersSnapshot) {
        return StreamBuilder<List<DriverModel>>(
          stream: firestoreService.getAllDrivers(),
          builder: (context, driverSnapshot) {
            return StreamBuilder<List<RideModel>>(
              stream: firestoreService.getAllActiveRides(),
              builder: (context, rideSnapshot) {
                final drivers = driverSnapshot.data ?? [];
                final activeRides = rideSnapshot.data ?? [];
                final totalUsers = totalUsersSnapshot.data ?? 0;
                final onlineDrivers = drivers.where((d) => d.isApproved && d.isInQueue).length;
                final pendingDrivers = drivers.where((d) => !d.isApproved).length;

                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 15,
                  crossAxisSpacing: 15,
                  childAspectRatio: 1.2,
                  children: [
                    _StatCard(
                      title: 'Active Rides',
                      value: activeRides.length.toString(),
                      icon: Icons.electric_rickshaw_rounded,
                      color: AppTheme.primaryGreen,
                    ),
                    _StatCard(
                      title: 'Drivers Online',
                      value: onlineDrivers.toString(),
                      icon: Icons.person_pin_circle_rounded,
                      color: AppTheme.infoBlue,
                    ),
                    _StatCard(
                      title: 'Pending Verify',
                      value: pendingDrivers.toString(),
                      icon: Icons.pending_actions_rounded,
                      color: AppTheme.warningOrange,
                    ),
                    _StatCard(
                      title: 'Total Users',
                      value: totalUsers.toString(),
                      icon: Icons.groups_rounded,
                      color: AppTheme.textPrimary,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }


}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


