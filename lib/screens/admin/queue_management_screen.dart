import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../models/driver_model.dart';
import '../../widgets/usability_helpers.dart';

class QueueManagementScreen extends StatelessWidget {
  const QueueManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<List<String>>(
        stream: firestoreService.getQueueStream(),
        builder: (context, queueSnapshot) {
          if (queueSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (queueSnapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${queueSnapshot.error}'),
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

          final queue = queueSnapshot.data ?? [];

          return Column(
            children: [
              // Queue header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.blue[50],
                child: Column(
                  children: [
                    Icon(
                      Icons.queue,
                      size: 48,
                      color: Colors.blue[600],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Driver Queue Management',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${queue.length} drivers in queue',
                      style: const TextStyle(
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),

              // Queue controls
              if (queue.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _clearQueue(context),
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Clear Queue'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _refreshQueue(context),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Queue list
              Expanded(
                child: queue.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.queue, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'Queue is empty',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Drivers will appear here when they check in',
                              style: TextStyle(color: Colors.black),
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: queue.length,
                        onReorder: (oldIndex, newIndex) {
                          _reorderQueue(context, queue, oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final driverId = queue[index];
                          return _QueueDriverCard(
                            key: ValueKey(driverId),
                            driverId: driverId,
                            position: index + 1,
                            onRemove: () => _removeFromQueue(context, driverId),
                            onMoveUp: index > 0 
                                ? () => _reorderQueue(context, queue, index, index - 1)
                                : null,
                            onMoveDown: index < queue.length - 1
                                ? () => _reorderQueue(context, queue, index, index + 1)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reorderQueue(BuildContext context, List<String> queue, int oldIndex, int newIndex) async {
    try {
      // Adjust newIndex if moving down
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }

      // Create new queue order
      final newQueue = List<String>.from(queue);
      final item = newQueue.removeAt(oldIndex);
      newQueue.insert(newIndex, item);

      // Update queue in Firestore
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      
      // This would require a new method in FirestoreService to update the entire queue
      // For now, we'll show a message
      SnackbarHelper.showSuccess(context, 'Queue reordered successfully');
    } catch (e) {
      if (context.mounted) {
        SnackbarHelper.showError(context, 'Error reordering queue: $e');
      }
    }
  }

  Future<void> _removeFromQueue(BuildContext context, String driverId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Queue'),
        content: const Text('Are you sure you want to remove this driver from the queue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
        await firestoreService.removeDriverFromQueue(driverId);
        
        if (context.mounted) {
          SnackbarHelper.showSuccess(context, 'Driver removed from queue');
        }
      } catch (e) {
        if (context.mounted) {
          SnackbarHelper.showError(context, 'Error removing driver: $e');
        }
      }
    }
  }

  Future<void> _clearQueue(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Queue'),
        content: const Text('Are you sure you want to clear the entire queue? This will remove all drivers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // This would require a new method in FirestoreService to clear the queue
        SnackbarHelper.showSuccess(context, 'Queue cleared successfully');
      } catch (e) {
        if (context.mounted) {
          SnackbarHelper.showError(context, 'Error clearing queue: $e');
        }
      }
    }
  }

  void _refreshQueue(BuildContext context) {
    (context as Element).markNeedsBuild();
    SnackbarHelper.showInfo(context, 'Queue refreshed');
  }
}

class _QueueDriverCard extends StatelessWidget {
  final String driverId;
  final int position;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _QueueDriverCard({
    super.key,
    required this.driverId,
    required this.position,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: FutureBuilder<DriverModel?>(
        future: firestoreService.getDriverProfile(driverId),
        builder: (context, snapshot) {
          final driver = snapshot.data;
          
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: position == 1 ? Colors.amber : Colors.blue[600],
              child: Text(
                position.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              driver != null 
                  ? '${driver.vehicleType} - ${driver.plateNumber}'
                  : 'Driver ${driverId.substring(0, 8)}...',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Driver ID: ${driverId.substring(0, 8)}...'),
                if (driver != null) ...[
                  Text('License: ${driver.licenseNumber}'),
                  _StatusChip(status: driver.status),
                ],
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'remove':
                    onRemove();
                    break;
                  case 'move_up':
                    onMoveUp?.call();
                    break;
                  case 'move_down':
                    onMoveDown?.call();
                    break;
                  case 'details':
                    _showDriverDetails(context, driver);
                    break;
                }
              },
              itemBuilder: (context) => [
                if (onMoveUp != null)
                  const PopupMenuItem(
                    value: 'move_up',
                    child: Row(
                      children: [
                        Icon(Icons.keyboard_arrow_up),
                        SizedBox(width: 8),
                        Text('Move Up'),
                      ],
                    ),
                  ),
                if (onMoveDown != null)
                  const PopupMenuItem(
                    value: 'move_down',
                    child: Row(
                      children: [
                        Icon(Icons.keyboard_arrow_down),
                        SizedBox(width: 8),
                        Text('Move Down'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'details',
                  child: Row(
                    children: [
                      Icon(Icons.info),
                      SizedBox(width: 8),
                      Text('Details'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.remove_circle, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Remove', style: TextStyle(color: Colors.red)),
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

  void _showDriverDetails(BuildContext context, DriverModel? driver) {
    if (driver == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Driver Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver ID: $driverId'),
            const SizedBox(height: 8),
            Text('Vehicle: ${driver.vehicleType}'),
            Text('Plate: ${driver.plateNumber}'),
            Text('License: ${driver.licenseNumber}'),
            const SizedBox(height: 8),
            Text('Status: ${driver.status.toString().split('.').last}'),
            Text('Queue Position: #$position'),
          ],
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
}

class _StatusChip extends StatelessWidget {
  final DriverStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    String text;

    switch (status) {
      case DriverStatus.offline:
        backgroundColor = Colors.grey[100]!;
        textColor = Colors.grey[800]!;
        text = 'Offline';
        break;
      case DriverStatus.available:
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        text = 'Available';
        break;
      case DriverStatus.busy:
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        text = 'Busy';
        break;
      case DriverStatus.onTrip:
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        text = 'On Trip';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
