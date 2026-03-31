import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/driver_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';

import '../../widgets/full_screen_image_viewer.dart';

class DriverApprovalScreen extends StatefulWidget {
  const DriverApprovalScreen({super.key});

  @override
  State<DriverApprovalScreen> createState() => _DriverApprovalScreenState();
}

class _DriverApprovalScreenState extends State<DriverApprovalScreen> {
  String _filterStatus = 'pending'; // pending, approved
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Driver Approvals'),
        backgroundColor: AppTheme.backgroundWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
      ),
      body: Column(
        children: [
          _buildHeaderAndSearch(),
          _buildFilterTabs(),
          Expanded(
            child: _buildDriversList(firestoreService, authService),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAndSearch() {
    return Container(
      color: AppTheme.backgroundWhite,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search applications...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGreen),
          filled: true,
          fillColor: AppTheme.backgroundLight,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _StatusTab(
            label: 'Pending',
            icon: Icons.timer_outlined,
            isSelected: _filterStatus == 'pending',
            color: AppTheme.warningOrange,
            onTap: () => setState(() => _filterStatus = 'pending'),
          ),
          const SizedBox(width: 15),
          _StatusTab(
            label: 'Approved',
            icon: Icons.check_circle_outline,
            isSelected: _filterStatus == 'approved',
            color: AppTheme.primaryGreen,
            onTap: () => setState(() => _filterStatus = 'approved'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriversList(FirestoreService firestoreService, AuthService authService) {
    return StreamBuilder<List<DriverModel>>(
      stream: firestoreService.getAllDrivers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }

        final drivers = snapshot.data ?? [];
        final filteredData = drivers.where((d) {
          final matchesStatus = _filterStatus == 'pending' ? !d.isApproved : d.isApproved;
          final matchesSearch = _searchQuery.isEmpty || 
              d.name.toLowerCase().contains(_searchQuery) || 
              (d.tricyclePlateNumber?.toLowerCase().contains(_searchQuery) ?? false);
          return matchesStatus && matchesSearch;
        }).toList();

        if (filteredData.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_turned_in_outlined, size: 80, color: AppTheme.textHint.withOpacity(0.2)),
                const SizedBox(height: 16),
                Text('No applications found', style: TextStyle(color: AppTheme.textHint, fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: filteredData.length,
          itemBuilder: (context, index) => _ApprovalCard(
            driver: filteredData[index],
            onTap: () => _showDetails(filteredData[index], firestoreService, authService),
          ),
        );
      },
    );
  }

  void _showDetails(DriverModel driver, FirestoreService firestoreService, AuthService authService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DriverDetailSheet(driver: driver, firestoreService: firestoreService, authService: authService),
    );
  }
}

class _StatusTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _StatusTab({required this.label, required this.icon, required this.isSelected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : AppTheme.backgroundWhite,
          borderRadius: BorderRadius.circular(15),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))] : [],
          border: isSelected ? null : Border.all(color: AppTheme.borderLight),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : AppTheme.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final DriverModel driver;
  final VoidCallback onTap;

  const _ApprovalCard({required this.driver, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreenLight,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.person_outline, color: AppTheme.primaryGreen, size: 30),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Tricycle Plate: ${driver.tricyclePlateNumber ?? driver.plateNumber}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.backgroundLight, borderRadius: BorderRadius.circular(8)),
                      child: Text(driver.barangayName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverDetailSheet extends StatelessWidget {
  final DriverModel driver;
  final FirestoreService firestoreService;
  final AuthService authService;

  const _DriverDetailSheet({required this.driver, required this.firestoreService, required this.authService});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
      padding: const EdgeInsets.fromLTRB(25, 12, 25, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: AppTheme.borderLight, borderRadius: BorderRadius.circular(10)))),
          const SizedBox(height: 30),
          const Text('Verification Details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 25),
          _buildInfoRow(Icons.person_outline, 'Full Name', driver.name),
          _buildInfoRow(Icons.pin_outlined, 'Plate Number', driver.tricyclePlateNumber ?? driver.plateNumber),
          _buildInfoRow(Icons.badge_outlined, 'Driver License', driver.driverLicenseNumber ?? 'Not provided'),
          _buildInfoRow(Icons.location_on_outlined, 'Area', driver.barangayName),
          const SizedBox(height: 30),
          const Text('Submitted Documents', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 15),
          Row(
            children: [
              _DocumentThumb(label: 'License', imageUrl: driver.licenseNumberImageUrl),
              const SizedBox(width: 15),
              _DocumentThumb(label: 'Plate', imageUrl: driver.plateNumberImageUrl),
            ],
          ),
          const SizedBox(height: 40),
          if (!driver.isApproved)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleRejection(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.errorRed,
                      side: const BorderSide(color: AppTheme.errorRed),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('Reject Application', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleApproval(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('Approve Driver', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppTheme.backgroundLight, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppTheme.primaryGreen, size: 20),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleApproval(BuildContext context) async {
    try {
      await firestoreService.approveDriver(driver.id, authService.currentUser!.uid);
      Navigator.pop(context);
      SnackbarHelper.showSuccess(context, 'Driver application approved successfully');
    } catch (e) {
      SnackbarHelper.showError(context, e.toString());
    }
  }

  Future<void> _handleRejection(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Rejection'),
        content: const Text('Are you sure you want to reject this driver application?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject', style: TextStyle(color: AppTheme.errorRed))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await firestoreService.rejectDriver(driver.id, authService.currentUser!.uid);
        Navigator.pop(context);
        SnackbarHelper.showSuccess(context, 'Driver application rejected');
      } catch (e) {
        SnackbarHelper.showError(context, e.toString());
      }
    }
  }
}

class _DocumentThumb extends StatelessWidget {
  final String label;
  final String? imageUrl;

  const _DocumentThumb({required this.label, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.startsWith('data:image');
    final heroTag = 'doc_${label}_${imageUrl?.hashCode}';

    return Expanded(
      child: GestureDetector(
        onTap: hasImage
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FullScreenImageViewer(
                      imageUrl: imageUrl!,
                      tag: heroTag,
                    ),
                  ),
                )
            : null,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.backgroundLight,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: hasImage
              ? Hero(
                  tag: heroTag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.memory(base64Decode(imageUrl!.split(',').last), fit: BoxFit.cover),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.image_not_supported_outlined, color: AppTheme.textHint),
                    const SizedBox(height: 8),
                    Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
      ),
    );
  }
}
