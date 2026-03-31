import 'package:flutter/material.dart';

class DriverAvailabilityCard extends StatelessWidget {
  final List<Map<String, dynamic>> onlineDrivers;
  final VoidCallback onRefresh;

  const DriverAvailabilityCard({
    required this.onlineDrivers,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final bool driversAvailable = onlineDrivers.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            driversAvailable ? Icons.check_circle_outline : Icons.error_outline,
            color: driversAvailable ? Colors.green : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driversAvailable
                      ? '${onlineDrivers.length} ${onlineDrivers.length == 1 ? "Driver" : "Drivers"} Online'
                      : 'No Drivers Available',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  driversAvailable ? 'Ready to serve you' : 'Please try again later',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}
