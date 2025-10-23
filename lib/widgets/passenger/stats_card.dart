import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../models/ride_model.dart';
import '../../utils/app_theme.dart';
import '../common/loading_skeleton.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);

    if (authService.currentUser == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<RideModel>>(
      stream: firestoreService.getUserRides(authService.currentUser!.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const StatsCardSkeleton();
        }

        final rides = snapshot.data ?? [];
        final completedRides = rides.where((r) => r.status == RideStatus.completed).toList();
        final totalSpent = completedRides.fold<double>(0, (sum, ride) => sum + ride.fare);
        final thisMonthRides = completedRides.where((r) {
          final now = DateTime.now();
          return r.completedAt != null &&
              r.completedAt!.month == now.month &&
              r.completedAt!.year == now.year;
        }).length;

        return Semantics(
          label: 'Your ride statistics. Total rides: ${completedRides.length}, This month: $thisMonthRides, Total spent: ${totalSpent.toStringAsFixed(0)} pesos',
          child: Card(
            elevation: 6,
            shadowColor: Colors.black.withOpacity(0.15),
            shape: RoundedRectangleBorder(
              borderRadius: AppTheme.getStandardBorderRadius(),
              side: BorderSide(
                color: AppTheme.lightGray.withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: Container(
              padding: AppTheme.getStandardPadding(),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
                borderRadius: AppTheme.getStandardBorderRadius(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.analytics_outlined,
                        color: AppTheme.primaryBlue,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Your Stats',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _StatItem(
                          icon: Icons.directions_car,
                          label: 'Total Rides',
                          value: completedRides.length.toString(),
                          iconColor: const Color(0xFF757575),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatItem(
                          icon: Icons.calendar_month,
                          label: 'This Month',
                          value: thisMonthRides.toString(),
                          iconColor: const Color(0xFF757575),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatItem(
                          icon: Icons.attach_money,
                          label: 'Total Spent',
                          value: '₱${totalSpent.toStringAsFixed(0)}',
                          iconColor: const Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFBDBDBD),
            width: 1.5,
          ),
        ),
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
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
