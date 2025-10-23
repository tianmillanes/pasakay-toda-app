import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../models/ride_model.dart';
import '../../utils/app_theme.dart';
import '../../screens/passenger/book_ride_screen.dart';
import '../../widgets/usability_helpers.dart';

class RecentDestinationsCard extends StatelessWidget {
  const RecentDestinationsCard({super.key});

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
          return Card(
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
              height: 150,
              child: const Center(
                child: ProgressIndicatorWithMessage(
                  message: 'Loading destinations...',
                ),
              ),
            ),
          );
        }

        final rides = snapshot.data ?? [];
        final completedRides = rides
            .where((r) => r.status == RideStatus.completed && r.completedAt != null)
            .toList()
          ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));

        // Get unique recent destinations (last 5, sorted by most recent)
        final Map<String, Map<String, dynamic>> uniqueDestinations = {};
        for (final ride in completedRides) {
          final key = ride.dropoffAddress.toLowerCase().trim();
          if (!uniqueDestinations.containsKey(key)) {
            uniqueDestinations[key] = {
              'ride': ride,
              'lastUsed': ride.completedAt!,
            };
          } else {
            // Keep the most recent occurrence
            final existing = uniqueDestinations[key]!['lastUsed'] as DateTime;
            if (ride.completedAt!.isAfter(existing)) {
              uniqueDestinations[key] = {
                'ride': ride,
                'lastUsed': ride.completedAt!,
              };
            }
          }
        }

        // Sort by most recent and take top 5
        final recentDestinations = uniqueDestinations.values
            .toList()
          ..sort((a, b) => (b['lastUsed'] as DateTime).compareTo(a['lastUsed'] as DateTime));
        
        final displayDestinations = recentDestinations
            .take(5)
            .map((item) => item['ride'] as RideModel)
            .toList();

        if (displayDestinations.isEmpty) {
          return Card(
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
                      const Icon(
                        Icons.location_history,
                        color: Color(0xFFFF5252),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Recent Destinations',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  EmptyStateWidget(
                    message: 'No recent destinations yet',
                    subtitle: 'Complete your first ride to see them here!',
                    icon: Icons.location_on_outlined,
                  ),
                ],
              ),
            ),
          );
        }

        return Semantics(
          label: 'Recent destinations. ${displayDestinations.length} destinations available',
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
                      const Icon(
                        Icons.location_history,
                        color: Color(0xFFFF5252),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Recent Destinations',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...displayDestinations.map((ride) => _DestinationItem(
                    ride: ride,
                    onTap: () => _quickBookToDestination(context, ride),
                  )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _quickBookToDestination(BuildContext context, RideModel ride) async {
    // First, check for online drivers
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF2D2D2D),
          ),
        );
      },
    );

    try {
      // Check for online drivers
      final drivers = await firestoreService.getOnlineDrivers();
      
      // Close loading dialog
      if (context.mounted) Navigator.of(context).pop();
      
      if (drivers.isEmpty) {
        // No drivers available
        if (context.mounted) {
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
                      'Please try again in a few minutes.',
                      style: TextStyle(fontSize: 14, color: Colors.black),
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2D2D2D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              );
            },
          );
        }
        return;
      }
      
      // Drivers are available, navigate to BookRideScreen with ONLY pre-filled destination
      if (context.mounted) {
        final dropoffLocation = LatLng(
          ride.dropoffLocation.latitude,
          ride.dropoffLocation.longitude,
        );
        
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => BookRideScreen(
              // Only pre-fill destination, let passenger choose pickup
              initialDropoffLocation: dropoffLocation,
              initialDropoffAddress: ride.dropoffAddress,
            ),
          ),
        );
        
        SnackbarHelper.showSuccess(
          context,
          '${drivers.length} ${drivers.length == 1 ? 'driver' : 'drivers'} available',
          seconds: 2,
        );
      }
    } catch (e) {
      // Close loading dialog if still open
      if (context.mounted) Navigator.of(context).pop();
      
      if (context.mounted) {
        SnackbarHelper.showError(
          context,
          'Error checking driver availability',
          seconds: 3,
        );
      }
    }
  }
}

class _DestinationItem extends StatelessWidget {
  final RideModel ride;
  final VoidCallback onTap;

  const _DestinationItem({
    required this.ride,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Book ride to ${ride.dropoffAddress}, estimated fare ${ride.fare.toStringAsFixed(2)} pesos',
      button: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: const Color(0xFFBDBDBD),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Color(0xFFFF5252),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ride.dropoffAddress,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D2D2D),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.payments_outlined,
                              size: 12,
                              color: Color(0xFF757575),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '₱${ride.fare.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Color(0xFF757575),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
