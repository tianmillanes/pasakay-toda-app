import 'package:flutter/material.dart';
import '../../models/lat_lng.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/location_helpers.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../models/pasabuy_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import 'map_picker_screen.dart';
import 'pasabuy_waiting_screen.dart';

class PasaBuyScreen extends StatefulWidget {
  const PasaBuyScreen({super.key});

  @override
  State<PasaBuyScreen> createState() => _PasaBuyScreenState();
}

class _PasaBuyScreenState extends State<PasaBuyScreen> {
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;
  LatLng? _currentLocation; // Passenger's current GPS location
  String _pickupAddress = '';
  String _dropoffAddress = '';
  String _itemDescription = '';
  String _budget = '';
  bool _sameLocation = false;
  bool _isSubmitting = false;
  bool _useCurrentLocation = true; // Toggle: true = current GPS, false = pickup location
  // final Set<Marker> _markers = {}; // No longer used for UI display

  final _itemController = TextEditingController();
  final _budgetController = TextEditingController();
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _itemController.dispose();
    _budgetController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final position = await locationService.getCurrentLocation();
      if (position != null && mounted) {
        final latLng = LatLng(position.latitude, position.longitude);
        final address = await locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        setState(() {
          // Store current location for routing
          _currentLocation = latLng;
          // Set pickup location to current location initially
          _pickupLocation = latLng;
          _pickupAddress = address;
          _pickupController.text = address;
        });
      }
    } on LocationServiceException catch (_) {
      if (mounted) {
        LocationHelpers.showLocationDisabledDialog(context);
      }
    } on LocationPermissionException catch (e) {
      if (mounted) {
        _showPermissionDeniedDialog(e.toString());
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Could not get current location: $e');
      }
    }
  }

  Future<void> _openMapPicker(bool isForPickup) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MapPickerScreen(
          isForPickup: isForPickup,
          initialLocation: (isForPickup ? _pickupLocation : _dropoffLocation) ?? _currentLocation,
        ),
      ),
    );
    if (result != null && mounted) {
      final address = result['address'] as String;
      final location = result['location'] as LatLng;
      setState(() {
        if (isForPickup) {
          _pickupController.text = address;
          _pickupAddress = address;
          _pickupLocation = location;
        } else {
          _dropoffController.text = address;
          _dropoffAddress = address;
          _dropoffLocation = location;
        }
      });
    }
  }

  Future<void> _submitPasaBuyRequest() async {
    // Validation
    if (_pickupLocation == null) {
      SnackbarHelper.showError(context, 'Please select a pickup location');
      return;
    }

    if (_itemDescription.trim().isEmpty) {
      SnackbarHelper.showError(context, 'Please describe items');
      return;
    }

    if (_budget.trim().isEmpty) {
      SnackbarHelper.showError(context, 'Please enter budget');
      return;
    }

    double? budgetAmount = double.tryParse(_budget);
    if (budgetAmount == null || budgetAmount <= 0) {
      SnackbarHelper.showError(context, 'Invalid budget');
      return;
    }

    LatLng finalDropoff = _sameLocation ? _pickupLocation! : _dropoffLocation!;
    if (!_sameLocation && _dropoffLocation == null) {
      SnackbarHelper.showError(context, 'Select delivery location');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );

      // Create PasaBuy request with queue-based driver assignment
      final result = await firestoreService.createPasaBuyWithDriverCheck(
        authService.currentUser!.uid,
        authService.currentUserModel?.name ?? 'Passenger',
        authService.currentUserModel?.phone ?? '',
        GeoPoint(_pickupLocation!.latitude, _pickupLocation!.longitude),
        _pickupAddress,
        GeoPoint(finalDropoff.latitude, finalDropoff.longitude),
        _sameLocation ? _pickupAddress : _dropoffAddress,
        _itemDescription,
        budgetAmount,
        authService.currentUserModel?.barangayId ?? '',
        authService.currentUserModel?.barangayName ?? '',
        _currentLocation != null 
            ? GeoPoint(_currentLocation!.latitude, _currentLocation!.longitude)
            : null,
        _useCurrentLocation, // true = use current GPS, false = use pickup location
      );

      if (mounted) {
        if (result['success'] == true) {
          final requestId = result['requestId'] as String?;
          
          SnackbarHelper.showSuccess(
            context,
            'PasaBuy request sent! Waiting driver to accept',
            seconds: 2,
          );

          if (mounted && requestId != null) {
            final pasabuyModel = PasaBuyModel(
              id: requestId,
              passengerId: authService.currentUser!.uid,
              passengerName: authService.currentUserModel?.name ?? 'Passenger',
              passengerPhone: authService.currentUserModel?.phone ?? '',
              pickupLocation: GeoPoint(_pickupLocation!.latitude, _pickupLocation!.longitude),
              pickupAddress: _pickupAddress,
              dropoffLocation: GeoPoint(finalDropoff.latitude, finalDropoff.longitude),
              dropoffAddress: _sameLocation ? _pickupAddress : _dropoffAddress,
              itemDescription: _itemDescription,
              budget: budgetAmount,
              status: PasaBuyStatus.pending,
              assignedDriverId: result['assignedDriverId'] as String?,
              driverId: null,
              driverName: null,
              createdAt: DateTime.now(),
              acceptedAt: null,
              completedAt: null,
              barangayId: authService.currentUserModel?.barangayId ?? '',
              barangayName: authService.currentUserModel?.barangayName ?? '',
              declinedBy: [],
              expiresAt: DateTime.now().add(const Duration(seconds: 30)),
            );

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => PasaBuyWaitingScreen(
                  requestId: requestId,
                  request: pasabuyModel,
                ),
              ),
            );
          }
        } else {
          SnackbarHelper.showError(
            context,
            result['error'] ?? 'Failed to create request',
            seconds: 4,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Error: $e',
          seconds: 4,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'PasaBuy Request',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModernLocationSection(),
              
              const SizedBox(height: 12),
              
              _buildModernOrderSection(),
              
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitPasaBuyRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
                    shape: const StadiumBorder(),
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Book Pasabuy',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernLocationSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.route_outlined,
                        size: 18,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Trip locations',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'STEP 1 OF 2',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: AppTheme.borderLight),
          _buildCompactLocationRow(
            label: 'Pickup Location',
            value: _pickupAddress,
            placeholder: 'Where to pick up?',
            icon: Icons.location_on_rounded,
            iconColor: Colors.orange,
            onTap: () => _openMapPicker(true),
            showLine: !_sameLocation,
          ),
          if (!_sameLocation)
            _buildCompactLocationRow(
              label: 'Delivery Location',
              value: _dropoffAddress,
              placeholder: 'Where to deliver?',
              icon: Icons.location_on_rounded,
              iconColor: AppTheme.primaryGreen,
              onTap: () => _openMapPicker(false),
              isLast: true,
            ),
          const Divider(height: 1, color: AppTheme.borderLight, indent: 56),
          _buildCompactToggle(),
        ],
      ),
    );
  }

  Widget _buildCompactLocationRow({
    required String label,
    required String value,
    required String placeholder,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    bool showLine = false,
    bool isLast = false,
  }) {
    final hasValue = value.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: isLast ? const BorderRadius.vertical(bottom: Radius.circular(16)) : (showLine ? null : const BorderRadius.vertical(top: Radius.circular(16))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              children: [
                Icon(icon, color: iconColor, size: 20),
                if (showLine)
                  Container(
                    width: 1.5,
                    height: 20,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.borderLight,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasValue ? value : placeholder,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hasValue ? AppTheme.textPrimary : AppTheme.textHint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactToggle() {
    return InkWell(
      onTap: () => setState(() => _sameLocation = !_sameLocation),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _sameLocation,
                onChanged: (val) => setState(() => _sameLocation = val ?? false),
                activeColor: AppTheme.primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                side: const BorderSide(color: AppTheme.borderLight, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Deliver to pickup location',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernOrderSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        size: 18,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Order details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'STEP 2 OF 2',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: AppTheme.borderLight),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ORDER DETAILS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _itemController,
                  maxLines: 2,
                  onChanged: (val) => _itemDescription = val,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'What do you need? (e.g., 2kg Rice, Milk...)',
                    hintStyle: const TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppTheme.backgroundLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ESTIMATED BUDGET',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _budgetController,
                  keyboardType: TextInputType.number,
                  onChanged: (val) => _budget = val,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryGreen,
                  ),
                  decoration: InputDecoration(
                    prefixText: '₱ ',
                    prefixStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryGreen,
                    ),
                    hintText: '0',
                    hintStyle: const TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 18,
                    ),
                    filled: true,
                    fillColor: AppTheme.backgroundLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.location_disabled, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            const Text('Location Permission Required'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // Open app settings
              await Geolocator.openAppSettings();
              // Try getting location again after settings are opened
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _getCurrentLocation();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D2D2D),
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
