import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../services/fare_service.dart';
import '../../models/ride_model.dart';
import '../../widgets/usability_helpers.dart';

class ActiveTripScreen extends StatefulWidget {
  final RideModel ride;

  const ActiveTripScreen({super.key, required this.ride});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
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
        [widget.ride.pickupLocation.latitude, widget.ride.dropoffLocation.latitude].reduce((a, b) => a < b ? a : b),
        [widget.ride.pickupLocation.longitude, widget.ride.dropoffLocation.longitude].reduce((a, b) => a < b ? a : b),
      ),
      northeast: LatLng(
        [widget.ride.pickupLocation.latitude, widget.ride.dropoffLocation.latitude].reduce((a, b) => a > b ? a : b),
        [widget.ride.pickupLocation.longitude, widget.ride.dropoffLocation.longitude].reduce((a, b) => a > b ? a : b),
      ),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  Future<void> _updateRideStatus(RideStatus newStatus) async {
    // Store navigator reference
    final navigator = Navigator.of(context);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: ProgressIndicatorWithMessage(
            message: 'Updating status...',
            subtitle: 'Please wait',
          ),
        ),
      ),
    );

    try {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      await firestoreService.updateRideStatus(widget.ride.id, newStatus);

      // Close loading dialog
      navigator.pop();

      String message = '';
      switch (newStatus) {
        case RideStatus.driverOnWay:
          message = 'Heading to pickup location';
          break;
        case RideStatus.driverArrived:
          message = 'Arrived at pickup location';
          break;
        case RideStatus.inProgress:
          message = 'Trip started successfully';
          break;
        case RideStatus.completed:
          message = 'Trip completed successfully!';
          break;
        default:
          message = 'Status updated';
      }

      if (mounted) {
        SnackbarHelper.showSuccess(context, message, seconds: 3);
      }
    } catch (e) {
      // Close loading dialog
      navigator.pop();

      if (mounted) {
        SnackbarHelper.showError(
          context,
          'Failed to update status. Please try again.',
          seconds: 4,
        );
      }
    }
  }

  String _getStatusText(RideStatus status) {
    switch (status) {
      case RideStatus.accepted:
        return 'Trip Accepted';
      case RideStatus.driverOnWay:
        return 'On The Way';
      case RideStatus.driverArrived:
        return 'Arrived at Pickup';
      case RideStatus.inProgress:
        return 'Trip In Progress';
      case RideStatus.completed:
        return 'Trip Completed';
      default:
        return 'Active Trip';
    }
  }

  String _getStatusSubtext(RideStatus status) {
    switch (status) {
      case RideStatus.accepted:
        return 'Head to pickup location';
      case RideStatus.driverOnWay:
        return 'Driving to pickup location';
      case RideStatus.driverArrived:
        return 'Waiting for passenger';
      case RideStatus.inProgress:
        return 'Drive safely to destination';
      case RideStatus.completed:
        return 'Thank you for your service';
      default:
        return '';
    }
  }

  Color _getStatusColor(RideStatus status) {
    switch (status) {
      case RideStatus.accepted:
        return const Color(0xFF2196F3);
      case RideStatus.driverOnWay:
        return const Color(0xFF9C27B0);
      case RideStatus.driverArrived:
        return const Color(0xFFFF9800);
      case RideStatus.inProgress:
        return const Color(0xFF00BCD4);
      case RideStatus.completed:
        return const Color(0xFF4CAF50);
      default:
        return const Color(0xFF757575);
    }
  }

  IconData _getStatusIcon(RideStatus status) {
    switch (status) {
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
      default:
        return Icons.local_taxi;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushReplacementNamed('/driver');
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: const Text(
            'Active Trip',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2D2D2D),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pushReplacementNamed('/driver'),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.navigation_outlined),
              onPressed: () {
                SnackbarHelper.showInfo(context, 'Navigation feature coming soon');
              },
            ),
          ],
        ),
        body: StreamBuilder<RideModel?>(
          stream: Provider.of<FirestoreService>(context).getRideStream(widget.ride.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ProgressIndicatorWithMessage(
                message: 'Loading trip details...',
                subtitle: 'Please wait while we fetch trip information',
              );
            }

            final ride = snapshot.data ?? widget.ride;

            // Auto-navigate when trip completes
            if (ride.status == RideStatus.completed) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pushReplacementNamed('/driver');
              });
            }

            return Column(
              children: [
                // Status Banner
                _buildStatusBanner(ride.status),

                // Map Section
                _buildMapSection(ride),

                // Trip Details Section
                Expanded(
                  child: _buildTripDetailsSection(ride),
                ),
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
              child: Icon(
                _getStatusIcon(status),
                color: Colors.white,
                size: 20,
              ),
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
            child: Semantics(
              label: _isMapMinimized ? 'Expand map' : 'Minimize map',
              button: true,
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
          ),
        ],
      ),
    );
  }

  Widget _buildTripDetailsSection(RideModel ride) {
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

            // Fare and Duration
            _buildFareInfo(ride),

            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 24),

            // Passenger Info
            _buildPassengerInfo(ride),

            const SizedBox(height: 24),

            // Action Button
            _buildActionButton(ride.status),
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
                Container(
                  width: 2,
                  height: 40,
                  color: const Color(0xFFE0E0E0),
                ),
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
                      color: Color(0xFF000000),
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
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.payments_outlined,
                  color: Color(0xFF000000),
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  FareService.formatFare(ride.fare),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000000),
                  ),
                ),
                const Text(
                  'Fare',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF757575),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.access_time,
                  color: Color(0xFF2D2D2D),
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  FareService.formatDuration(ride.estimatedDuration),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000000),
                  ),
                ),
                const Text(
                  'Duration',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF757575),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPassengerInfo(RideModel ride) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(ride.passengerId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingPassengerCard();
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildUnknownPassengerCard();
        }

        final passengerData = snapshot.data!.data() as Map<String, dynamic>;
        final passengerName = passengerData['name'] ?? 'Unknown';
        final passengerPhone = passengerData['phone'] ?? '';

        return _buildPassengerCard(passengerName, passengerPhone);
      },
    );
  }

  Widget _buildLoadingPassengerCard() {
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
            'Loading passenger information...',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF757575),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnknownPassengerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.person_outline,
            color: Color(0xFF757575),
            size: 24,
          ),
          SizedBox(width: 16),
          Text(
            'Passenger information unavailable',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF757575),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerCard(String name, String phone) {
    return Semantics(
      label: 'Passenger: $name${phone.isNotEmpty ? ", phone: $phone" : ""}',
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
                      const Text(
                        'Passenger',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF757575),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                      if (phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF757575),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (phone.isNotEmpty) ...[
              const SizedBox(height: 16),
              Semantics(
                label: 'Call passenger',
                button: true,
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      SnackbarHelper.showInfo(context, 'Calling $phone...');
                    },
                    icon: const Icon(Icons.phone, size: 18),
                    label: const Text('Call Passenger'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4CAF50),
                      side: const BorderSide(color: Color(0xFF4CAF50)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(RideStatus status) {
    String buttonText;
    IconData buttonIcon;
    VoidCallback? onPressed;

    switch (status) {
      case RideStatus.accepted:
        buttonText = 'Start Driving to Pickup';
        buttonIcon = Icons.directions_car;
        onPressed = () => _updateRideStatus(RideStatus.driverOnWay);
        break;
      case RideStatus.driverOnWay:
        buttonText = 'I\'ve Arrived';
        buttonIcon = Icons.location_on;
        onPressed = () => _updateRideStatus(RideStatus.driverArrived);
        break;
      case RideStatus.driverArrived:
        buttonText = 'Start Trip';
        buttonIcon = Icons.play_arrow;
        onPressed = () => _updateRideStatus(RideStatus.inProgress);
        break;
      case RideStatus.inProgress:
        buttonText = 'Complete Trip';
        buttonIcon = Icons.check_circle;
        onPressed = () => _showCompleteDialog();
        break;
      default:
        return const SizedBox.shrink();
    }

    return Semantics(
      label: buttonText,
      button: true,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(buttonIcon, size: 20),
          label: Text(
            buttonText,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D2D2D),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  void _showCompleteDialog() {
    showDialog(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: 'Complete Trip?',
        message:
            'Are you sure you want to mark this trip as completed? The passenger will be notified.',
        confirmText: 'Complete Trip',
        cancelText: 'Not Yet',
        icon: Icons.check_circle_outline,
        confirmColor: const Color(0xFF4CAF50),
        onConfirm: () => _updateRideStatus(RideStatus.completed),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
