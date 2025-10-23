import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/firestore_service.dart';
import '../../services/fare_service.dart';
import '../../models/ride_model.dart';
import '../../models/driver_model.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _selectedDate = DateTime.now();
  String _selectedPeriod = 'Today';

  final List<String> _periods = ['Today', 'This Week', 'This Month', 'Custom'];

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Report controls
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.purple[50],
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.analytics, color: Colors.purple[600], size: 32),
                    const SizedBox(width: 12),
                    const Text(
                      'Reports & Analytics',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedPeriod,
                        decoration: const InputDecoration(
                          labelText: 'Period',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: _periods.map((period) {
                          return DropdownMenuItem(
                            value: period,
                            child: Text(period),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedPeriod = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (_selectedPeriod == 'Custom')
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          readOnly: true,
                          controller: TextEditingController(
                            text: DateFormat(
                              'MMM dd, yyyy',
                            ).format(_selectedDate),
                          ),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setState(() {
                                _selectedDate = date;
                              });
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Reports content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Overview stats
                  StreamBuilder<List<DriverModel>>(
                    stream: firestoreService.getAllDrivers(),
                    builder: (context, driverSnapshot) {
                      return StreamBuilder<List<RideModel>>(
                        stream: firestoreService.getAllActiveRides(),
                        builder: (context, rideSnapshot) {
                          final drivers = driverSnapshot.data ?? [];
                          final rides = rideSnapshot.data ?? [];

                          return _buildOverviewStats(drivers, rides);
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Daily stats (mock data for demonstration)
                  _buildDailyStats(),

                  const SizedBox(height: 24),

                  // Popular routes (mock data)
                  _buildPopularRoutes(),

                  const SizedBox(height: 24),

                  // Driver performance (mock data)
                  _buildDriverPerformance(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewStats(List<DriverModel> drivers, List<RideModel> rides) {
    final totalDrivers = drivers.length;
    final approvedDrivers = drivers.where((d) => d.isApproved).length;
    final onlineDrivers = drivers
        .where((d) => d.status == DriverStatus.available)
        .length;
    final activeRides = rides.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Total Drivers',
                value: totalDrivers.toString(),
                icon: Icons.people,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _StatCard(
                title: 'Approved',
                value: approvedDrivers.toString(),
                icon: Icons.verified,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                title: 'Online Now',
                value: onlineDrivers.toString(),
                icon: Icons.online_prediction,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _StatCard(
                title: 'Active Rides',
                value: activeRides.toString(),
                icon: Icons.local_taxi,
                color: Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyStats() {
    // Mock data for demonstration
    final dailyStats = [
      {'day': 'Mon', 'rides': 45, 'revenue': 2250.0},
      {'day': 'Tue', 'rides': 52, 'revenue': 2600.0},
      {'day': 'Wed', 'rides': 38, 'revenue': 1900.0},
      {'day': 'Thu', 'rides': 61, 'revenue': 3050.0},
      {'day': 'Fri', 'rides': 73, 'revenue': 3650.0},
      {'day': 'Sat', 'rides': 89, 'revenue': 4450.0},
      {'day': 'Sun', 'rides': 67, 'revenue': 3350.0},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Daily Statistics (This Week)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: dailyStats.map((stat) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          stat['day'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${stat['rides']} rides'),
                            Text(
                              FareService.formatFare(stat['revenue'] as double),
                              style: const TextStyle(
                                color: Color(0xFF000000),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 100,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (stat['rides'] as int) / 100,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue[600],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPopularRoutes() {
    // Mock data for demonstration
    final popularRoutes = [
      {
        'from': 'Sto. Cristo Terminal',
        'to': 'Tarlac City Proper',
        'count': 156,
      },
      {'from': 'Concepcion Plaza', 'to': 'SM City Tarlac', 'count': 134},
      {'from': 'Tarlac State University', 'to': 'Public Market', 'count': 98},
      {'from': 'Provincial Hospital', 'to': 'Bus Terminal', 'count': 87},
      {'from': 'City Hall', 'to': 'Metrotown Mall', 'count': 72},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Popular Routes',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: popularRoutes.asMap().entries.map((entry) {
                final index = entry.key;
                final route = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.blue[600],
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${route['from']} → ${route['to']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${route['count']} rides',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriverPerformance() {
    // Mock data for demonstration
    final topDrivers = [
      {'name': 'Juan Dela Cruz', 'rides': 89, 'rating': 4.8, 'revenue': 4450.0},
      {'name': 'Maria Santos', 'rides': 76, 'rating': 4.9, 'revenue': 3800.0},
      {'name': 'Pedro Garcia', 'rides': 68, 'rating': 4.7, 'revenue': 3400.0},
      {'name': 'Ana Reyes', 'rides': 62, 'rating': 4.6, 'revenue': 3100.0},
      {'name': 'Jose Mendoza', 'rides': 55, 'rating': 4.5, 'revenue': 2750.0},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Performing Drivers',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: topDrivers.asMap().entries.map((entry) {
                final index = entry.key;
                final driver = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: index == 0
                            ? Colors.amber
                            : index == 1
                            ? Colors.grey[400]
                            : index == 2
                            ? Colors.brown[300]
                            : Colors.blue[600],
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driver['name'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${driver['rides']} rides',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.star,
                                  size: 12,
                                  color: Colors.amber[600],
                                ),
                                Text(
                                  '${driver['rating']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        FareService.formatFare(driver['revenue'] as double),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF000000),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.black),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
