import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../services/location_service.dart';
import '../../widgets/usability_helpers.dart';

class MapPickerScreen extends StatefulWidget {
  final bool isForPickup;
  final LatLng? initialLocation;

  const MapPickerScreen({
    super.key,
    required this.isForPickup,
    this.initialLocation,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  String _selectedAddress = '';
  bool _isLoadingAddress = false;
  final Set<Marker> _markers = {};
  final Set<Polygon> _polygons = {};

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    if (_selectedLocation != null) {
      _updateMarker(_selectedLocation!);
      _getAddressFromLocation(_selectedLocation!);
    }
    _loadCurrentLocation();
    _loadServiceArea();
  }

  Future<void> _loadCurrentLocation() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final position = await locationService.getCurrentLocation();

    if (position != null && mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });
    }
  }

  Future<void> _loadServiceArea() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final barangayGeofence = locationService.getBarangayGeofence();

    if (barangayGeofence != null && barangayGeofence.isNotEmpty) {
      final polygonPoints = barangayGeofence
          .map((coord) => LatLng(coord[0], coord[1]))
          .toList();

      setState(() {
        _polygons.add(
          Polygon(
            polygonId: const PolygonId('service_area'),
            points: polygonPoints,
            strokeColor: widget.isForPickup ? Colors.green : Colors.red,
            strokeWidth: 2,
            fillColor: (widget.isForPickup ? Colors.green : Colors.red)
                .withOpacity(0.1),
          ),
        );
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    // Move camera to initial location or current location
    final targetLocation =
        _selectedLocation ??
        _currentLocation ??
        const LatLng(15.4817, 120.5979);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(targetLocation, 15),
    );
  }

  Future<void> _onMapTapped(LatLng location) async {
    // STRICT VALIDATION: If selecting pickup, check if within service area
    if (widget.isForPickup) {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      if (!locationService.isInBarangayGeofence(
        location.latitude,
        location.longitude,
      )) {
        SnackbarHelper.showError(
          context,
          'This location is outside the service area. Please select a pickup location inside the barangay.',
          seconds: 4,
        );
        return; // Block the selection
      }
    }

    setState(() {
      _selectedLocation = location;
      _updateMarker(location);
    });

    await _getAddressFromLocation(location);
  }

  void _updateMarker(LatLng location) {
    _markers.clear();
    _markers.add(
      Marker(
        markerId: const MarkerId('selected'),
        position: location,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          widget.isForPickup
              ? BitmapDescriptor.hueGreen
              : BitmapDescriptor.hueRed,
        ),
      ),
    );
  }

  Future<void> _getAddressFromLocation(LatLng location) async {
    setState(() {
      _isLoadingAddress = true;
    });

    try {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final address = await locationService.getAddressFromCoordinates(
        location.latitude,
        location.longitude,
      );

      if (mounted) {
        setState(() {
          _selectedAddress = address;
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _selectedAddress = 'Unknown location';
          _isLoadingAddress = false;
        });
      }
    }
  }

  void _useCurrentLocation() async {
    if (_currentLocation == null) return;

    // STRICT VALIDATION: Check if current location is within service area for pickup
    if (widget.isForPickup) {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      if (!locationService.isInBarangayGeofence(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
      )) {
        SnackbarHelper.showError(
          context,
          'Your current location is outside the service area. You can only book rides from inside the barangay.',
          seconds: 4,
        );
        return; // Block using current location
      }
    }

    setState(() {
      _selectedLocation = _currentLocation;
      _updateMarker(_currentLocation!);
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_currentLocation!, 16),
    );

    await _getAddressFromLocation(_currentLocation!);
  }

  void _confirmSelection() {
    if (_selectedLocation == null) {
      SnackbarHelper.showWarning(
        context,
        'Please select a location on the map',
      );
      return;
    }

    // FINAL VALIDATION: Double-check geofence before confirming pickup location
    if (widget.isForPickup) {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      if (!locationService.isInBarangayGeofence(
        _selectedLocation!.latitude,
        _selectedLocation!.longitude,
      )) {
        SnackbarHelper.showError(
          context,
          '🚫 Selected pickup location is outside the service area. Please choose a location inside the barangay.',
          seconds: 4,
        );
        return; // Block confirmation
      }
    }

    Navigator.pop(context, {
      'location': _selectedLocation,
      'address': _selectedAddress.isNotEmpty
          ? _selectedAddress
          : 'Selected location',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isForPickup ? 'Select Pickup Location' : 'Select Destination',
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Map
          GoogleMap(
            onMapCreated: _onMapCreated,
            onTap: _onMapTapped,
            markers: _markers,
            polygons: _polygons,
            initialCameraPosition: CameraPosition(
              target: _currentLocation ?? const LatLng(15.4817, 120.5979),
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),

          // Instructions at top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.isForPickup
                            ? Icons.trip_origin
                            : Icons.location_on,
                        color: widget.isForPickup
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF5252),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.isForPickup
                              ? 'Tap map to select pickup (must be in service area)'
                              : 'Tap map to select destination (anywhere)',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedAddress.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Text(
                      _selectedAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF757575),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Current location button
          if (_currentLocation != null && widget.isForPickup)
            Positioned(
              bottom: 100,
              right: 16,
              child: FloatingActionButton(
                onPressed: _useCurrentLocation,
                backgroundColor: const Color(0xFF4CAF50),
                child: const Icon(Icons.my_location, color: Colors.white),
              ),
            ),

          // Confirm button
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: _isLoadingAddress ? null : _confirmSelection,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D2D2D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: _isLoadingAddress
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _selectedLocation == null
                          ? 'Select Location on Map'
                          : 'Confirm Location',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
