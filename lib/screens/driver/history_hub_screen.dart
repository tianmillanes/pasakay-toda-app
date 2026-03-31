import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'trip_history_screen.dart';
import 'pasabuy_history_screen.dart';

class DriverHistoryHubScreen extends StatefulWidget {
  const DriverHistoryHubScreen({super.key});

  @override
  State<DriverHistoryHubScreen> createState() => _DriverHistoryHubScreenState();
}

class _DriverHistoryHubScreenState extends State<DriverHistoryHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'History',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryGreen,
          unselectedLabelColor: Colors.grey.shade400,
          indicatorColor: AppTheme.primaryGreen,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [
            Tab(text: 'Trips'),
            Tab(text: 'PasaBuy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          TripHistoryScreen(),
          DriverPasaBuyHistoryScreen(),
        ],
      ),
    );
  }
}
