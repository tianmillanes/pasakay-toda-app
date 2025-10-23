import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/fare_service.dart';
import '../../models/ride_model.dart';
import '../../utils/app_theme.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/animated_card.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  String _searchQuery = '';
  RideStatus? _statusFilter;
  DateTimeRange? _dateFilter;
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);

    if (authService.currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view ride history')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [AppTheme.getSoftShadow()],
            ),
            child: Column(
              children: [
                // Search Bar
                Semantics(
                  label: 'Search rides by destination or pickup location',
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search rides by destination...',
                      prefixIcon: Icon(Icons.search, color: AppTheme.primaryBlue),
                      suffixIcon: Semantics(
                        label: _showFilters ? 'Hide filters' : 'Show filters',
                        child: IconButton(
                          icon: Icon(
                            _showFilters ? Icons.filter_list : Icons.filter_list_outlined,
                            color: AppTheme.primaryBlue,
                          ),
                          onPressed: () {
                            setState(() {
                              _showFilters = !_showFilters;
                            });
                          },
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: AppTheme.getStandardBorderRadius(),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppTheme.getStandardBorderRadius(),
                        borderSide: BorderSide(color: AppTheme.primaryBlue),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
                
                // Filters Section
                if (_showFilters) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterChip(
                          label: 'Status',
                          value: _statusFilter?.toString().split('.').last ?? 'All',
                          onTap: () => _showStatusFilter(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FilterChip(
                          label: 'Date Range',
                          value: _dateFilter != null ? 'Custom' : 'All Time',
                          onTap: () => _showDateFilter(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _clearFilters,
                        icon: Icon(Icons.clear_all, color: AppTheme.errorColor),
                        tooltip: 'Clear Filters',
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          // Rides List
          Expanded(
            child: StreamBuilder<List<RideModel>>(
              stream: firestoreService.getUserRides(authService.currentUser!.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 3,
                    itemBuilder: (context, index) => const RideCardSkeleton(),
                  );
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
                            setState(() {});
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final allRides = snapshot.data ?? [];
                final filteredRides = _filterRides(allRides);

                if (filteredRides.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.history, size: 64, color: Color(0xFF757575)),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty || _statusFilter != null || _dateFilter != null
                              ? 'No rides match your filters'
                              : 'No rides yet',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty || _statusFilter != null || _dateFilter != null
                              ? 'Try adjusting your search or filters'
                              : 'Your ride history will appear here',
                          style: const TextStyle(color: Colors.black),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredRides.length,
                  itemBuilder: (context, index) {
                    final ride = filteredRides[index];
                    return SlideInCard(
                      index: index,
                      child: _RideHistoryCard(ride: ride),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<RideModel> _filterRides(List<RideModel> rides) {
    return rides.where((ride) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final matchesSearch = ride.dropoffAddress.toLowerCase().contains(_searchQuery) ||
            ride.pickupAddress.toLowerCase().contains(_searchQuery);
        if (!matchesSearch) return false;
      }

      // Status filter
      if (_statusFilter != null && ride.status != _statusFilter) {
        return false;
      }

      // Date filter
      if (_dateFilter != null) {
        final rideDate = ride.requestedAt;
        if (rideDate.isBefore(_dateFilter!.start) || rideDate.isAfter(_dateFilter!.end)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _showStatusFilter() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusFilterOption(
              status: null,
              label: 'All Statuses',
              isSelected: _statusFilter == null,
              onTap: () {
                setState(() {
                  _statusFilter = null;
                });
                Navigator.pop(context);
              },
            ),
            ...RideStatus.values.map((status) => _StatusFilterOption(
              status: status,
              label: status.toString().split('.').last,
              isSelected: _statusFilter == status,
              onTap: () {
                setState(() {
                  _statusFilter = status;
                });
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showDateFilter() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _dateFilter,
    );
    if (picked != null) {
      setState(() {
        _dateFilter = picked;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _statusFilter = null;
      _dateFilter = null;
    });
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.getStandardBorderRadius(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.primaryBlue),
          borderRadius: AppTheme.getStandardBorderRadius(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusFilterOption extends StatelessWidget {
  final RideStatus? status;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusFilterOption({
    required this.status,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      leading: Radio<RideStatus?>(
        value: status,
        groupValue: isSelected ? status : null,
        onChanged: (_) => onTap(),
        activeColor: AppTheme.primaryBlue,
      ),
      onTap: onTap,
    );
  }
}


class _RideHistoryCard extends StatelessWidget {
  final RideModel ride;

  const _RideHistoryCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.getStandardBorderRadius(),
        side: const BorderSide(
          color: Color(0xFFBDBDBD),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatusChip(status: ride.status),
                Text(
                  DateFormat('MMM dd, yyyy • hh:mm a').format(ride.requestedAt),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
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
                    ride.pickupAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black,
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
                    ride.dropoffAddress,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Fare and duration
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            
            // Additional details for completed rides
            if (ride.status == RideStatus.completed && ride.completedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Completed: ${DateFormat('MMM dd, yyyy • hh:mm a').format(ride.completedAt!)}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                ),
              ),
            ],
            
            // Notes if any
            if (ride.notes != null && ride.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Note: ${ride.notes}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
        backgroundColor = Colors.cyan[100]!;
        textColor = Colors.cyan[800]!;
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
