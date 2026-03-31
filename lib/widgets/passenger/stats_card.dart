import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../models/ride_model.dart';
import '../../services/fare_service.dart';
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

        return Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Total Rides',
                value: completedRides.length.toString(),
                icon: Icons.directions_car_rounded,
                backgroundColor: const Color(0xFFE8F5FF),
                iconColor: const Color(0xFF2196F3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'This Month',
                value: thisMonthRides.toString(),
                icon: Icons.calendar_today_rounded,
                backgroundColor: const Color(0xFFE8F5E9),
                iconColor: const Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Spent',
                value: FareService.formatFare(totalSpent),
                icon: Icons.account_balance_wallet_rounded,
                backgroundColor: const Color(0xFFFFF3E0),
                iconColor: const Color(0xFFFF9800),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Icon container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          // Value
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A1A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          // Label
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
