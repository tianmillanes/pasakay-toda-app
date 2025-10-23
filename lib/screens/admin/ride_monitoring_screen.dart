import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/firestore_service.dart';
import '../../services/fare_service.dart';
import '../../models/ride_model.dart';
import '../../widgets/usability_helpers.dart';

class RideMonitoringScreen extends StatelessWidget {
  const RideMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<List<RideModel>>(
        stream: firestoreService.getAllActiveRides(),
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

          final activeRides = snapshot.data ?? [];

          if (activeRides.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.monitor, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No active rides',
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

          // Group rides by status
          final pendingRides = activeRides
              .where((r) => r.status == RideStatus.pending)
              .toList();
          final acceptedRides = activeRides
              .where((r) => r.status == RideStatus.accepted)
              .toList();
          final onWayRides = activeRides
              .where((r) => r.status == RideStatus.driverOnWay)
              .toList();
          final arrivedRides = activeRides
              .where((r) => r.status == RideStatus.driverArrived)
              .toList();
          final inProgressRides = activeRides
              .where((r) => r.status == RideStatus.inProgress)
              .toList();

          return Column(
            children: [
              // Summary header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.blue[50],
                child: Column(
                  children: [
                    Text(
                      '${activeRides.length} Active Rides',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatusCount(
                          'Pending',
                          pendingRides.length,
                          Colors.orange,
                        ),
                        _StatusCount(
                          'Accepted',
                          acceptedRides.length,
                          Colors.blue,
                        ),
                        _StatusCount(
                          'On Way',
                          onWayRides.length,
                          Colors.purple,
                        ),
                        _StatusCount(
                          'In Progress',
                          inProgressRides.length,
                          Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Rides list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: activeRides.length,
                  itemBuilder: (context, index) {
                    final ride = activeRides[index];
                    return _RideMonitorCard(ride: ride);
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

class _StatusCount extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatusCount(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black)),
      ],
    );
  }
}

class _RideMonitorCard extends StatelessWidget {
  final RideModel ride;

  const _RideMonitorCard({required this.ride});

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
            // Header with status and time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatusChip(status: ride.status),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Ride ID: ${ride.id.substring(0, 8)}...',
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                    ),
                    Text(
                      DateFormat('hh:mm a').format(ride.requestedAt),
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Route information
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
                    ride.pickupAddress,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

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
                    ride.dropoffAddress,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Ride details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fare: ${FareService.formatFare(ride.fare)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF000000),
                      ),
                    ),
                    Text(
                      'Duration: ${FareService.formatDuration(ride.estimatedDuration)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Passenger: ${ride.passengerId.substring(0, 8)}...',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (ride.driverId != null)
                      Text(
                        'Driver: ${ride.driverId!.substring(0, 8)}...',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Time tracking
            if (ride.acceptedAt != null || ride.startedAt != null) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              _TimelineRow(
                icon: Icons.access_time,
                label: 'Requested',
                time: ride.requestedAt,
              ),
              if (ride.acceptedAt != null)
                _TimelineRow(
                  icon: Icons.check_circle,
                  label: 'Accepted',
                  time: ride.acceptedAt!,
                ),
              if (ride.startedAt != null)
                _TimelineRow(
                  icon: Icons.play_arrow,
                  label: 'Started',
                  time: ride.startedAt!,
                ),
            ],

            // Action buttons
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _viewRideDetails(context, ride),
                    icon: const Icon(Icons.info, size: 16),
                    label: const Text('Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (ride.status == RideStatus.pending)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelRide(context, ride),
                      icon: const Icon(Icons.cancel, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _viewRideDetails(BuildContext context, RideModel ride) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ride Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ride ID: ${ride.id}'),
              const SizedBox(height: 8),
              Text('Passenger ID: ${ride.passengerId}'),
              if (ride.driverId != null) Text('Driver ID: ${ride.driverId}'),
              const SizedBox(height: 8),
              Text('Status: ${ride.status.toString().split('.').last}'),
              Text('Fare: ${FareService.formatFare(ride.fare)}'),
              Text(
                'Duration: ${FareService.formatDuration(ride.estimatedDuration)}',
              ),
              const SizedBox(height: 8),
              const Text(
                'Pickup:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(ride.pickupAddress),
              const SizedBox(height: 4),
              const Text(
                'Dropoff:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(ride.dropoffAddress),
              const SizedBox(height: 8),
              Text(
                'Requested: ${DateFormat('MMM dd, yyyy • hh:mm a').format(ride.requestedAt)}',
              ),
              if (ride.acceptedAt != null)
                Text(
                  'Accepted: ${DateFormat('MMM dd, yyyy • hh:mm a').format(ride.acceptedAt!)}',
                ),
              if (ride.startedAt != null)
                Text(
                  'Started: ${DateFormat('MMM dd, yyyy • hh:mm a').format(ride.startedAt!)}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelRide(BuildContext context, RideModel ride) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Ride'),
        content: const Text('Are you sure you want to cancel this ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final firestoreService = Provider.of<FirestoreService>(
          context,
          listen: false,
        );
        await firestoreService.updateRideStatus(ride.id, RideStatus.cancelled);

        if (context.mounted) {
          SnackbarHelper.showSuccess(context, 'Ride cancelled successfully');
        }
      } catch (e) {
        if (context.mounted) {
          SnackbarHelper.showError(context, 'Error cancelling ride: $e');
        }
      }
    }
  }
}

class _StatusChip extends StatelessWidget {
  final RideStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case RideStatus.pending:
        backgroundColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        text = 'Pending';
        break;
      case RideStatus.accepted:
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        text = 'Accepted';
        break;
      case RideStatus.driverOnWay:
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        text = 'Driver On Way';
        break;
      case RideStatus.driverArrived:
        backgroundColor = Colors.indigo[100]!;
        textColor = Colors.indigo[800]!;
        text = 'Driver Arrived';
        break;
      case RideStatus.inProgress:
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        text = 'In Progress';
        break;
      case RideStatus.completed:
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        text = 'Completed';
        break;
      case RideStatus.cancelled:
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        text = 'Cancelled';
        break;
      case RideStatus.failed:
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        text = 'Failed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final DateTime time;

  const _TimelineRow({
    required this.icon,
    required this.label,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF007AFF)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            DateFormat('hh:mm a').format(time),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
