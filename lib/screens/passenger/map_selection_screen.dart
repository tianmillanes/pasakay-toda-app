import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../services/location_service.dart';
import '../../widgets/usability_helpers.dart';

class MapSelectionScreen extends StatefulWidget {
  final String title;
  final bool isPickupLocation;
  final LatLng? initialLocation;

  const MapSelectionScreen({
    super.key,
    required this.title,
    required this.isPickupLocation,
    this.initialLocation,
  });

  @override
  State<MapSelectionScreen> createState() => _MapSelectionScreenState();
}

class _MapSelectionScreenState extends State<MapSelectionScreen> {
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
    _getCurrentLocation();
    _loadServiceAreaBoundary();
    if (_selectedLocation != null) {
      _getAddressForLocation(_selectedLocation!);
    }
  }

  Future<void> _getCurrentLocation() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final position = await locationService.getCurrentLocation();

    if (position != null && mounted) {
      final latLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = latLng;
      });

      // If no initial location, center on current location
      if (widget.initialLocation == null) {
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
      }
    }
  }

  Future<void> _loadServiceAreaBoundary() async {
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
            strokeColor: Colors.blue,
            strokeWidth: 2,
            fillColor: Colors.blue.withOpacity(0.1),
          ),
        );
      });
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _getCurrentLocation();

    // Add initial marker if location exists
    if (_selectedLocation != null) {
      _updateMarker(_selectedLocation!);
    }
  }

  void _onMapTapped(LatLng location) async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );

    // STRICT VALIDATION: Check if pickup location is within service area
    if (widget.isPickupLocation) {
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
    });

    _updateMarker(location);
    _getAddressForLocation(location);
  }

  void _updateMarker(LatLng location) {
    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('selected'),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            widget.isPickupLocation
                ? BitmapDescriptor.hueGreen
                : BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: widget.isPickupLocation
                ? 'Pickup Location'
                : 'Dropoff Location',
          ),
        ),
      );
    });
  }

  Future<void> _getAddressForLocation(LatLng location) async {
    setState(() {
      _isLoadingAddress = true;
    });

    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final address = await locationService.getAddressFromCoordinates(
      location.latitude,
      location.longitude,
    );

    setState(() {
      _selectedAddress = address;
      _isLoadingAddress = false;
    });
  }

  void _useCurrentLocation() async {
    if (_currentLocation == null) return;

    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );

    // STRICT VALIDATION: Check if current location is within service area (for pickup only)
    if (widget.isPickupLocation) {
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
    });

    _updateMarker(_currentLocation!);
    _getAddressForLocation(_currentLocation!);

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_currentLocation!, 16),
    );
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
    if (widget.isPickupLocation) {
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

    Navigator.of(
      context,
    ).pop({'location': _selectedLocation, 'address': _selectedAddress});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
        actions: [
          if (_currentLocation != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _useCurrentLocation,
              tooltip: 'Use Current Location',
            ),
        ],
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
              target:
                  widget.initialLocation ??
                  _currentLocation ??
                  const LatLng(15.4817, 120.5979),
              zoom: 16,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
          ),

          // Instructions at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.all(16),
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
                        widget.isPickupLocation
                            ? Icons.trip_origin
                            : Icons.location_on,
                        color: widget.isPickupLocation
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF5252),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isPickupLocation
                              ? 'Tap on the map to select pickup location'
                              : 'Tap on the map to select destination',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.isPickupLocation) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            border: Border.all(color: Colors.blue, width: 2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Pickup must be within service area',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Selected address and confirm button at bottom
          if (_selectedLocation != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.isPickupLocation
                              ? Icons.radio_button_checked
                              : Icons.location_on,
                          color: widget.isPickupLocation
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFF5252),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isPickupLocation
                                    ? 'Pickup Location'
                                    : 'Dropoff Location',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF757575),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _isLoadingAddress
                                  ? const Text(
                                      'Loading address...',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF2D2D2D),
                                      ),
                                    )
                                  : Text(
                                      _selectedAddress.isNotEmpty
                                          ? _selectedAddress
                                          : 'Selected location',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2D2D2D),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _confirmSelection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2D2D2D),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Confirm Location',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
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
