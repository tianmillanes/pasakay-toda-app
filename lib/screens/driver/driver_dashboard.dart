import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/fcm_notification_service.dart';
import '../../services/fare_service.dart';
import '../../models/driver_model.dart';
import '../../models/ride_model.dart';
import '../../models/pasabuy_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/custom_appbars.dart';
import '../../utils/app_theme.dart';
import 'driver_registration_screen.dart';
import 'queue_screen.dart';
import 'active_trip_screen.dart';
import 'history_hub_screen.dart';
import 'pasabuy_active_ride_screen.dart';
import 'gcash_qr_display_screen.dart';
import 'payment_proof_screen.dart';
import '../../models/barangay_model.dart';
import '../../widgets/barangay_selector.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  int _currentIndex = 0;
  DriverModel? _driverProfile;
  RideModel? _activeRide;
  PasaBuyModel? _activePasaBuy;
  bool _isMaintenanceMode = false;
  bool _isLoading = true;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _membershipNoticeSubscription;
  final List<Map<String, dynamic>> _pendingMembershipNotices = [];
  bool _isShowingMembershipNotice = false;
  StreamSubscription? _fareUpdateSubscription;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadDriverProfile();
    _checkMaintenanceMode();
    _checkActiveRide();
    _checkActivePasaBuy();
    _listenToDriverNotifications();
    _listenToMembershipNotices();
    _listenToFareUpdates();
  }

  void _listenToFareUpdates() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final uid = authService.currentUser?.uid;
    if (uid == null) return;

    _fareUpdateSubscription = FareService.fareRulesStream.listen((snapshot) async {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final updatedAt = data['updatedAt'] as Timestamp?;
        
        if (updatedAt != null) {
          final fareUpdateTime = updatedAt.toDate();
          
          // Get user's last seen fare update from their Firestore doc
          final userDoc = await FirebaseFirestore.instance
              .collection('users').doc(uid).get();
          final userData = userDoc.data();
          final lastSeenTs = userData?['lastSeenFareUpdate'] as Timestamp?;
          final lastSeen = lastSeenTs?.toDate();

          // Show popup if user has never seen an update, or fare is newer
          if (lastSeen == null || fareUpdateTime.isAfter(lastSeen)) {
            if (mounted) {
              _showFareUpdatedDialog(data);
              // Mark as seen
              await FirebaseFirestore.instance
                  .collection('users').doc(uid)
                  .set({'lastSeenFareUpdate': updatedAt}, SetOptions(merge: true));
            }
          }
        }
      }
    });
  }

  void _showFareUpdatedDialog(Map<String, dynamic> fareData) {
    final baseFare = (fareData['baseFare'] ?? 20.0).toDouble();
    final firstTwoKmFare = (fareData['firstTwoKmFare'] ?? 20.0).toDouble();
    final farePer500m = (fareData['farePer500m'] ?? 10.0).toDouble();
    final minimumFare = (fareData['minimumFare'] ?? 20.0).toDouble();
    final surgeMultiplier = (fareData['surgeMultiplier'] ?? 1.0).toDouble();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreenLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.price_change_rounded, color: AppTheme.primaryGreen, size: 32),
            ),
            const SizedBox(height: 12),
            const Text('Fare Rates Updated', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text(
              'Admin has updated the fare structure. The new rates apply to all your succeeding trips.',
              style: TextStyle(fontWeight: FontWeight.w400, fontSize: 13, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        content: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _fareAdvisoryRow('Base Fare', '₱${baseFare.toStringAsFixed(2)}'),
              const Divider(height: 16, color: AppTheme.borderLight),
              _fareAdvisoryRow('First 2km', '₱${firstTwoKmFare.toStringAsFixed(2)}'),
              const Divider(height: 16, color: AppTheme.borderLight),
              _fareAdvisoryRow('Per 500m (after 2km)', '₱${farePer500m.toStringAsFixed(2)}'),
              const Divider(height: 16, color: AppTheme.borderLight),
              _fareAdvisoryRow('Minimum Fare', '₱${minimumFare.toStringAsFixed(2)}'),
              if (surgeMultiplier > 1.0) ...[
                const Divider(height: 16, color: AppTheme.borderLight),
                _fareAdvisoryRow('⚡ Surge Multiplier', '${surgeMultiplier.toStringAsFixed(1)}x', highlight: true),
              ],
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('I Understand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fareAdvisoryRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: highlight ? Colors.orange.shade700 : AppTheme.textSecondary,
        )),
        Text(value, style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          color: highlight ? Colors.orange.shade700 : AppTheme.textPrimary,
        )),
      ],
    );
  }

  /// Initialize FCM notifications for this driver
  void _initializeNotifications() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser != null) {
        final userId = authService.currentUser!.uid;
        print('✅ Driver initialized: $userId');
      }
    } catch (e) {
      print('⚠️ Error initializing driver: $e');
    }
  }

  Future<void> _loadDriverProfile() async {
    print('🔄 [DriverDashboard._loadDriverProfile] Loading driver profile...');
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
        '   Profile loaded: ${profile?.name}, isApproved=${profile?.isApproved}, isInQueue=${profile?.isInQueue}',
      );
      if (mounted) {
        print('   Updating dashboard state...');
        setState(() {
          _driverProfile = profile;
          _isLoading = false;
        });
        print('✅ [DriverDashboard._loadDriverProfile] Dashboard updated');
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

  void _checkActivePasaBuy() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    if (authService.currentUser != null) {
      firestoreService
          .getActivePasaBuyForDriver(authService.currentUser!.uid)
          .listen((requests) {
            if (mounted) {
              setState(() {
                _activePasaBuy = requests.isNotEmpty ? requests.first : null;
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

  void _listenToMembershipNotices() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final uid = authService.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    _membershipNoticeSubscription?.cancel();
    _membershipNoticeSubscription = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('type', isEqualTo: 'membership_expiration')
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        _pendingMembershipNotices.add({
          'id': change.doc.id,
          ...data,
        });
      }
      _showNextMembershipNoticeIfNeeded();
    });
  }

  Future<void> _showNextMembershipNoticeIfNeeded() async {
    if (!mounted) return;
    if (_isShowingMembershipNotice) return;
    if (_pendingMembershipNotices.isEmpty) return;

    _isShowingMembershipNotice = true;
    final notice = _pendingMembershipNotices.removeAt(0);
    final noticeId = notice['id'] as String? ?? '';
    final title = notice['title'] as String? ?? 'Notice';
    final body = notice['body'] as String? ?? '';

    if (noticeId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(noticeId)
          .update({'read': true});
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: Colors.orange.shade700,
                  size: 24,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    _isShowingMembershipNotice = false;
    _showNextMembershipNoticeIfNeeded();
  }

  @override
  void dispose() {
    _membershipNoticeSubscription?.cancel();
    _fareUpdateSubscription?.cancel();
    super.dispose();
  }

  // Show logout confirmation dialog
  Future<void> _showLogoutConfirmation() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.logout_rounded, color: Colors.red, size: 24),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sign Out?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Are you sure you want to log out of your driver account?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
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
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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

    if (shouldLogout == true && mounted) {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  // Show deactivation dialog
  Future<void> _showDeactivationDialog() async {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.block_rounded, color: Colors.red, size: 24),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Account Deactivated',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your driver account has been suspended by the administrator. Please contact support for more information.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final authService = Provider.of<AuthService>(context, listen: false);
                      await authService.signOut();
                      if (mounted) {
                        Navigator.of(context).pushReplacementNamed('/login');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Exit App', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Show monthly earnings history modal
  Future<void> _showMonthlyEarningsHistory(BuildContext context, List<RideModel> allTrips) async {
    // Get PasaBuy earnings data as well
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final driverId = authService.currentUser?.uid;
    
    List<PasaBuyModel> allPasaBuyRequests = [];
    if (driverId != null) {
      try {
        // Get all completed PasaBuy requests for this driver
        final pasaBuySnapshot = await FirebaseFirestore.instance
            .collection('pasabuy_requests')
            .where('driverId', isEqualTo: driverId)
            .where('status', isEqualTo: 'completed')
            .get();
        
        allPasaBuyRequests = pasaBuySnapshot.docs
            .map((doc) => PasaBuyModel.fromFirestore(doc))
            .toList();
      } catch (e) {
        print('Error fetching PasaBuy history: $e');
      }
    }
    
    // Calculate earnings for the last 6 months
    final now = DateTime.now();
    final monthlyData = <Map<String, dynamic>>[];
    
    for (int i = 0; i < 6; i++) {
      final targetMonth = DateTime(now.year, now.month - i, 1);
      final monthName = _getMonthName(targetMonth.month);
      final year = targetMonth.year;
      
      // Filter ride trips for this month
      final monthTrips = allTrips.where((trip) {
        return trip.status == RideStatus.completed &&
            trip.completedAt != null &&
            trip.completedAt!.year == year &&
            trip.completedAt!.month == targetMonth.month;
      }).toList();
      
      // Filter PasaBuy requests for this month
      final monthPasaBuy = allPasaBuyRequests.where((request) {
        return request.completedAt != null &&
            request.completedAt!.year == year &&
            request.completedAt!.month == targetMonth.month;
      }).toList();
      
      final rideEarnings = monthTrips.fold<double>(0.0, (sum, trip) => sum + trip.fare);
      final pasaBuyEarnings = monthPasaBuy.fold<double>(0.0, (sum, request) => sum + request.budget);
      final totalEarnings = rideEarnings + pasaBuyEarnings;
      
      final rideCount = monthTrips.length;
      final pasaBuyCount = monthPasaBuy.length;
      final totalCount = rideCount + pasaBuyCount;
      
      monthlyData.add({
        'month': monthName,
        'year': year,
        'totalEarnings': totalEarnings,
        'rideEarnings': rideEarnings,
        'pasaBuyEarnings': pasaBuyEarnings,
        'rideCount': rideCount,
        'pasaBuyCount': pasaBuyCount,
        'totalCount': totalCount,
        'isCurrentMonth': i == 0,
      });
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
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
            
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.trending_up_rounded,
                      color: AppTheme.primaryGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Earnings History',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          'Rides & PasaBuy earnings - Last 6 months',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF757575),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Monthly data list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: monthlyData.length,
                itemBuilder: (context, index) {
                  final data = monthlyData[index];
                  final isCurrentMonth = data['isCurrentMonth'] as bool;
                  final totalEarnings = data['totalEarnings'] as double;
                  final rideEarnings = data['rideEarnings'] as double;
                  final pasaBuyEarnings = data['pasaBuyEarnings'] as double;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isCurrentMonth ? AppTheme.primaryGreen.withOpacity(0.05) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCurrentMonth ? AppTheme.primaryGreen.withOpacity(0.2) : Colors.grey.shade200,
                        width: isCurrentMonth ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Header row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '${data['month']} ${data['year']}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: isCurrentMonth ? AppTheme.primaryGreen : const Color(0xFF1A1A1A),
                                        ),
                                      ),
                                      if (isCurrentMonth) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryGreen,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Current',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${data['totalCount']} total services',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Total earnings
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  FareService.formatFare(totalEarnings),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: isCurrentMonth ? AppTheme.primaryGreen : const Color(0xFF1A1A1A),
                                  ),
                                ),
                                if (totalEarnings > 0 && data['totalCount'] > 0) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '₱${(totalEarnings / (data['totalCount'] as int)).toStringAsFixed(0)}/service',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        
                        // Breakdown if both services have earnings
                        if (rideEarnings > 0 && pasaBuyEarnings > 0) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                // Rides
                                Expanded(
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.local_taxi_rounded, size: 16, color: AppTheme.primaryGreen),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Rides',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        FareService.formatFare(rideEarnings),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1A1A1A),
                                        ),
                                      ),
                                      Text(
                                        '${data['rideCount']} trips',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: Colors.grey.shade200,
                                ),
                                
                                // PasaBuy
                                Expanded(
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.shopping_bag_rounded, size: 16, color: Colors.orange),
                                          const SizedBox(width: 4),
                                          Text(
                                            'PasaBuy',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        FareService.formatFare(pasaBuyEarnings),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1A1A1A),
                                        ),
                                      ),
                                      Text(
                                        '${data['pasaBuyCount']} orders',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get month name
  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUserModel;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Show loading indicator while driver profile is being loaded
    if (_isLoading) {
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

    // If driver application was rejected, show rejection screen
    if (!_driverProfile!.isApproved && _driverProfile!.rejectedAt != null) {
      return _RejectionScreen(driverProfile: _driverProfile!);
    }

    // If driver is not approved, show pending approval screen
    if (!_driverProfile!.isApproved) {
      return _PendingApprovalScreen(driverProfile: _driverProfile!);
    }

    // If driver account is deactivated, show deactivation screen and logout
    if (user?.isActive == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showDeactivationDialog();
      });
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // If there's an active ride, show the active trip screen
    if (_activeRide != null) {
      return ActiveTripScreen(ride: _activeRide!);
    }

    // If there's an active PasaBuy, show the PasaBuy active ride screen
    if (_activePasaBuy != null) {
      return PasaBuyActiveRideScreen(
        requestId: _activePasaBuy!.id,
        request: _activePasaBuy!,
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HomeTab(driverProfile: _driverProfile!),
          QueueScreen(initialDriverProfile: _driverProfile),
          const DriverHistoryHubScreen(),
          _ProfileTab(
            driverProfile: _driverProfile!,
            onLogout: _showLogoutConfirmation,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.white,
            selectedItemColor: AppTheme.primaryGreen,
            unselectedItemColor: Colors.grey[500],
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            showUnselectedLabels: true,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.queue_rounded),
                label: 'Queue',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_rounded),
                label: 'History',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
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
  late Stream<List<Map<String, dynamic>>> _rideRequestsStream;
  late Stream<List<PasaBuyModel>> _pasaBuyRequestsStream;
  late Stream<List<RideModel>> _earningsStream;
  late Stream<DriverModel?> _driverStream;
  Timer? _expirationTimer;
  List<Map<String, dynamic>> _rideRequests = [];
  List<PasaBuyModel> _pasaBuyRequests = [];
  StreamSubscription? _rideSub;
  StreamSubscription? _pasaBuySub;
  StreamSubscription? _photoUrlSub;
  final ValueNotifier<DateTime> _nowNotifier = ValueNotifier(DateTime.now());
  final Map<String, DateTime> _rideDisplayStartTimes = {};
  final Map<String, DateTime> _pasaBuyDisplayStartTimes = {};
  String? _userPhotoUrl;

  @override
  void initState() {
    super.initState();
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);
    final driverId = widget.driverProfile.id;

    _rideRequestsStream = firestoreService.getDriverNotifications(driverId);
    _pasaBuyRequestsStream = firestoreService.getAssignedPasaBuyRequestsForDriver(driverId);
    _earningsStream = firestoreService.getUserRides(driverId, isDriver: true);
    _driverStream = firestoreService.getDriverStream(driverId);

    final userId = authService.currentUser?.uid;
    if (userId != null) {
      firestoreService.getUserProfile(userId).then((userData) {
        if (!mounted || userData == null) return;
        setState(() {
          _userPhotoUrl = userData['photoUrl'] as String?;
        });
      });

      // Listen to real-time photoUrl changes
      _photoUrlSub = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          final data = snapshot.data() as Map<String, dynamic>;
          final photoUrl = data['photoUrl'] as String?;
          
          // Update state when photoUrl changes
          if (photoUrl != _userPhotoUrl) {
            setState(() {
              _userPhotoUrl = photoUrl;
            });
          }
        }
      });
    }

    _rideSub = _rideRequestsStream.listen((requests) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _rideRequests = requests;
        for (final r in requests) {
          final rideId = r['rideId'] as String?;
          if (rideId != null && !_rideDisplayStartTimes.containsKey(rideId)) {
            _rideDisplayStartTimes[rideId] = now;
          }
        }
        _rideDisplayStartTimes.removeWhere(
          (id, _) => !requests.any((r) => r['rideId'] == id),
        );
      });
    });
    
    _pasaBuySub = _pasaBuyRequestsStream.listen((requests) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _pasaBuyRequests = requests;
        for (final r in requests) {
          final id = r.id;
          if (!_pasaBuyDisplayStartTimes.containsKey(id)) {
            _pasaBuyDisplayStartTimes[id] = now;
          }
        }
        _pasaBuyDisplayStartTimes.removeWhere(
          (id, _) => !requests.any((r) => r.id == id),
        );
      });
    });

    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      _nowNotifier.value = DateTime.now();
      _checkExpirations();
    });
  }

  void _checkExpirations() {
    final now = DateTime.now();
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    for (final request in List.from(_rideRequests)) {
      final rideId = request['rideId'] as String?;
      if (rideId == null) continue;
      
      DateTime expiresAt;
      if (request['expiresAt'] is Timestamp) {
        expiresAt = (request['expiresAt'] as Timestamp).toDate();
      } else {
        final start = _rideDisplayStartTimes[rideId] ?? now;
        expiresAt = start.add(const Duration(minutes: 3));
      }

      if (now.isAfter(expiresAt)) {
        firestoreService.declineRideRequest(rideId, widget.driverProfile.id);
        setState(() {
          _rideRequests.removeWhere((r) => r['rideId'] == rideId);
          _rideDisplayStartTimes.remove(rideId);
        });
      }
    }

    for (final request in List.from(_pasaBuyRequests)) {
      final id = request.id;
      final start = _pasaBuyDisplayStartTimes[id] ?? request.createdAt;
      final expiresAt = request.expiresAt ?? start.add(const Duration(minutes: 3));

      if (now.isAfter(expiresAt)) {
        firestoreService.declinePasaBuyRequest(id, widget.driverProfile.id);
        setState(() {
          _pasaBuyRequests.removeWhere((r) => r.id == id);
          _pasaBuyDisplayStartTimes.remove(id);
        });
      }
    }
  }

  Widget _buildHeaderAvatar(String driverName) {
    final photoUrl = _userPhotoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          final bytes = base64Decode(photoUrl.split(',').last);
          return CircleAvatar(
            radius: 25,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: Image.memory(
                bytes,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
            ),
          );
        } catch (_) {}
      } else if (photoUrl.startsWith('http')) {
        return CircleAvatar(
          radius: 25,
          backgroundColor: Colors.white,
          backgroundImage: NetworkImage(photoUrl),
        );
      }
    }
    final initial = driverName.isNotEmpty ? driverName.substring(0, 1).toUpperCase() : 'D';
    return CircleAvatar(
      radius: 25,
      backgroundColor: AppTheme.primaryGreenLight,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppTheme.primaryGreen,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _expirationTimer?.cancel();
    _rideSub?.cancel();
    _pasaBuySub?.cancel();
    _photoUrlSub?.cancel();
    _nowNotifier.dispose();
    super.dispose();
  }

  // Show monthly earnings history modal
  Future<void> _showMonthlyEarningsHistory(BuildContext context, List<RideModel> allTrips) async {
    // Calculate earnings for the last 6 months (rides only)
    final now = DateTime.now();
    final monthlyData = <Map<String, dynamic>>[];
    
    for (int i = 0; i < 6; i++) {
      final targetMonth = DateTime(now.year, now.month - i, 1);
      final monthName = _getMonthName(targetMonth.month);
      final year = targetMonth.year;
      
      // Filter ride trips for this month
      final monthTrips = allTrips.where((trip) {
        return trip.status == RideStatus.completed &&
            trip.completedAt != null &&
            trip.completedAt!.year == year &&
            trip.completedAt!.month == targetMonth.month;
      }).toList();
      
      final rideEarnings = monthTrips.fold<double>(0.0, (sum, trip) => sum + trip.fare);
      final rideCount = monthTrips.length;
      
      monthlyData.add({
        'month': monthName,
        'year': year,
        'totalEarnings': rideEarnings,
        'rideCount': rideCount,
        'isCurrentMonth': i == 0,
      });
    }

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
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
            
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.trending_up_rounded,
                      color: AppTheme.primaryGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Earnings History',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          'Ride earnings - Last 6 months',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF757575),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Monthly data list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: monthlyData.length,
                itemBuilder: (context, index) {
                  final data = monthlyData[index];
                  final isCurrentMonth = data['isCurrentMonth'] as bool;
                  final totalEarnings = data['totalEarnings'] as double;
                  final rideCount = data['rideCount'] as int;
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isCurrentMonth ? AppTheme.primaryGreen.withOpacity(0.05) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCurrentMonth ? AppTheme.primaryGreen.withOpacity(0.2) : Colors.grey.shade200,
                        width: isCurrentMonth ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Header row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '${data['month']} ${data['year']}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: isCurrentMonth ? AppTheme.primaryGreen : const Color(0xFF1A1A1A),
                                        ),
                                      ),
                                      if (isCurrentMonth) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryGreen,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'Current',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$rideCount trips',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Total earnings
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  FareService.formatFare(totalEarnings),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: isCurrentMonth ? AppTheme.primaryGreen : const Color(0xFF1A1A1A),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get month name
  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  @override
  void didUpdateWidget(_HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.driverProfile.id != oldWidget.driverProfile.id) {
      _rideSub?.cancel();
      _pasaBuySub?.cancel();
      
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final driverId = widget.driverProfile.id;
      _rideRequestsStream = firestoreService.getDriverNotifications(driverId);
      _pasaBuyRequestsStream = firestoreService.getAssignedPasaBuyRequestsForDriver(driverId);
      _earningsStream = firestoreService.getUserRides(driverId, isDriver: true);
      _driverStream = firestoreService.getDriverStream(driverId);

      _rideSub = _rideRequestsStream.listen((requests) {
        if (mounted) setState(() => _rideRequests = requests);
      });
      
      _pasaBuySub = _pasaBuyRequestsStream.listen((requests) {
        if (mounted) setState(() => _pasaBuyRequests = requests);
      });
    }
  }

  Widget _buildRideRequestCard(
    BuildContext context,
    Map<String, dynamic> request,
    FirestoreService firestoreService,
  ) {
    final rideId = request['rideId'] as String? ?? '';
    final passengerName = request['passengerName'] as String? ?? 'Passenger';
    final passengerPhone = request['passengerPhone'] as String? ?? '';
    final pickupAddress = request['pickupAddress'] as String? ?? 'Pickup location';
    final destinationAddress = request['destinationAddress'] as String? ?? 'Destination';
    final fare = (request['fare'] ?? 0.0).toDouble();

    if (rideId.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16, left: 20, right: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'RIDE REQUEST',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                ValueListenableBuilder<DateTime>(
                  valueListenable: _nowNotifier,
                  builder: (context, now, child) {
                    DateTime end;
                    if (request['expiresAt'] is Timestamp) {
                      end = (request['expiresAt'] as Timestamp).toDate();
                    } else {
                      final start = _rideDisplayStartTimes[rideId] ?? now;
                      end = start.add(const Duration(minutes: 3));
                    }
                    final timeLeft = end.difference(now);
                    final minutes = timeLeft.inMinutes;
                    final seconds = timeLeft.inSeconds % 60;
                    final displayTime = timeLeft.isNegative 
                        ? 'Expired' 
                        : '${minutes}:${seconds.toString().padLeft(2, '0')}';
                    
                    return Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: timeLeft.inSeconds < 30 ? Colors.red : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displayTime,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: timeLeft.inSeconds < 30 ? Colors.red : Colors.orange,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          
          // Progress Bar
          ValueListenableBuilder<DateTime>(
            valueListenable: _nowNotifier,
            builder: (context, now, child) {
              DateTime end;
              if (request['expiresAt'] is Timestamp) {
                end = (request['expiresAt'] as Timestamp).toDate();
              } else {
                final fallbackStart = _rideDisplayStartTimes[rideId] ?? now;
                end = fallbackStart.add(const Duration(minutes: 3));
              }
              
              DateTime start = end.subtract(const Duration(minutes: 3));
              final totalDuration = 180000; // 3 minutes in milliseconds
              final remaining = end.difference(now).inMilliseconds;

              final progress = remaining > 0 ? (remaining / totalDuration).clamp(0.0, 1.0) : 0.0;
              
              return LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade100,
                color: progress < 0.3 ? Colors.red : Colors.orange,
                minHeight: 3,
              );
            },
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF5F5F5)),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            passengerName,
                            style: const TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.w600, 
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                passengerPhone,
                                style: TextStyle(
                                  fontSize: 13, 
                                  color: Colors.grey.shade500, 
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (request['passengerCount'] != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  '${request['passengerCount']} ${request['passengerCount'] == 1 ? 'passenger' : 'passengers'}',
                                  style: TextStyle(
                                    fontSize: 13, 
                                    color: Colors.grey.shade500, 
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      FareService.formatFare(fare),
                      style: const TextStyle(
                        fontSize: 20, 
                        fontWeight: FontWeight.w700, 
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _LocationRow(icon: Icons.circle, iconColor: AppTheme.primaryGreen, address: pickupAddress),
                const SizedBox(height: 12),
                _LocationRow(icon: Icons.location_on, iconColor: Colors.red, address: destinationAddress),
                
                if (request['notes'] != null && request['notes'].toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NOTE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request['notes'].toString(),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _declineRide(context, rideId, firestoreService),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptRide(context, rideId, firestoreService),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Accept Ride', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasaBuyRequestCard(
    BuildContext context,
    PasaBuyModel request,
    FirestoreService firestoreService,
  ) {
    final fare = request.budget.toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 16, left: 20, right: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'PASABUY REQUEST',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                ValueListenableBuilder<DateTime>(
                  valueListenable: _nowNotifier,
                  builder: (context, now, child) {
                    final start = _pasaBuyDisplayStartTimes[request.id] ?? request.createdAt;
                    final end = request.expiresAt ?? start.add(const Duration(minutes: 3));
                    final timeLeft = end.difference(now);
                    final minutes = timeLeft.inMinutes;
                    final seconds = timeLeft.inSeconds % 60;
                    final displayTime = timeLeft.isNegative
                        ? 'Expired'
                        : '${minutes}:${seconds.toString().padLeft(2, '0')}';

                    return Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: timeLeft.inSeconds < 30 ? Colors.red : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displayTime,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: timeLeft.inSeconds < 30 ? Colors.red : Colors.orange,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          // Progress Bar
          ValueListenableBuilder<DateTime>(
            valueListenable: _nowNotifier,
            builder: (context, now, child) {
              final end = request.expiresAt ?? (request.createdAt).add(const Duration(minutes: 3));
              final start = end.subtract(const Duration(minutes: 3));
              final totalDuration = 180000; // 3 minutes in milliseconds
              final remaining = end.difference(now).inMilliseconds;

              final progress = remaining > 0 ? (remaining / totalDuration).clamp(0.0, 1.0) : 0.0;

              return LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade100,
                color: progress < 0.3 ? Colors.red : Colors.orange,
                minHeight: 3,
              );
            },
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF5F5F5)),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.passengerName,
                            style: const TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.w600, 
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            request.passengerPhone,
                            style: TextStyle(
                              fontSize: 13, 
                              color: Colors.grey.shade500, 
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          FareService.formatFare(fare),
                          style: const TextStyle(
                            fontSize: 20, 
                            fontWeight: FontWeight.w700, 
                            color: Colors.orange,
                          ),
                        ),
                        const Text(
                          'Budget',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Items
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.orange.shade700),
                              const SizedBox(width: 6),
                              Text(
                                'ITEMS TO BUY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orange.shade700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          if (request.itemDescription.length > 100)
                            const Icon(Icons.more_horiz, size: 14, color: Colors.orange),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        request.itemDescription,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade800,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                _LocationRow(icon: Icons.storefront_rounded, iconColor: Colors.orange, address: request.pickupAddress),
                const SizedBox(height: 12),
                _LocationRow(icon: Icons.home_rounded, iconColor: Colors.red, address: request.dropoffAddress),
              ],
            ),
          ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _declinePasaBuyRequest(context, request, firestoreService),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptPasaBuyRequest(context, request, firestoreService),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Accept PasaBuy', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptPasaBuyRequest(
    BuildContext context,
    PasaBuyModel request,
    FirestoreService firestoreService,
  ) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final driverId = authService.currentUser?.uid;
      final driverName = authService.currentUserModel?.name ?? 'Driver';

      if (driverId == null) {
        if (mounted) {
          SnackbarHelper.showError(context, 'Error: Not logged in');
        }
        return;
      }

      final success = await firestoreService.acceptPasaBuyRequest(
        request.id,
        driverId,
        driverName,
      );

      if (mounted) {
        if (success) {
          SnackbarHelper.showSuccess(
            context,
            'PasaBuy request accepted!',
          );
          // Small delay to ensure UI updates before navigating
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Navigate to active ride screen
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => PasaBuyActiveRideScreen(
                  requestId: request.id,
                  request: request,
                ),
              ),
            );
          }
        } else {
          SnackbarHelper.showError(
            context,
            'Failed to accept request',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Error: $e',
        );
      }
    }
  }

  Future<void> _declinePasaBuyRequest(
    BuildContext context,
    PasaBuyModel request,
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

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.red, size: 24),
                  ),
                  const SizedBox(height: 16),
                  const Text('Decline Request?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 8),
                  Text('Are you sure you want to decline this PasaBuy request?', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 14)),
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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

      final success = await firestoreService.declinePasaBuyRequest(
        request.id,
        driverId,
      );

      if (mounted) {
        if (success) {
          SnackbarHelper.showSuccess(
            context,
            'Request moved to next driver',
          );
          // Small delay to ensure UI updates before rebuilding
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          SnackbarHelper.showWarning(
            context,
            'No more drivers available. Passenger will be notified.',
          );
        }
      }
    } catch (e) {
      print('Error declining PasaBuy request: $e');
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Error declining request: $e',
        );
      }
    }
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
            'Ride is no longer available',
          );
        }
        return;
      }

      await firestoreService.acceptRideRequest(rideId, driverId);
      if (mounted) {
        SnackbarHelper.showSuccess(context, 'Ride accepted successfully!');
        // Small delay to ensure UI updates before rebuilding
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      print('Error accepting ride: $e');
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
      final authService = Provider.of<AuthService>(context, listen: false);
      final driverId = authService.currentUser?.uid;

      if (driverId == null) {
        if (mounted) {
          SnackbarHelper.showError(context, 'Error: Not logged in');
        }
        return;
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.red, size: 24),
                  ),
                  const SizedBox(height: 16),
                  const Text('Decline Ride?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                  const SizedBox(height: 8),
                  Text('Are you sure you want to decline this ride request?', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 14)),
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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

      await firestoreService.declineRideRequest(rideId, driverId);
      if (mounted) {
        SnackbarHelper.showSuccess(context, 'Ride declined successfully');
        // Small delay to ensure UI updates before rebuilding
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Failed to decline ride: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);
    final driverId = authService.currentUser?.uid;

    String getGreeting() {
      final hour = DateTime.now().hour;
      if (hour < 12) return 'Good Morning';
      if (hour < 17) return 'Good Afternoon';
      return 'Good Evening';
    }

    return StreamBuilder<DriverModel?>(
      stream: _driverStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }

        final driverData = snapshot.data ?? widget.driverProfile;
        final isInQueue = driverData.isInQueue;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Premium Header
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 60, 28, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          getGreeting(),
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          driverData.name.split(' ').isNotEmpty ? driverData.name.split(' ')[0] : driverData.name,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: -1,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2), width: 2),
                      ),
                      child: _buildHeaderAvatar(driverData.name),
                    ),
                  ],
                ),
              ),
            ),

            // Online/Offline Toggle and Earnings Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    StreamBuilder<List<RideModel>>(
                      stream: _earningsStream,
                      builder: (context, ridesSnapshot) {
                        final trips = ridesSnapshot.data ?? [];
                        final now = DateTime.now();
                        
                        // Calculate Today's Earnings
                        final todayTrips = trips.where((trip) {
                          return trip.status == RideStatus.completed &&
                              trip.completedAt != null &&
                              trip.completedAt!.year == now.year &&
                              trip.completedAt!.month == now.month &&
                              trip.completedAt!.day == now.day;
                        }).toList();

                        double dailyEarnings = todayTrips.fold(0.0, (sum, trip) => sum + trip.fare);
                        
                        // Calculate Monthly Earnings
                        final monthlyTrips = trips.where((trip) {
                          return trip.status == RideStatus.completed &&
                              trip.completedAt != null &&
                              trip.completedAt!.year == now.year &&
                              trip.completedAt!.month == now.month;
                        }).toList();

                        double monthlyEarnings = monthlyTrips.fold(0.0, (sum, trip) => sum + trip.fare);
                        
                        int tripsCount = todayTrips.length;
                        double totalKm = todayTrips.fold(0.0, (sum, trip) => sum + (trip.distance ?? 0.0));
                        String ratingValue = widget.driverProfile.isApproved ? "5.0" : "0.0";

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0xFF212121),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Today's Earnings Section
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'TODAY\'S EARNINGS',
                                        style: TextStyle(
                                          color: Colors.white70, 
                                          fontSize: 11, 
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        FareService.formatFare(dailyEarnings),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 32,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryGreen,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 24),
                                  ),
                                ],
                              ),
                              
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Divider(color: Colors.white12, height: 1),
                              ),

                              // Monthly Earnings Section - Clickable
                              GestureDetector(
                                onTap: () => _showMonthlyEarningsHistory(context, trips),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'MONTHLY EARNINGS',
                                          style: TextStyle(
                                            color: Colors.white70, 
                                            fontSize: 11, 
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          FareService.formatFare(monthlyEarnings),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tap to view history',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.6),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.history_rounded, color: Colors.white, size: 20),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    ),
                  ],
                ),
              ),
            ),

            // Active Requests
            if (isInQueue && driverId != null) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 32, 24, 16),
                  child: Text(
                    'ACTIVE REQUESTS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF757575),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              
              // Ride Requests
              if (_rideRequests.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    children: _rideRequests.map((request) => _buildRideRequestCard(context, request, firestoreService)).toList(),
                  ),
                ),

              // PasaBuy Requests
              if (_pasaBuyRequests.isNotEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    children: _pasaBuyRequests.map((request) => _buildPasaBuyRequestCard(context, request, firestoreService)).toList(),
                  ),
                ),
              
              // Empty State (if both are empty)
              if (_rideRequests.isEmpty && _pasaBuyRequests.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.notifications_none_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'Waiting for requests...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'New requests will appear here',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ] else ...[
              // Offline State
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        
                        const Text(
                          'You are currently offline',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Go online to start receiving ride and shopping requests.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        );
      },
    );
  }
}

