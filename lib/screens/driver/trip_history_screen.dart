import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/fare_service.dart';
import '../../models/ride_model.dart';

class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);

    if (authService.currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view trip history')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<List<RideModel>>(
        stream: firestoreService.getUserRides(authService.currentUser!.uid, isDriver: true),
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
                      // Trigger rebuild
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final trips = snapshot.data ?? [];
          final completedTrips = trips.where((trip) => trip.status == RideStatus.completed).toList();

          if (completedTrips.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No completed trips yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your completed trips will appear here',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Calculate statistics
          double totalEarnings = completedTrips.fold(0, (sum, trip) => sum + trip.fare);
          int totalTrips = completedTrips.length;

          return Column(
            children: [
              // Enhanced statistics header
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFD0D0D0),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trip Statistics',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D2D2D),
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: 'Total Trips',
                                value: totalTrips.toString(),
                                icon: Icons.local_taxi,
                                color: const Color(0xFF2D2D2D),
                                isLight: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                title: 'Total Earnings',
                                value: FareService.formatFare(totalEarnings),
                                icon: Icons.payments,
                                color: const Color(0xFF000000),
                                isLight: false,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                title: 'Average Fare',
                                value: FareService.formatFare(totalTrips > 0 ? totalEarnings / totalTrips : 0),
                                icon: Icons.trending_up,
                                color: const Color(0xFF000000),
                                isLight: false,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatCard(
                                title: 'This Month',
                                value: _getMonthlyTrips(completedTrips).toString(),
                                icon: Icons.calendar_month,
                                color: const Color(0xFF2D2D2D),
                                isLight: false,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Trip list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: completedTrips.length,
                  itemBuilder: (context, index) {
                    final trip = completedTrips[index];
                    return _TripHistoryCard(trip: trip);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  int _getMonthlyTrips(List<RideModel> trips) {
    final now = DateTime.now();
    return trips.where((trip) => 
      trip.completedAt != null &&
      trip.completedAt!.year == now.year &&
      trip.completedAt!.month == now.month
    ).length;
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isLight;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.isLight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight ? Colors.white.withOpacity(0.2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: isLight
            ? []
            : [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
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
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isLight ? Colors.white : color,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isLight ? Colors.white : Colors.black,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TripHistoryCard extends StatelessWidget {
  final RideModel trip;

  const _TripHistoryCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD0D0D0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and fare with modern design
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF2D2D2D),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMM dd, yyyy').format(trip.completedAt ?? trip.requestedAt),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                        Text(
                          DateFormat('hh:mm a').format(trip.completedAt ?? trip.requestedAt),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF2D2D2D),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    FareService.formatFare(trip.fare),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Pickup location
            Row(
              children: [
                const Icon(
                  Icons.radio_button_checked,
                  color: Colors.green,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip.pickupAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2D2D2D),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Dropoff location
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  color: Color(0xFFFF5252),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip.dropoffAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF000000),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Trip details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Duration: ${FareService.formatDuration(trip.estimatedDuration)}',
                  style: const TextStyle(
                    color: Color(0xFF2D2D2D),
                    fontSize: 12,
                  ),
                ),
                if (trip.startedAt != null && trip.completedAt != null)
                  Text(
                    'Trip time: ${_calculateTripDuration(trip.startedAt!, trip.completedAt!)}',
                    style: const TextStyle(
                      color: Color(0xFF2D2D2D),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            
            // Notes if any
            if (trip.notes != null && trip.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Note: ${trip.notes}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _calculateTripDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final minutes = duration.inMinutes;
    
    if (minutes < 60) {
      return '${minutes}m';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return remainingMinutes > 0 ? '${hours}h ${remainingMinutes}m' : '${hours}h';
    }
  }
}
