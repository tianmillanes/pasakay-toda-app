import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/firestore_service.dart';
import '../../services/fare_service.dart';
import '../../models/driver_model.dart';
import '../../models/ride_model.dart';

class DriverHistoryScreen extends StatelessWidget {
  final DriverModel driver;

  const DriverHistoryScreen({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('${driver.name} - Ride History'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
      ),
      body: StreamBuilder<List<RideModel>>(
        stream: firestoreService.getUserRides(driver.id, isDriver: true).map(
          (rides) => rides
              .where((ride) => ride.status == RideStatus.completed)
              .toList(),
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Color(0xFFFF3B30)),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(color: Color(0xFF2D2D2D)),
                  ),
                ],
              ),
            );
          }

          final rides = snapshot.data ?? [];

          if (rides.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No ride history',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D2D2D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This driver hasn\'t completed any rides yet',
                    style: TextStyle(color: Color(0xFF2D2D2D)),
                  ),
                ],
              ),
            );
          }

          // Calculate statistics
          final totalRides = rides.length;
          final totalEarnings = rides.fold<double>(
            0,
            (sum, ride) => sum + ride.fare,
          );

          return Column(
            children: [
              // Statistics Header - Dark Theme
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatItem(
                        label: 'Total Rides',
                        value: totalRides.toString(),
                        icon: Icons.local_taxi,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: const Color(0xFF424242),
                    ),
                    Expanded(
                      child: _StatItem(
                        label: 'Total Earnings',
                        value: FareService.formatFare(totalEarnings),
                        icon: Icons.payments_outlined,
                      ),
                    ),
                  ],
                ),
              ),

              // Rides List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: rides.length,
                  itemBuilder: (context, index) {
                    final ride = rides[index];
                    return _RideHistoryCard(ride: ride);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: Colors.white,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFFBDBDBD),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  final RideModel ride;

  const _RideHistoryCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF2D2D2D).withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and Fare
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMM dd, yyyy').format(
                        ride.completedAt ?? ride.requestedAt,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF2D2D2D),
                      ),
                    ),
                    Text(
                      DateFormat('hh:mm a').format(
                        ride.completedAt ?? ride.requestedAt,
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF757575),
                      ),
                    ),
                  ],
                ),
                Text(
                  FareService.formatFare(ride.fare),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000000),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Route Information
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F9F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.trip_origin,
                        size: 14,
                        color: Color(0xFF2D2D2D),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ride.pickupAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Color(0xFFFF5252),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ride.dropoffAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF000000),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Duration
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 12,
                  color: Color(0xFF757575),
                ),
                const SizedBox(width: 4),
                Text(
                  FareService.formatDuration(ride.estimatedDuration),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF757575),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