class _LocationRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String address;

  const _LocationRow({required this.icon, required this.iconColor, required this.address});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(fontSize: 14, color: Color(0xFF4A4A4A), fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _QuickStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _ProfileTab extends StatefulWidget {
  final DriverModel driverProfile;
  final VoidCallback onLogout;

  const _ProfileTab({required this.driverProfile, required this.onLogout});

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  String? _userPhotoUrl;
  StreamSubscription? _photoUrlSub;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final userId = authService.currentUser?.uid;
    if (userId != null) {
      firestoreService.getUserProfile(userId).then((userData) {
        if (!mounted || userData == null) return;
        setState(() {
          _userPhotoUrl = userData['photoUrl'] as String?;
        });
      });

      // Listen to real-time photoUrl changes
      _photoUrlSub = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          final data = snapshot.data() as Map<String, dynamic>;
          final photoUrl = data['photoUrl'] as String?;
          
          // Update state when photoUrl changes
          if (photoUrl != _userPhotoUrl) {
            setState(() {
              _userPhotoUrl = photoUrl;
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _photoUrlSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driverProfile = widget.driverProfile;
    final onLogout = widget.onLogout;
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Profile Header with Avatar and Info
                  Row(
                    children: [
                      // Avatar Section
                      GestureDetector(
                        onTap: () => _showPhotoOptions(context, driverProfile),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primaryGreen.withOpacity(0.2),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryGreen.withOpacity(0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: _buildProfileTabAvatar(driverProfile.name),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Driver Info Section
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverProfile.name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A1A),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppTheme.primaryGreen.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified_rounded, color: AppTheme.primaryGreen, size: 16),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Verified Driver',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.primaryGreen,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Ready to serve your community',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Settings Button
                      GestureDetector(
                        onTap: () {
                          onLogout();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Icon(Icons.logout_rounded, color: Colors.red.shade600, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Quick Stats
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Today\'s Trips',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '0',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'Earnings',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₱0.00',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primaryGreen,
                                ),
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
          ),
          // Quick Actions Section
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                    children: [
                      _QuickActionCard(
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'GCash QR',
                        subtitle: 'Manage payments',
                        color: AppTheme.primaryGreen,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => GcashQrDisplayScreen()),
                          );
                        },
                      ),
                      _QuickActionCard(
                        icon: Icons.person_outline_rounded,
                        title: 'Edit Profile',
                        subtitle: 'Update info',
                        color: const Color(0xFF8B5CF6),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const DriverEditProfileScreen()),
                          );
                        },
                      ),
                      _QuickActionCard(
                        icon: Icons.directions_car_filled_rounded,
                        title: 'Vehicle Info',
                        subtitle: 'Tricycle details',
                        color: const Color(0xFF3B82F6),
                        onTap: () => _showVehicleInfo(context, driverProfile),
                      ),
                      _QuickActionCard(
                        icon: Icons.security_rounded,
                        title: 'Privacy',
                        subtitle: 'Security settings',
                        color: const Color(0xFFF59E0B),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const DriverPrivacySecurityScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVehicleInfo(BuildContext context, DriverModel driverProfile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Vehicle Information',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildInfoRow(Icons.directions_car_rounded, 'Vehicle Type', driverProfile.vehicleType),
            _buildInfoRow(Icons.tag_rounded, 'Plate Number', driverProfile.tricyclePlateNumber ?? driverProfile.plateNumber),
            _buildInfoRow(Icons.location_city_rounded, 'Barangay', driverProfile.barangayName),
            _buildInfoRow(Icons.badge_rounded, 'License Number', driverProfile.driverLicenseNumber ?? driverProfile.licenseNumber),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTabAvatar(String driverName) {
    final photoUrl = _userPhotoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          final bytes = base64Decode(photoUrl.split(',').last);
          return CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: Image.memory(
                bytes,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
          );
        } catch (_) {}
      } else if (photoUrl.startsWith('http')) {
        return CircleAvatar(
          radius: 40,
          backgroundColor: Colors.white,
          backgroundImage: NetworkImage(photoUrl),
        );
      }
    }
    final initial = driverName.isNotEmpty ? driverName.substring(0, 1).toUpperCase() : 'D';
    return CircleAvatar(
      radius: 40,
      backgroundColor: AppTheme.primaryGreenLight,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppTheme.primaryGreen,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.accentBlue, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreenLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF1A1A1A),
            letterSpacing: -0.3,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300, size: 24),
        onTap: onTap,
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showPhotoOptions(BuildContext context, DriverModel driverProfile) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Profile Photo',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PhotoOptionButton(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                onTap: () async {
                  Navigator.pop(context);
                  await _handleImagePicker(context, ImageSource.camera);
                },
              ),
              _PhotoOptionButton(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                onTap: () async {
                  Navigator.pop(context);
                  await _handleImagePicker(context, ImageSource.gallery);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

Future<void> _handleImagePicker(BuildContext context, ImageSource source) async {
  try {
    final XFile? pickedFile = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    
    if (pickedFile != null && context.mounted) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final user = authService.currentUser;

      if (user == null) {
        if (context.mounted) {
          Navigator.pop(context); // Close loading
          SnackbarHelper.showError(context, 'Error: Not logged in');
        }
        return;
      }

      // Upload image using the correct method
      final photoUrl = await firestoreService.uploadDriverProfileImage(
        user.uid,
        pickedFile,
      );

      // Update user profile with new photo URL
      await firestoreService.updateUserProfile(user.uid, {
        'photoUrl': photoUrl,
      });

      if (context.mounted) {
        Navigator.pop(context); // Close loading
        SnackbarHelper.showSuccess(context, 'Profile photo updated successfully!');
      }
    }
  } catch (e) {
    if (context.mounted) {
      // Close loading if it's open
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      SnackbarHelper.showError(context, 'Error updating photo: $e');
    }
  }
}

class _PhotoOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PhotoOptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Icon(icon, color: Colors.grey.shade600, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// Driver Privacy and Security Screen
class DriverPrivacySecurityScreen extends StatefulWidget {
  const DriverPrivacySecurityScreen({super.key});

  @override
  State<DriverPrivacySecurityScreen> createState() => _DriverPrivacySecurityScreenState();
}

class _DriverPrivacySecurityScreenState extends State<DriverPrivacySecurityScreen> {
  bool _isLoading = false;

  Future<void> _handlePasswordReset() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    
    if (user != null && user.email != null) {
      setState(() => _isLoading = true);
      try {
        await authService.sendPasswordResetEmail(user.email!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Password reset email sent to ${user.email}'),
              backgroundColor: AppTheme.primaryGreen,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Delete Account?', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This action is permanent and cannot be undone. All your data will be removed.'),
                const SizedBox(height: 20),
                Text(
                  'To confirm, please type "DELETE MY ACCOUNT" below:',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: 'DELETE MY ACCOUNT',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.red),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(
                onPressed: controller.text == 'DELETE MY ACCOUNT' 
                  ? () => Navigator.pop(context, true) 
                  : null,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  disabledForegroundColor: Colors.grey.shade300,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ),
      );

      if (confirm == true) {
        setState(() => _isLoading = true);
        bool deletionSuccessful = false;
        
        while (!deletionSuccessful && mounted) {
          try {
            await authService.deleteAccount();
            deletionSuccessful = true;
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Account deleted successfully'),
                  backgroundColor: AppTheme.primaryGreen,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              if (e.toString().contains('requires-recent-login')) {
                setState(() => _isLoading = false);
                final reauthSuccess = await _showReauthDialog();
                if (reauthSuccess == true && mounted) {
                  setState(() => _isLoading = true);
                  continue; // Retry deletion
                } else {
                  break; // User cancelled reauth or it failed
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not delete account: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
                break;
              }
            } else {
              break;
            }
          }
        }
        if (mounted) setState(() => _isLoading = false);
      }
    } finally {
      controller.dispose();
      focusNode.dispose();
    }
  }

  Future<bool?> _showReauthDialog() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final passwordController = TextEditingController();
    final focusNode = FocusNode();
    bool isReauthLoading = false;

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Re-authentication Required', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('For security reasons, please enter your password to confirm account deletion.'),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordController,
                  focusNode: focusNode,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isReauthLoading ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isReauthLoading ? null : () async {
                  if (passwordController.text.isEmpty) return;
                  
                  setDialogState(() => isReauthLoading = true);
                  try {
                    await authService.reauthenticate(passwordController.text);
                    if (context.mounted) {
                      Navigator.pop(context, true); // Close reauth dialog with success
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invalid password. Please try again.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } finally {
                    if (context.mounted) setDialogState(() => isReauthLoading = false);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: isReauthLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm'),
              ),
            ],
          ),
        ),
      );
      return result;
    } finally {
      passwordController.dispose();
      focusNode.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Privacy and Security', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(28.0),
            children: [
              const Text('PASSWORD MANAGEMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 16),
              _buildSecurityTile(
                icon: Icons.lock_reset_rounded,
                title: 'Change Password',
                subtitle: 'Send reset link to your email',
                onTap: _isLoading ? null : _handlePasswordReset,
              ),
              const SizedBox(height: 32),
              const Text('ACCOUNT PRIVACY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 16),
              _buildSecurityTile(
                icon: Icons.delete_forever_rounded,
                title: 'Delete Account',
                subtitle: 'Permanently remove your account',
                isDestructive: true,
                onTap: _isLoading ? null : _handleDeleteAccount,
              ),
              const SizedBox(height: 40),
              Center(
                child: Text(
                  'Your data is encrypted and secure.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen)),
            ),
        ],
      ),
    );
  }

  Widget _buildSecurityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100, width: 2),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDestructive ? Colors.red.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: isDestructive ? Colors.red : AppTheme.primaryGreen, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: isDestructive ? Colors.red : const Color(0xFF1A1A1A),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 14),
        onTap: onTap,
      ),
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
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.engineering_rounded, size: 80, color: Colors.orange),
              ),
              const SizedBox(height: 32),
              const Text(
                'Under Maintenance',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -1),
              ),
              const SizedBox(height: 16),
              Text(
                'Pasakay Toda is currently undergoing scheduled maintenance to improve our service.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Back to Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
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
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: AppTheme.primaryGreenLight, shape: BoxShape.circle),
                child: const Icon(Icons.verified_user_rounded, size: 80, color: AppTheme.primaryGreen),
              ),
              const SizedBox(height: 32),
              const Text(
                'Approval Pending',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -1),
              ),
              const SizedBox(height: 16),
              Text(
                'Your application is being reviewed. We\'ll notify you once you\'re ready to hit the road!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final state = context.findAncestorStateOfType<_DriverDashboardState>();
                    state?._showLogoutConfirmation();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Sign Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RejectionScreen extends StatelessWidget {
  final DriverModel driverProfile;
  const _RejectionScreen({required this.driverProfile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Color(0xFFFFF1F1), shape: BoxShape.circle),
                child: const Icon(Icons.cancel_rounded, size: 80, color: Colors.red),
              ),
              const SizedBox(height: 32),
              const Text(
                'Application Status',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -1),
              ),
              const SizedBox(height: 16),
              Text(
                'Unfortunately, your application was not approved at this time. Please contact your barangay admin.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final state = context.findAncestorStateOfType<_DriverDashboardState>();
                    state?._showLogoutConfirmation();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Sign Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnpaidStatusScreen extends StatelessWidget {
  final DriverModel driverProfile;
  const _UnpaidStatusScreen({required this.driverProfile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: Icon(Icons.payment_rounded, size: 80, color: Colors.orange.shade700),
              ),
              const SizedBox(height: 32),
              const Text(
                'Payment Required',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -1),
              ),
              const SizedBox(height: 16),
              Text(
                'Your account is unpaid. Please settle your payment.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final state = context.findAncestorStateOfType<_DriverDashboardState>();
                    state?._showLogoutConfirmation();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Sign Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Global Helper Widgets updated for consistency
Widget _DetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
      ],
    ),
  );
}

