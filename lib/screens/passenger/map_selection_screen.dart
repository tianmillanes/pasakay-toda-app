import 'package:flutter/material.dart';
import '../../widgets/common/animated_map_button.dart';
import '../../models/lat_lng.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../widgets/location_helpers.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';
import '../../widgets/usability_helpers.dart';
import '../../config/credentials_config.dart';

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
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleAnnotationManager;
  mapbox.CircleAnnotationManager? _userLocationAnnotationManager; // User location marker
  mapbox.PolygonAnnotationManager? _polygonAnnotationManager;
  mapbox.PolylineAnnotationManager? _lineAnnotationManager;
  
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  String _selectedAddress = '';
  bool _isLoadingAddress = false;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _getCurrentLocation();
    if (_selectedLocation != null) {
      _getAddressForLocation(_selectedLocation!);
    }
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

        setState(() {
          _currentLocation = latLng;
        });

        // Show user location marker (Google Maps style)
        _updateUserLocationMarker(latLng);

        // If no initial location, center on current location
        if (widget.initialLocation == null && _mapboxMap != null) {
          _mapboxMap?.setCamera(
            mapbox.CameraOptions(
              center: mapbox.Point(coordinates: mapbox.Position(latLng.longitude, latLng.latitude)),
              zoom: 16.0,
            ),
          );
        }
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

  Future<void> _loadServiceAreaBoundary() async {
    if (_mapboxMap == null) return;

    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    final barangayGeofence = locationService.getBarangayGeofence();

    if (barangayGeofence != null && barangayGeofence.isNotEmpty) {
      final polygonPoints = barangayGeofence
          .map((coord) => [coord[1], coord[0]]) // Mapbox uses [lng, lat]
          .toList();

      if (polygonPoints.first[0] != polygonPoints.last[0] || polygonPoints.first[1] != polygonPoints.last[1]) {
        polygonPoints.add(polygonPoints.first);
      }

      if (_polygonAnnotationManager == null) {
        _polygonAnnotationManager = await _mapboxMap!.annotations.createPolygonAnnotationManager();
      }

      final positions = polygonPoints.map((p) => mapbox.Position(p[0], p[1])).toList();

      await _polygonAnnotationManager!.create(
        mapbox.PolygonAnnotationOptions(
          geometry: mapbox.Polygon(coordinates: [positions]),
          fillColor: Colors.green.withOpacity(0.1).value,
          fillOutlineColor: Colors.green.value,
        ),
      );
    }
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _userLocationAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _polygonAnnotationManager = await mapboxMap.annotations.createPolygonAnnotationManager();
    _lineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();

    _getCurrentLocation();
    _loadServiceAreaBoundary();

    // Show user's current location marker if available
    if (_currentLocation != null) {
      _updateUserLocationMarker(_currentLocation!);
    }

    // Add initial marker if location exists
    if (_selectedLocation != null) {
      _updateMarker(_selectedLocation!);
      
      _mapboxMap?.setCamera(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(_selectedLocation!.longitude, _selectedLocation!.latitude)),
          zoom: 16.0,
        ),
      );
    } else if (_currentLocation != null) {
      _mapboxMap?.setCamera(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(_currentLocation!.longitude, _currentLocation!.latitude)),
          zoom: 16.0,
        ),
      );
    }
  }

  void _onMapTapped(mapbox.MapContentGestureContext context) {
    final location = LatLng(context.point.coordinates.lat.toDouble(), context.point.coordinates.lng.toDouble());
    
    setState(() {
      _selectedLocation = location;
    });

    _updateMarker(location);
    _getAddressForLocation(location);
  }

  Future<void> _updateMarker(LatLng location) async {
    if (_circleAnnotationManager == null) return;
    
    await _circleAnnotationManager!.deleteAll();
    
    final color = widget.isPickupLocation ? const Color(0xFF4CAF50) : const Color(0xFFF44336);
    
    await _circleAnnotationManager!.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude)),
        circleRadius: 8.0,
        circleColor: color.value,
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );
  }

  // Add user location marker (Google Maps style blue dot)
  Future<void> _updateUserLocationMarker(LatLng location) async {
    // User location marker removed as requested
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

    if (mounted) {
      setState(() {
        _selectedAddress = address;
        _isLoadingAddress = false;
      });
    }
  }

  void _useCurrentLocation() async {
    if (_currentLocation == null) return;

    setState(() {
      _selectedLocation = _currentLocation;
    });

    _updateMarker(_currentLocation!);
    _getAddressForLocation(_currentLocation!);

    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(_currentLocation!.longitude, _currentLocation!.latitude)),
        zoom: 16.0,
      ),
      mapbox.MapAnimationOptions(duration: 1000),
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
          mapbox.MapWidget(
            key: const ValueKey("mapbox_selection"),
            onMapCreated: _onMapCreated,
            onTapListener: _onMapTapped,
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(coordinates: mapbox.Position(120.5979, 15.4817)),
              zoom: 16.0,
            ),
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
                            : const Color(0xFFF44336),
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
                            color: Colors.green.withOpacity(0.1),
                            border: Border.all(color: Colors.green, width: 2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Pickup from anywhere',
                          style: TextStyle(
                            fontSize: 11,
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6,
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
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isPickupLocation
                                    ? 'Pickup Location'
                                    : 'Dropoff Location',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF757575),
                                  fontWeight: FontWeight.w600,
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
    _circleAnnotationManager = null;
    _polygonAnnotationManager = null;
    _lineAnnotationManager = null;
    super.dispose();
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
