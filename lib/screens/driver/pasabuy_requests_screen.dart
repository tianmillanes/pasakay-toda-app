import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../models/pasabuy_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import 'pasabuy_detail_screen.dart';

class PasaBuyRequestsScreen extends StatefulWidget {
  const PasaBuyRequestsScreen({super.key});

  @override
  State<PasaBuyRequestsScreen> createState() => _PasaBuyRequestsScreenState();
}

class _PasaBuyRequestsScreenState extends State<PasaBuyRequestsScreen> {
  String _filterStatus = 'pending';

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUser;
    final barangayId = authService.currentUserModel?.barangayId;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (barangayId == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('PasaBuy Requests', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF1A1A1A))),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
        ),
        body: Center(child: Text('Barangay information not found', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('PasaBuy Requests', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF1A1A1A), letterSpacing: -0.5)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
            color: Colors.white,
            child: Row(
              children: [
                _FilterChip(label: 'Available', isSelected: _filterStatus == 'pending', onTap: () => setState(() => _filterStatus = 'pending')),
                const SizedBox(width: 12),
                _FilterChip(label: 'My Tasks', isSelected: _filterStatus == 'accepted', onTap: () => setState(() => _filterStatus = 'accepted')),
              ],
            ),
          ),
          Expanded(
            child: _filterStatus == 'pending'
                ? _PendingRequestsList(barangayId: barangayId)
                : _MyRequestsList(driverId: currentUser.uid),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isSelected ? Colors.orange : Colors.grey.shade100, width: 1.5),
        ),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isSelected ? Colors.white : Colors.grey.shade500)),
      ),
    );
  }
}

class _PendingRequestsList extends StatelessWidget {
  final String barangayId;
  const _PendingRequestsList({required this.barangayId});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    return StreamBuilder<List<PasaBuyModel>>(
      stream: firestoreService.getPendingPasaBuyRequestsForBarangay(barangayId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.orange));
        if (snapshot.hasError) return _ErrorView();
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) return _EmptyView(icon: Icons.inbox_rounded, title: 'No Requests', subtitle: 'Check back later for new tasks');
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          physics: const BouncingScrollPhysics(),
          itemCount: requests.length,
          itemBuilder: (context, index) => _PasaBuyRequestCard(
            request: requests[index],
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => PasaBuyDetailScreen(request: requests[index]))),
          ),
        );
      },
    );
  }
}

class _MyRequestsList extends StatelessWidget {
  final String driverId;
  const _MyRequestsList({required this.driverId});

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    return StreamBuilder<List<PasaBuyModel>>(
      stream: firestoreService.getDriverPasaBuyRequests(driverId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.orange));
        if (snapshot.hasError) return _ErrorView();
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) return _EmptyView(icon: Icons.shopping_bag_rounded, title: 'No Tasks', subtitle: "You haven't accepted any tasks yet");
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          physics: const BouncingScrollPhysics(),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final isActive = request.status != PasaBuyStatus.completed && 
                           request.status != PasaBuyStatus.cancelled;
            
            return _PasaBuyRequestCard(
              request: request,
              onTap: () {
                if (isActive) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PasaBuyActiveRideScreen(
                        requestId: request.id,
                        request: request,
                      ),
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PasaBuyDetailScreen(request: request),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}

// Add import for PasaBuyActiveRideScreen
import 'pasabuy_active_ride_screen.dart';

class _PasaBuyRequestCard extends StatelessWidget {
  final PasaBuyModel request;
  final VoidCallback onTap;
  const _PasaBuyRequestCard({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.grey.shade100, width: 2),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(color: _getStatusColor().withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, size: 16, color: _getStatusColor()),
                  const SizedBox(width: 8),
                  Text(_getStatusText().toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: _getStatusColor(), letterSpacing: 0.5)),
                  const Spacer(),
                  Text('₱${request.fare.toStringAsFixed(2)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _getStatusColor())),

                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.shopping_bag_rounded, size: 18, color: Colors.orange)),
                      const SizedBox(width: 16),
                      Expanded(child: Text(request.itemDescription, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _LocationItem(icon: Icons.trip_origin_rounded, address: request.pickupAddress, color: Colors.orange),
                  Container(margin: const EdgeInsets.only(left: 17), height: 16, width: 2, color: Colors.grey.shade100),
                  _LocationItem(icon: Icons.location_on_rounded, address: request.dropoffAddress, color: Colors.red),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (request.status) {
      case PasaBuyStatus.pending: return Colors.orange;
      case PasaBuyStatus.accepted:
      case PasaBuyStatus.driver_on_way:
      case PasaBuyStatus.arrived_pickup:
      case PasaBuyStatus.delivery_in_progress:
        return AppTheme.primaryGreen;
      case PasaBuyStatus.completed: return AppTheme.primaryGreen;
      case PasaBuyStatus.cancelled: return Colors.red;
    }
  }

  String _getStatusText() {
    switch (request.status) {
      case PasaBuyStatus.pending: return 'Available';
      case PasaBuyStatus.accepted:
      case PasaBuyStatus.driver_on_way:
      case PasaBuyStatus.arrived_pickup:
      case PasaBuyStatus.delivery_in_progress:
        return 'In Progress';
      case PasaBuyStatus.completed: return 'Completed';
      case PasaBuyStatus.cancelled: return 'Cancelled';
    }
  }
}

class _LocationItem extends StatelessWidget {
  final IconData icon;
  final String address;
  final Color color;
  const _LocationItem({required this.icon, required this.address, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(address, style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyView({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 100, color: Colors.grey.shade100),
          const SizedBox(height: 24),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 15, color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 64, color: Colors.red.shade100),
          const SizedBox(height: 16),
          Text('Something went wrong', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