Widget _DetailField(String label, String value, IconData icon) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.primaryGreenLight, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: AppTheme.primaryGreen),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _GridDetailCard(String label, String value, IconData icon) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade100, width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: AppTheme.primaryGreen),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
      ],
    ),
  );
}

Widget _Badge(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5),
    ),
  );
}

// Driver Edit Profile Screen
class DriverEditProfileScreen extends StatefulWidget {
  const DriverEditProfileScreen({super.key});

  @override
  State<DriverEditProfileScreen> createState() => _DriverEditProfileScreenState();
}

class _DriverEditProfileScreenState extends State<DriverEditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _isEditing = false;
  final ImagePicker _imagePicker = ImagePicker();
  String? _photoUrl;
  bool _isUploadingPhoto = false;
  BarangayModel? _selectedBarangay;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  void _loadDriverData() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    
    if (authService.currentUser != null) {
      firestoreService.getUserProfile(authService.currentUser!.uid).then((userData) {
        if (userData != null && mounted) {
          setState(() {
            _nameController.text = userData['name'] ?? '';
            _phoneController.text = userData['phone'] ?? '';
            _emailController.text = userData['email'] ?? '';
            _photoUrl = userData['photoUrl'] as String?;
            if (userData['barangayId'] != null && userData['barangayId'].toString().isNotEmpty) {
              _selectedBarangay = BarangayModel(
                id: userData['barangayId'] as String,
                name: userData['barangayName'] as String? ?? '',
                municipality: '', 
                province: '',
                createdAt: DateTime.now(),
                isActive: true,
              );
            }
          });
        }
      });
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final source = await SnackbarHelper.showImageSourceDialog(context);
      if (source == null) return;

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        await _uploadProfileImage(pickedFile);
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error picking image: $e');
      }
    }
  }

  Future<void> _uploadProfileImage(XFile imageFile) async {
    try {
      setState(() {
        _isUploadingPhoto = true;
      });

      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final user = authService.currentUser;

      if (user == null) {
        if (mounted) {
          SnackbarHelper.showError(context, 'Error: Not logged in');
        }
        return;
      }

      final photoUrl = await firestoreService.uploadDriverProfileImage(
        user.uid,
        imageFile,
      );

      if (mounted) {
        setState(() {
          _photoUrl = photoUrl;
        });
        SnackbarHelper.showSuccess(context, 'Profile photo updated');
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error uploading photo: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);

      if (authService.currentUser != null) {
        await firestoreService.updateUserProfile(authService.currentUser!.uid, {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'barangayId': _selectedBarangay?.id ?? '',
          'barangayName': _selectedBarangay?.name ?? '',
          'updatedAt': Timestamp.now(),
        });

        await authService.refreshUserData();

        if (mounted) {
          setState(() {
            _isEditing = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: AppTheme.primaryGreen,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A1A1A))),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
      ),
      backgroundColor: const Color(0xFFF8F9FA),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Avatar Section with Camera Button
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppTheme.primaryGreen.withOpacity(0.8), AppTheme.primaryGreen],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryGreen.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                )
                              ],
                            ),
                            child: _buildProfileAvatarChild(),
                          ),
                          if (_isUploadingPhoto)
                            SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _isUploadingPhoto ? null : _pickProfileImage,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryGreen,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryGreen.withOpacity(0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    )
                                  ],
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'Tap camera to update photo',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Form Fields
                    _buildModernEditField(
                      controller: _nameController,
                      label: 'Full Name',
                      icon: Icons.person_outline_rounded,
                      enabled: _isEditing,
                      hint: 'Enter your full name',
                    ),
                    const SizedBox(height: 20),
                    _buildModernEditField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      icon: Icons.phone_outlined,
                      enabled: false,
                      keyboardType: TextInputType.phone,
                      hint: 'Phone number',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Phone number cannot be changed for security reasons',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 20),
                    _buildModernEditField(
                      controller: _emailController,
                      label: 'Email Address',
                      icon: Icons.email_outlined,
                      enabled: false,
                      hint: 'Email address',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Email address cannot be changed for account security',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Barangay',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: _isEditing ? 1.0 : 0.6,
                      child: IgnorePointer(
                        ignoring: !_isEditing,
                        child: BarangaySelector(
                          selectedBarangay: _selectedBarangay,
                          onBarangaySelected: (barangay) {
                            setState(() {
                              _selectedBarangay = barangay;
                            });
                          },
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                )
              ],
            ),
            child: SafeArea(
              top: false,
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
                                  _loadDriverData();
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.grey.shade700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isEditing = true;
                          });
                        },
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        label: const Text('Edit Profile', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatarChild() {
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      if (_photoUrl!.startsWith('data:image')) {
        try {
          final bytes = base64Decode(_photoUrl!.split(',').last);
          return ClipOval(
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              width: 100,
              height: 100,
            ),
          );
        } catch (_) {}
      } else if (_photoUrl!.startsWith('http')) {
        return ClipOval(
          child: Image.network(
            _photoUrl!,
            fit: BoxFit.cover,
            width: 100,
            height: 100,
            errorBuilder: (context, error, stackTrace) => _buildProfileInitials(),
          ),
        );
      }
    }
    return _buildProfileInitials();
  }

  Widget _buildProfileInitials() {
    final initial = _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : 'D';
    return Text(
      initial,
      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.primaryGreen),
    );
  }

  Widget _buildModernEditField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    TextInputType? keyboardType,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: enabled ? Colors.white : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? Colors.grey.shade200 : Colors.grey.shade100,
              width: 1.5,
            ),
          ),
          child: TextFormField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: enabled ? AppTheme.primaryGreen : Colors.grey.shade400, size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              hintText: hint,
              hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}
