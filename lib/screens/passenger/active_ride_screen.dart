import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../models/ride_model.dart';
import '../../widgets/usability_helpers.dart';

class ActiveRideScreen extends StatefulWidget {
  final RideModel ride;

  const ActiveRideScreen({super.key, required this.ride});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  bool _isMapMinimized = false;

  @override
  void initState() {
    super.initState();
    _setupMarkers();
  }

  void _setupMarkers() {
    _markers.addAll([
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(
          widget.ride.pickupLocation.latitude,
          widget.ride.pickupLocation.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(
          widget.ride.dropoffLocation.latitude,
          widget.ride.dropoffLocation.longitude,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    ]);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _fitMapBounds();
  }

  void _fitMapBounds() {
    if (_mapController == null) return;

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        [
          widget.ride.pickupLocation.latitude,
          widget.ride.dropoffLocation.latitude,
        ].reduce((a, b) => a < b ? a : b),
        [
          widget.ride.pickupLocation.longitude,
          widget.ride.dropoffLocation.longitude,
        ].reduce((a, b) => a < b ? a : b),
      ),
      northeast: LatLng(
        [
          widget.ride.pickupLocation.latitude,
          widget.ride.dropoffLocation.latitude,
        ].reduce((a, b) => a > b ? a : b),
        [
          widget.ride.pickupLocation.longitude,
          widget.ride.dropoffLocation.longitude,
        ].reduce((a, b) => a > b ? a : b),
      ),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  String _getStatusText(RideStatus status) {
    switch (status) {
      case RideStatus.pending:
        return 'Finding Driver';
      case RideStatus.accepted:
        return 'Driver Accepted';
      case RideStatus.driverOnWay:
        return 'Driver On The Way';
      case RideStatus.driverArrived:
        return 'Driver Arrived';
      case RideStatus.inProgress:
        return 'Trip In Progress';
      case RideStatus.completed:
        return 'Trip Completed';
      case RideStatus.cancelled:
        return 'Ride Cancelled';
      case RideStatus.failed:
        return 'No Drivers Available';
    }
  }

  Color _getStatusColor(RideStatus status) {
    switch (status) {
      case RideStatus.pending:
        return const Color(0xFFFF9800);
      case RideStatus.accepted:
      case RideStatus.driverOnWay:
        return const Color(0xFF2196F3);
      case RideStatus.driverArrived:
        return const Color(0xFF9C27B0);
      case RideStatus.inProgress:
        return const Color(0xFF00BCD4);
      case RideStatus.completed:
        return const Color(0xFF4CAF50);
      case RideStatus.cancelled:
      case RideStatus.failed:
        return const Color(0xFFFF5252);
    }
  }

  IconData _getStatusIcon(RideStatus status) {
    switch (status) {
      case RideStatus.pending:
        return Icons.hourglass_empty;
      case RideStatus.accepted:
        return Icons.check_circle;
      case RideStatus.driverOnWay:
        return Icons.local_shipping;
      case RideStatus.driverArrived:
        return Icons.location_on;
      case RideStatus.inProgress:
        return Icons.directions_car;
      case RideStatus.completed:
        return Icons.check_circle_outline;
      case RideStatus.cancelled:
      case RideStatus.failed:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _showBackConfirmationDialog(context);
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'Active Ride',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2D2D2D),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _showBackConfirmationDialog(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.home_outlined),
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed('/passenger'),
            ),
          ],
        ),
        body: StreamBuilder<RideModel?>(
          stream: Provider.of<FirestoreService>(
            context,
          ).getRideStream(widget.ride.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ProgressIndicatorWithMessage(
                message: 'Loading ride details...',
                subtitle: 'Please wait while we fetch your ride information',
              );
            }

            final ride = snapshot.data ?? widget.ride;

            // Auto-navigate when ride ends
            if (ride.status == RideStatus.completed ||
                ride.status == RideStatus.cancelled ||
                ride.status == RideStatus.failed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop();
              });
            }

            return Column(
              children: [
                // Status Banner
                _buildStatusBanner(ride.status),

                // Map Section
                _buildMapSection(ride),

                // Ride Details Section
                Expanded(child: _buildRideDetailsSection(ride)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusBanner(RideStatus status) {
    return Semantics(
      label: '${_getStatusText(status)}. ${_getStatusSubtext(status)}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: _getStatusColor(status).withValues(alpha: 0.1),
          border: Border(
            bottom: BorderSide(
              color: _getStatusColor(status).withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _getStatusColor(status),
                shape: BoxShape.circle,
              ),
              child: Icon(_getStatusIcon(status), color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getStatusText(status),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(status),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getStatusSubtext(status),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF757575),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusSubtext(RideStatus status) {
    switch (status) {
      case RideStatus.pending:
        return 'Searching for nearby drivers...';
      case RideStatus.accepted:
        return 'Driver is preparing to pick you up';
      case RideStatus.driverOnWay:
        return 'Driver is heading to your location';
      case RideStatus.driverArrived:
        return 'Driver is waiting at pickup location';
      case RideStatus.inProgress:
        return 'Enjoy your ride!';
      case RideStatus.completed:
        return 'Thank you for riding with us';
      case RideStatus.cancelled:
        return 'This ride has been cancelled';
      case RideStatus.failed:
        return 'Please try booking again';
    }
  }

  Widget _buildMapSection(RideModel ride) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isMapMinimized ? 120 : 250,
      child: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            markers: _markers,
            initialCameraPosition: CameraPosition(
              target: LatLng(
                ride.pickupLocation.latitude,
                ride.pickupLocation.longitude,
              ),
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),
          // Map toggle button
          Positioned(
            top: 12,
            right: 12,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              elevation: 2,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isMapMinimized = !_isMapMinimized;
                  });
                  if (!_isMapMinimized) {
                    Future.delayed(const Duration(milliseconds: 350), () {
                      _fitMapBounds();
                    });
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    _isMapMinimized ? Icons.expand_more : Icons.expand_less,
                    color: const Color(0xFF2D2D2D),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideDetailsSection(RideModel ride) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trip Route
            _buildTripRoute(ride),

            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 24),

            // Fare Info
            _buildFareInfo(ride),

            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 24),

            // Driver Info
            _buildDriverInfo(ride),

            const SizedBox(height: 24),

            // Action Buttons
            if (ride.status == RideStatus.pending ||
                ride.status == RideStatus.failed)
              _buildCancelButton(ride),
          ],
        ),
      ),
    );
  }

  Widget _buildTripRoute(RideModel ride) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trip Route',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2D2D),
          ),
        ),
        const SizedBox(height: 16),
        // Pickup
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(width: 2, height: 40, color: const Color(0xFFE0E0E0)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pickup',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF757575),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ride.pickupAddress,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF2D2D2D),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Dropoff
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Color(0xFFFF5252),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Destination',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF757575),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ride.dropoffAddress,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF2D2D2D),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFareInfo(RideModel ride) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fare',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF757575),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₱${ride.fare.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF000000),
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'Requested',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF757575),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('MMM dd, h:mm a').format(ride.requestedAt),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2D2D2D),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDriverInfo(RideModel ride) {
    if (ride.status == RideStatus.pending) {
      return _buildSearchingDriverCard();
    }

    final driverId = ride.driverId ?? ride.assignedDriverId;

    if (driverId == null || driverId.isEmpty) {
      return _buildSearchingDriverCard();
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(driverId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingDriverCard();
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildSearchingDriverCard();
        }

        final driverData = snapshot.data!.data() as Map<String, dynamic>;
        final driverName = driverData['name'] ?? 'Driver';
        final driverPhone = driverData['phone'] ?? '';
        final vehicleInfo = driverData['vehicleInfo'] ?? 'Vehicle';

        return _buildDriverCard(driverName, driverPhone, vehicleInfo);
      },
    );
  }

  Widget _buildSearchingDriverCard() {
    return Semantics(
      label: 'Finding Driver. Searching for available drivers nearby',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFFF9800),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Finding Driver',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D2D2D),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Searching for available drivers nearby...',
                    style: TextStyle(fontSize: 13, color: Color(0xFF757575)),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFF9800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingDriverCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF2D2D2D),
            ),
          ),
          SizedBox(width: 16),
          Text(
            'Loading driver information...',
            style: TextStyle(fontSize: 14, color: Color(0xFF757575)),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(String name, String phone, String vehicle) {
    return Semantics(
      label: 'Your driver is $name, driving $vehicle',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E0E0)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2D2D2D),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.directions_car,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              vehicle,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF757575),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (phone.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Call driver',
                    button: true,
                    child: OutlinedButton.icon(
                      onPressed: () => _makePhoneCall(phone),
                      icon: const Icon(Icons.phone, size: 18),
                      label: const Text('Call'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4CAF50),
                        side: const BorderSide(color: Color(0xFF4CAF50)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    label: 'Send message to driver',
                    button: true,
                    child: OutlinedButton.icon(
                      onPressed: () => _sendMessage(phone),
                      icon: const Icon(Icons.message, size: 18),
                      label: const Text('Message'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2196F3),
                        side: const BorderSide(color: Color(0xFF2196F3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCancelButton(RideModel ride) {
    return Semantics(
      label: 'Cancel ride button',
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: () => _showCancelRideDialog(context, ride),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5252),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Cancel Ride',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  void _showBackConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Return to Dashboard?'),
        content: const Text(
          'Your ride will continue in the background. You can return to this screen anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay Here'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).pushReplacementNamed('/passenger');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D2D2D),
              foregroundColor: Colors.white,
            ),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  void _showCancelRideDialog(BuildContext context, RideModel ride) {
    showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Cancel Ride?',
        message:
            'Are you sure you want to cancel this ride? This action cannot be undone.',
        confirmText: 'Cancel Ride',
        cancelText: 'Keep Ride',
        icon: Icons.cancel_outlined,
        isDangerous: true,
        onConfirm: () => _cancelRide(context, ride),
      ),
    );
  }

  Future<void> _cancelRide(BuildContext context, RideModel ride) async {
    // Store references before async operations
    final navigator = Navigator.of(context);

    // Show loading dialog with clear message
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: ProgressIndicatorWithMessage(
            message: 'Cancelling ride...',
            subtitle: 'Please wait',
          ),
        ),
      ),
    );

    try {
      await Provider.of<FirestoreService>(
        context,
        listen: false,
      ).updateRideStatus(ride.id, RideStatus.cancelled);

      // Close loading dialog
      navigator.pop();

      // Show success message with clear feedback
      SnackbarHelper.showSuccess(
        context,
        'Ride cancelled successfully!',
        seconds: 3,
      );

      // Go back to dashboard
      navigator.pushReplacementNamed('/passenger');
    } catch (e) {
      // Close loading dialog
      navigator.pop();

      // Show error message with clear explanation
      SnackbarHelper.showError(
        context,
        'Failed to cancel ride. Please try again.',
        seconds: 4,
      );
    }
  }

  void _makePhoneCall(String phone) {
    SnackbarHelper.showInfo(context, 'Calling feature will be available soon');
  }

  void _sendMessage(String phone) {
    SnackbarHelper.showInfo(
      context,
      'Messaging feature will be available soon',
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
