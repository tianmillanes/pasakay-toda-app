import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/fare_service.dart';
import '../../models/pasabuy_model.dart';
import '../../utils/app_theme.dart';

class DriverPasaBuyHistoryScreen extends StatelessWidget {
  const DriverPasaBuyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);

    if (authService.currentUser == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('Please log in to view pasabuy history', style: TextStyle(fontWeight: FontWeight.w900))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<List<PasaBuyModel>>(
        stream: firestoreService.getDriverPasaBuyRequests(authService.currentUser!.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: Color(0xFFFFF1F1), shape: BoxShape.circle),
                      child: const Icon(Icons.error_outline_rounded, size: 64, color: Colors.red),
                    ),
                    const SizedBox(height: 24),
                    const Text('Oops!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 12),
                    Text('We couldn\'t load your history. ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => (context as Element).markNeedsBuild(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final requests = snapshot.data ?? [];
          final completedRequests = requests.where((req) => req.status == PasaBuyStatus.completed).toList();

          if (completedRequests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_rounded, size: 100, color: Colors.grey.shade100),
                  const SizedBox(height: 20),
                  const Text(
                    'No PasaBuy History',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Complete your first pasabuy delivery to see history',
                    style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }

          double totalEarnings = completedRequests.fold(0, (sum, req) => sum + req.fare);
          int totalDeliveries = completedRequests.length;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.only(top: 60, left: 28, right: 28, bottom: 20),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Activity',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              title: 'Deliveries Done',
                              value: totalDeliveries.toString(),
                              icon: Icons.shopping_bag_rounded,
                              color: Color(0xFFFF9800),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final request = completedRequests[index];
                      return _PasaBuyHistoryCard(request: request);
                    },
                    childCount: completedRequests.length,
                  ),
                ),
              ),
            ],
          );
        },
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A), letterSpacing: -0.5),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _PasaBuyHistoryCard extends StatelessWidget {
  final PasaBuyModel request;
  const _PasaBuyHistoryCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Color(0xFFFFF3E0),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: Color(0xFFFF9800), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM dd, yyyy').format(request.completedAt ?? request.createdAt),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFFFF9800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LocationRow(icon: Icons.shopping_bag_rounded, iconColor: Color(0xFFFF9800), address: request.pickupAddress),
                const Padding(
                  padding: EdgeInsets.only(left: 6.5, top: 2, bottom: 2),
                  child: SizedBox(height: 12, child: VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE0E0E0))),
                ),
                _LocationRow(icon: Icons.location_on_rounded, iconColor: Colors.red, address: request.dropoffAddress),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _DetailItem(label: 'TIME', value: DateFormat('hh:mm a').format(request.completedAt ?? request.createdAt)),
                    _DetailItem(label: 'PASSENGER', value: request.passengerName),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DetailItem extends StatelessWidget {
  final String label;
  final String value;
  const _DetailItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey.shade400, letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)), maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
