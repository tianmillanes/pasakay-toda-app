import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/driver_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import '../../widgets/modern_barangay_picker.dart';

enum UserStatus { all, active, deactivated }

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _StatusSelector extends StatelessWidget {
  final UserStatus currentStatus;
  final Function(UserStatus) onStatusChanged;

  const _StatusSelector({
    required this.currentStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.borderLight),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildOption(UserStatus.all, 'All'),
          _buildOption(UserStatus.active, 'Active'),
          _buildOption(UserStatus.deactivated, 'Inactive'),
        ],
      ),
    );
  }

  Widget _buildOption(UserStatus status, String label) {
    final isSelected = currentStatus == status;
    return Expanded(
      child: GestureDetector(
        onTap: () => onStatusChanged(status),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primaryGreen.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _UserManagementScreenState extends State<UserManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;
  String _selectedBarangayName = '';
  UserStatus _statusFilter = UserStatus.active;
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');
  List<String> _sortedBarangayNames = [];
  bool _isLoadingBarangays = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController = TextEditingController();
    _searchController.addListener(() {
      _searchNotifier.value = _searchController.text.toLowerCase();
    });
    _loadBarangayNames();
  }

  Future<void> _loadBarangayNames() async {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    try {
      final barangays = await firestoreService.getAllBarangays();
      final barangayNames = barangays.map((b) => b.name).toSet().toList();
      barangayNames.sort();
      if (mounted) {
        setState(() {
          _sortedBarangayNames = barangayNames;
          _isLoadingBarangays = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sortedBarangayNames = [];
          _isLoadingBarangays = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: AppTheme.backgroundWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primaryGreen,
          unselectedLabelColor: AppTheme.textHint,
          indicatorColor: AppTheme.primaryGreen,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          tabs: const [
            Tab(text: 'Drivers'),
            Tab(text: 'Passengers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDriversTab(firestoreService, authService),
          _buildPassengersTab(firestoreService, authService),
        ],
      ),
    );
  }

  Widget _buildDriversTab(FirestoreService firestoreService, AuthService authService) {
    return StreamBuilder<Map<String, List<DriverModel>>>(
      stream: firestoreService.getAllDriversByBarangay(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }

        final driversByBarangay = snapshot.data ?? {};
        
        return Column(
          children: [
            _buildSearchAndFilters(isPassengerTab: false),
            Expanded(
              child: _buildDriversList(driversByBarangay, _sortedBarangayNames, firestoreService, authService),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchAndFilters({required bool isPassengerTab}) {
    return Container(
      color: AppTheme.backgroundWhite,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: isPassengerTab ? 'Search by name...' : 'Search by name or plate...',
              prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGreen),
              filled: true,
              fillColor: AppTheme.backgroundLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isPassengerTab) ...[
                Expanded(
                  flex: 3,
                  child: ModernBarangayPicker(
                    barangayNames: ['All Barangays', ..._sortedBarangayNames],
                    selectedBarangay: _selectedBarangayName,
                    onBarangaySelected: (v) {
                      setState(() => _selectedBarangayName = (v == 'All Barangays') ? '' : v);
                    },
                    isLoading: _isLoadingBarangays,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: isPassengerTab ? 1 : 2,
                child: _StatusSelector(
                  currentStatus: _statusFilter,
                  onStatusChanged: (status) {
                    setState(() => _statusFilter = status);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriversList(
    Map<String, List<DriverModel>> driversByBarangay,
    List<String> sortedBarangayNames,
    FirestoreService firestoreService,
    AuthService authService,
  ) {
    return ValueListenableBuilder<String>(
      valueListenable: _searchNotifier,
      builder: (context, searchText, child) {
        final allDrivers = driversByBarangay.values.expand((list) => list).toList();
        
        final filteredDrivers = allDrivers.where((d) {
          final matchesBarangay = _selectedBarangayName.isEmpty || d.barangayName == _selectedBarangayName;
          final matchesStatus = _statusFilter == UserStatus.all || 
              (_statusFilter == UserStatus.active && d.isActive) ||
              (_statusFilter == UserStatus.deactivated && !d.isActive);
          final name = d.name.toLowerCase();
          final tricyclePlate = d.tricyclePlateNumber?.toLowerCase() ?? '';
          final plate = d.plateNumber.toLowerCase();
          
          final matchesSearch = searchText.isEmpty || 
              name.contains(searchText) || 
              tricyclePlate.contains(searchText) ||
              plate.contains(searchText);
          return matchesBarangay && matchesStatus && matchesSearch;
        }).toList();

        if (filteredDrivers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_off_rounded, size: 80, color: AppTheme.textHint.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text('No drivers found', style: TextStyle(color: AppTheme.textHint, fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: filteredDrivers.length,
          itemBuilder: (context, index) {
            final driver = filteredDrivers[index];
            return _buildUserCard(
              title: driver.name,
              subtitle: 'Plate: ${driver.tricyclePlateNumber ?? driver.plateNumber}',
              label: driver.barangayName,
              isActive: driver.isActive,
              isApproved: driver.isApproved,
              onAction: () => _showUserActions(driver, firestoreService, authService),
            );
          },
        );
      },
    );
  }

  Widget _buildPassengersTab(FirestoreService firestoreService, AuthService authService) {
    return StreamBuilder<Map<String, List<Map<String, dynamic>>>>(
      stream: firestoreService.getAllPassengersByBarangay(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }

        final passengersByBarangay = snapshot.data ?? {};
        
        return Column(
          children: [
            _buildSearchAndFilters(isPassengerTab: true),
            Expanded(
              child: _buildPassengersList(passengersByBarangay, firestoreService, authService),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPassengersList(
    Map<String, List<Map<String, dynamic>>> passengersByBarangay,
    FirestoreService firestoreService,
    AuthService authService,
  ) {
    return ValueListenableBuilder<String>(
      valueListenable: _searchNotifier,
      builder: (context, searchText, child) {
        final allPassengers = passengersByBarangay.values.expand((list) => list).toList();
        
        final filteredPassengers = allPassengers.where((p) {
          final isActive = p['isActive'] ?? true;
          final matchesStatus = _statusFilter == UserStatus.all || 
              (_statusFilter == UserStatus.active && isActive) ||
              (_statusFilter == UserStatus.deactivated && !isActive);
          final name = (p['name'] ?? '').toString().toLowerCase();
          final matchesSearch = searchText.isEmpty || name.contains(searchText);
          return matchesStatus && matchesSearch;
        }).toList();

        if (filteredPassengers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_off_rounded, size: 80, color: AppTheme.textHint.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text('No passengers found', style: TextStyle(color: AppTheme.textHint, fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: filteredPassengers.length,
          itemBuilder: (context, index) {
            final p = filteredPassengers[index];
            final isActive = p['isActive'] ?? true;
            return _buildUserCard(
              title: p['name'] ?? 'Unknown',
              subtitle: p['email'] ?? 'No email',
              label: 'Passenger',
              isActive: isActive,
              isApproved: true,
              onAction: () => _showPassengerActions(p, firestoreService, authService),
            );
          },
        );
      },
    );
  }

  Widget _buildUserCard({
    required String title,
    required String subtitle,
    required String label,
    required bool isActive,
    required bool isApproved,
    required VoidCallback onAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppTheme.primaryGreen.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.person_rounded, color: AppTheme.primaryGreen, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.textPrimary)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildBadge(label, AppTheme.primaryGreen),
                  const SizedBox(width: 8),
                  _buildBadge(isActive ? 'Active' : 'Deactivated', isActive ? AppTheme.successGreen : AppTheme.errorRed),
                  if (!isApproved) ...[
                    const SizedBox(width: 8),
                    _buildBadge('Pending Verification', AppTheme.warningOrange),
                  ],
                ],
              ),
            ),
          ],
        ),
        trailing: Container(
          decoration: BoxDecoration(color: AppTheme.backgroundLight, borderRadius: BorderRadius.circular(12)),
          child: IconButton(
            icon: const Icon(Icons.more_horiz_rounded, color: AppTheme.textPrimary),
            onPressed: onAction,
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.2)),
    );
  }

  void _showUserActions(DriverModel driver, FirestoreService firestoreService, AuthService authService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.borderLight, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 25),
            Text(driver.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            _buildActionButton(
              icon: driver.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
              title: driver.isActive ? 'Deactivate Driver Account' : 'Reactivate Driver Account',
              color: driver.isActive ? AppTheme.errorRed : AppTheme.successGreen,
              onTap: () async {
                final currentUser = authService.currentUser;
                if (currentUser == null) {
                  SnackbarHelper.showError(context, 'You must be logged in to perform this action');
                  return;
                }
                Navigator.pop(context);
                try {
                  if (driver.isActive) {
                    await firestoreService.deactivateUser(driver.id, currentUser.uid);
                  } else {
                    await firestoreService.activateUser(driver.id, currentUser.uid);
                  }
                  SnackbarHelper.showSuccess(context, 'Account status updated');
                } catch (e) {
                  SnackbarHelper.showError(context, e.toString());
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPassengerActions(Map<String, dynamic> p, FirestoreService firestoreService, AuthService authService) {
    final isActive = p['isActive'] ?? true;
    final uid = p['uid'] ?? p['id'] ?? '';
    final name = p['name']?.toString() ?? 'Passenger';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.borderLight, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 25),
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            _buildActionButton(
              icon: isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
              title: isActive ? 'Deactivate Passenger Account' : 'Reactivate Passenger Account',
              color: isActive ? AppTheme.errorRed : AppTheme.successGreen,
              onTap: () async {
                if (uid.toString().isEmpty) {
                  SnackbarHelper.showError(context, 'Invalid user ID');
                  return;
                }
                final currentUser = authService.currentUser;
                if (currentUser == null) {
                  SnackbarHelper.showError(context, 'You must be logged in to perform this action');
                  return;
                }
                Navigator.pop(context);
                try {
                  if (isActive) {
                    await firestoreService.deactivateUser(uid.toString(), currentUser.uid);
                  } else {
                    await firestoreService.activateUser(uid.toString(), currentUser.uid);
                  }
                  SnackbarHelper.showSuccess(context, 'Account status updated');
                } catch (e) {
                  SnackbarHelper.showError(context, e.toString());
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 15),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}
