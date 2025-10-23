import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/driver_model.dart';
import '../../widgets/usability_helpers.dart';
import 'driver_history_screen.dart';

class DriverManagementScreen extends StatelessWidget {
  const DriverManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<List<DriverModel>>(
        stream: firestoreService.getAllDrivers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final drivers = snapshot.data ?? [];
          final pendingDrivers = drivers.where((d) => !d.isApproved).toList();
          final approvedDrivers = drivers.where((d) => d.isApproved).toList();

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Container(
                  color: const Color(0xFFFF3B30).withOpacity(0.1),
                  child: TabBar(
                    labelColor: const Color(0xFFFF3B30),
                    unselectedLabelColor: Colors.black,
                    indicatorColor: const Color(0xFFFF3B30),
                    tabs: [
                      Tab(
                        text: 'Pending (${pendingDrivers.length})',
                        icon: const Icon(Icons.pending),
                      ),
                      Tab(
                        text: 'Approved (${approvedDrivers.length})',
                        icon: const Icon(Icons.verified),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _PendingDriversList(drivers: pendingDrivers),
                      _ApprovedDriversList(drivers: approvedDrivers),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PendingDriversList extends StatelessWidget {
  final List<DriverModel> drivers;

  const _PendingDriversList({required this.drivers});

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'No pending approvals',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 8),
            Text('', style: TextStyle(color: Colors.black)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: drivers.length,
      itemBuilder: (context, index) {
        final driver = drivers[index];
        return _DriverCard(driver: driver, isPending: true);
      },
    );
  }
}

class _ApprovedDriversList extends StatelessWidget {
  final List<DriverModel> drivers;

  const _ApprovedDriversList({required this.drivers});

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No approved drivers',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 8),
            Text('', style: TextStyle(color: Colors.black)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: drivers.length,
      itemBuilder: (context, index) {
        final driver = drivers[index];
        return _DriverCard(driver: driver, isPending: false);
      },
    );
  }
}

class _DriverCard extends StatelessWidget {
  final DriverModel driver;
  final bool isPending;

  const _DriverCard({required this.driver, required this.isPending});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with driver name and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.name.isNotEmpty ? driver.name : 'Unknown Driver',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(
                  status: driver.status,
                  isApproved: driver.isApproved,
                  isInQueue: driver.isInQueue,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Vehicle information
            _InfoRow(
              icon: Icons.confirmation_number,
              label: 'Plate Number',
              value: driver.plateNumber,
            ),
            const SizedBox(height: 4),
            _InfoRow(
              icon: Icons.credit_card,
              label: 'License',
              value: driver.licenseNumber,
            ),

            if (driver.approvedAt != null) ...[
              const SizedBox(height: 4),
              _InfoRow(
                icon: Icons.check_circle,
                label: 'Approved',
                value: DateFormat('MMM dd, yyyy').format(driver.approvedAt!),
              ),
            ],

            if (driver.isInQueue) ...[
              const SizedBox(height: 8),
              Text(
                'In Queue - Position ${driver.queuePosition}',
                style: const TextStyle(
                  color: Color(0xFF007AFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                if (isPending) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveDriver(context, driver),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectDriver(context, driver),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _viewDriverHistory(context, driver),
                      icon: const Icon(Icons.history),
                      label: const Text('History'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deactivateDriver(context, driver),
                      icon: const Icon(Icons.block),
                      label: const Text('Deactivate'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF3B30),
                        side: const BorderSide(color: Color(0xFFFF3B30)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveDriver(BuildContext context, DriverModel driver) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );

      await firestoreService.approveDriver(
        driver.id,
        authService.currentUser!.uid,
      );

      if (context.mounted) {
        SnackbarHelper.showSuccess(context, 'Driver approved successfully');
      }
    } catch (e) {
      if (context.mounted) {
        SnackbarHelper.showError(context, 'Error approving driver: $e');
      }
    }
  }

  Future<void> _rejectDriver(BuildContext context, DriverModel driver) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Reject Driver',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'Are you sure you want to reject this driver application?',
          style: TextStyle(color: Colors.black),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Reject',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        final firestoreService = Provider.of<FirestoreService>(
          context,
          listen: false,
        );
        final adminId = authService.currentUser?.uid;

        if (adminId == null) {
          throw Exception('Admin user not authenticated');
        }

        await firestoreService.deactivateDriver(driver.id, adminId);

        if (context.mounted) {
          SnackbarHelper.showSuccess(
            context,
            'Driver deactivated successfully',
          );
        }
      } catch (e) {
        if (context.mounted) {
          SnackbarHelper.showError(context, 'Error deactivating driver: $e');
        }
      }
    }
  }

  void _viewDriverHistory(BuildContext context, DriverModel driver) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DriverHistoryScreen(driver: driver),
      ),
    );
  }

  Future<void> _deactivateDriver(
    BuildContext context,
    DriverModel driver,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Deactivate Driver',
          style: TextStyle(color: Colors.black),
        ),
        content: const Text(
          'Are you sure you want to deactivate this driver? They will no longer be able to accept rides.',
          style: TextStyle(color: Colors.black),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Deactivate',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Update driver to inactive status
        await FirebaseFirestore.instance
            .collection('users')
            .doc(driver.userId)
            .update({'isActive': false});

        if (context.mounted) {
          SnackbarHelper.showSuccess(
            context,
            'Driver deactivated successfully',
          );
        }
      } catch (e) {
        if (context.mounted) {
          SnackbarHelper.showError(context, 'Error deactivating driver: $e');
        }
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF007AFF)),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Colors.black,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final DriverStatus status;
  final bool isApproved;
  final bool isInQueue;

  const _StatusChip({
    required this.status,
    required this.isApproved,
    required this.isInQueue,
  });

  @override
  Widget build(BuildContext context) {
    Color textColor;
    String text;

    if (!isApproved) {
      textColor = const Color(0xFFFF9500);
      text = 'Pending';
    } else {
      // New logic: Status based on queue and trip status
      if (status == DriverStatus.onTrip) {
        textColor = const Color(0xFF5856D6);
        text = 'On Trip';
      } else if (isInQueue) {
        // Driver is in queue = ONLINE
        textColor = const Color(0xFF34C759);
        text = 'Online';
      } else {
        // Driver is not in queue = BUSY
        textColor = const Color(0xFFFF9500);
        text = 'Busy';
      }
    }

    return Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
