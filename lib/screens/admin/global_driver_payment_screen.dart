import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/driver_model.dart';
import '../../models/barangay_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import '../../widgets/modern_barangay_picker.dart';

import '../../widgets/full_screen_image_viewer.dart';

class DriverPaymentScreen extends StatefulWidget {
  const DriverPaymentScreen({super.key});

  @override
  State<DriverPaymentScreen> createState() => _DriverPaymentScreenState();
}

class _DriverPaymentScreenState extends State<DriverPaymentScreen> {
  late FirestoreService _firestoreService;
  late AuthService _authService;
  String _selectedBarangayId = 'all';
  String _filterStatus = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedDriverIds = {};
  List<BarangayModel> _barangays = [];
  bool _isLoadingBarangays = true;
  bool _isProcessing = false;
  List<DriverModel> _currentFilteredDrivers = [];

  @override
  void initState() {
    super.initState();
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _authService = Provider.of<AuthService>(context, listen: false);
    _loadBarangays();
  }

  Future<void> _loadBarangays() async {
    try {
      final barangays = await _firestoreService.getAllBarangays();
      if (mounted) {
        setState(() {
          _barangays = barangays;
          _isLoadingBarangays = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBarangays = false;
        });
        SnackbarHelper.showError(context, 'Failed to load barangays: $e');
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelectionMode = _selectedDriverIds.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: isSelectionMode ? _buildSelectionAppBar() : _buildStandardAppBar(),
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              _buildQuickFilters(),
              Expanded(
                child: _buildDriversList(),
              ),
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.primaryGreen,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: isSelectionMode ? _buildBottomActionBar() : null,
    );
  }

  AppBar _buildStandardAppBar() {
    return AppBar(
      title: const Text('Driver Payments'),
      backgroundColor: AppTheme.backgroundWhite,
      centerTitle: false,
      elevation: 0,
      automaticallyImplyLeading: false,
      actions: [
        _buildActionMenu(),
        const SizedBox(width: 8),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: AppTheme.primaryGreen,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        onPressed: () => setState(() => _selectedDriverIds.clear()),
      ),
      title: Text(
        '${_selectedDriverIds.length} Selected',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      actions: [
        TextButton.icon(
          onPressed: _selectAllFiltered,
          icon: const Icon(Icons.select_all, color: Colors.white),
          label: const Text('Select All', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _handleBulkPayment,
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Mark Paid', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successGreen,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _handleBulkUnpayment,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Mark Unpaid', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorRed,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppTheme.backgroundWhite,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGreen, size: 18),
                      filled: true,
                      fillColor: AppTheme.backgroundLight,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 40,
                  child: _buildBarangayPicker(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarangayPicker() {
    String selectedName = 'All Barangays';
    if (_selectedBarangayId != 'all') {
      final found = _barangays.where((b) => b.id == _selectedBarangayId);
      if (found.isNotEmpty) {
        selectedName = found.first.name;
      }
    }

    return ModernBarangayPicker(
      barangayNames: ['All Barangays', ..._barangays.map((b) => b.name).toList()],
      selectedBarangay: selectedName,
      onBarangaySelected: (name) {
        setState(() {
          if (name == 'All Barangays') {
            _selectedBarangayId = 'all';
          } else {
            _selectedBarangayId = _barangays.firstWhere((b) => b.name == name).id;
          }
        });
      },
      isLoading: _isLoadingBarangays,
    );
  }

  Widget _buildQuickFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(label: 'All Drivers', isSelected: _filterStatus == 'all', onTap: () => setState(() => _filterStatus = 'all')),
          const SizedBox(width: 8),
          _FilterChip(label: 'Paid', isSelected: _filterStatus == 'paid', color: AppTheme.successGreen, onTap: () => setState(() => _filterStatus = 'paid')),
          const SizedBox(width: 8),
          _FilterChip(label: 'Unpaid', isSelected: _filterStatus == 'unpaid', color: AppTheme.errorRed, onTap: () => setState(() => _filterStatus = 'unpaid')),
        ],
      ),
    );
  }

  void _selectAllFiltered() {
    setState(() {
      _selectedDriverIds.addAll(_currentFilteredDrivers.map((d) => d.id));
    });
  }

  void _toggleSelection(String driverId) {
    setState(() {
      if (_selectedDriverIds.contains(driverId)) {
        _selectedDriverIds.remove(driverId);
      } else {
        _selectedDriverIds.add(driverId);
      }
    });
  }

  Widget _buildDriversList() {
    return StreamBuilder<Map<String, List<DriverModel>>>(
      stream: _firestoreService.getAllDriversByBarangay(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 48),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}', style: const TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
          );
        }
        
        final driversMap = snapshot.data ?? {};
        final allDrivers = driversMap.values.expand((element) => element).toList();
        
        final filteredData = allDrivers.where((d) {
          final matchesBarangay = _selectedBarangayId == 'all' || d.barangayId == _selectedBarangayId;
          final matchesStatus = _filterStatus == 'all' || (_filterStatus == 'paid' ? d.isPaid : !d.isPaid);
          final matchesSearch = _searchQuery.isEmpty || 
              d.name.toLowerCase().contains(_searchQuery) || 
              (d.tricyclePlateNumber?.toLowerCase().contains(_searchQuery) ?? false) ||
              d.plateNumber.toLowerCase().contains(_searchQuery);
          return matchesBarangay && matchesStatus && matchesSearch;
        }).toList();

        _currentFilteredDrivers = filteredData;

        if (filteredData.isEmpty) {
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: filteredData.length,
          itemBuilder: (context, index) {
            final driver = filteredData[index];
            final isSelected = _selectedDriverIds.contains(driver.id);
            final isSelectionMode = _selectedDriverIds.isNotEmpty;
            
            return _PaymentDriverCard(
              driver: driver,
              isSelected: isSelected,
              onLongPress: () => _toggleSelection(driver.id),
              onTap: () => isSelectionMode ? _toggleSelection(driver.id) : _showSingleDriverActions(driver),
            );
          },
        );
      },
    );
  }

  Widget _buildActionMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) {
        if (v == 'notify_all') _sendMembershipNoticeToAll();
        if (v == 'clear_notices') _clearAllNotices();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'notify_all', child: Text('Send Expiration Notices')),
        const PopupMenuItem(value: 'clear_notices', child: Text('Clear All Notices', style: TextStyle(color: AppTheme.errorRed))),
      ],
    );
  }

  Future<void> _handleBulkPayment() async {
    try {
      setState(() => _isProcessing = true);
      final adminId = _authService.currentUser!.uid;
      await _firestoreService.markDriversAsPaidBulk(_selectedDriverIds.toList(), adminId);
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _selectedDriverIds.clear();
      });
      SnackbarHelper.showSuccess(context, 'Selected drivers marked as paid');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      SnackbarHelper.showError(context, e.toString());
    }
  }

  Future<void> _handleBulkUnpayment() async {
    try {
      setState(() => _isProcessing = true);
      final adminId = _authService.currentUser!.uid;
      await _firestoreService.markDriversAsUnpaidBulk(_selectedDriverIds.toList(), adminId);
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _selectedDriverIds.clear();
      });
      SnackbarHelper.showSuccess(context, 'Selected drivers marked as unpaid');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      SnackbarHelper.showError(context, e.toString());
    }
  }

  void _showSingleDriverActions(DriverModel driver) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(driver.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 20),
            _ActionButton(
              icon: driver.isPaid ? Icons.cancel_outlined : Icons.check_circle_outline,
              label: driver.isPaid ? 'Mark as Unpaid' : 'Mark as Paid',
              color: driver.isPaid ? AppTheme.errorRed : AppTheme.successGreen,
              onTap: () async {
                Navigator.pop(context);
                setState(() => _isProcessing = true);
                try {
                  final adminId = _authService.currentUser!.uid;
                  if (driver.isPaid) await _firestoreService.markDriverAsUnpaid(driver.id, adminId);
                  else await _firestoreService.markDriverAsPaid(driver.id, adminId);
                  if (!mounted) return;
                  setState(() => _isProcessing = false);
                  SnackbarHelper.showSuccess(context, 'Driver status updated');
                } catch (e) {
                  if (!mounted) return;
                  setState(() => _isProcessing = false);
                  SnackbarHelper.showError(context, e.toString());
                }
              },
            ),
            if (driver.paymentProofImageBase64 != null) ...[
              const SizedBox(height: 12),
              _ActionButton(
                icon: Icons.receipt_long_outlined,
                label: 'View Proof of Payment',
                color: AppTheme.infoBlue,
                onTap: () {
                  Navigator.pop(context);
                  final heroTag = 'payment_proof_${driver.id}';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullScreenImageViewer(
                        imageUrl: driver.paymentProofImageBase64!,
                        tag: heroTag,
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            _ActionButton(
              icon: Icons.notifications_active_outlined,
              label: 'Send Individual Notice',
              color: AppTheme.warningOrange,
              onTap: () async {
                Navigator.pop(context);
                
                setState(() => _isProcessing = true);

                try {
                  await _firestoreService.sendMembershipExpirationNoticeToDriver(
                    driver.id,
                  );
                  
                  if (!mounted) return;
                  setState(() => _isProcessing = false);

                  // Show success dialog
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      title: const Row(
                        children: [
                          Icon(Icons.check_circle, color: AppTheme.successGreen),
                          SizedBox(width: 10),
                          Text('Success'),
                        ],
                      ),
                      content: Text('Notice sent to ${driver.name} successfully.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK', style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  setState(() => _isProcessing = false);
                  SnackbarHelper.showError(context, e.toString());
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMembershipNoticeToAll() async {
    try {
      setState(() => _isProcessing = true);
      await _firestoreService.sendMembershipExpirationNoticeToAllBarangays();
      if (!mounted) return;
      setState(() => _isProcessing = false);
      SnackbarHelper.showSuccess(context, 'Expiration notices sent to all drivers');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      SnackbarHelper.showError(context, e.toString());
    }
  }

  Future<void> _clearAllNotices() async {
    try {
      setState(() => _isProcessing = true);
      final adminId = _authService.currentUser!.uid;
      await _firestoreService.clearAllMembershipNotices(adminId);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      SnackbarHelper.showSuccess(context, 'All membership notices cleared');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      SnackbarHelper.showError(context, e.toString());
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.isSelected, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppTheme.primaryGreen;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : AppTheme.backgroundWhite,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? null : Border.all(color: AppTheme.borderLight),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textSecondary, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

class _PaymentDriverCard extends StatelessWidget {
  final DriverModel driver;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PaymentDriverCard({required this.driver, required this.isSelected, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected ? const BorderSide(color: AppTheme.primaryGreen, width: 2) : BorderSide.none,
      ),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(radius: 20, backgroundColor: AppTheme.backgroundLight, child: const Icon(Icons.person_outline, color: AppTheme.primaryGreen, size: 20)),
                  if (isSelected) const Positioned(right: 0, bottom: 0, child: Icon(Icons.check_circle, color: AppTheme.primaryGreen, size: 14)),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(driver.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis)),
                         _CompactBadge(label: driver.isPaid ? 'PAID' : 'UNPAID', color: driver.isPaid ? AppTheme.successGreen : AppTheme.errorRed),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('${driver.tricyclePlateNumber ?? driver.plateNumber}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                         if (!driver.isPaid && driver.paymentProofImageBase64 != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.receipt_long, size: 14, color: AppTheme.infoBlue),
                          const SizedBox(width: 2),
                          const Text('Proof', style: TextStyle(fontSize: 11, color: AppTheme.infoBlue, fontWeight: FontWeight.w500)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CompactBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 15),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}
