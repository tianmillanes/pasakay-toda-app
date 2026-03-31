import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../models/lat_lng.dart';
import '../../services/location_service.dart';
import '../../services/firestore_service.dart';
import '../../services/address_search_service.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/location_helpers.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:async';

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
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleAnnotationManager;
  mapbox.CircleAnnotationManager? _userLocationAnnotationManager; // User location marker
  mapbox.PolygonAnnotationManager? _polygonAnnotationManager;
  
  LatLng? _selectedLocation;
  LatLng? _currentLocation;
  String _selectedAddress = '';
  bool _isLoadingAddress = false;
  bool _isConfirming = false;
  final _searchController = TextEditingController();
  List<AddressSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  Timer? _addressDebounceTimer;
  Timer? _searchDebounceTimer;
  DateTime? _ignoreCameraEventsUntil;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _getCurrentLocation();
    if (_selectedLocation != null) {
      _getAddressFromLocation(_selectedLocation!);
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
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        
        // Add user location marker (Google Maps style)
        _updateUserLocationMarker(_currentLocation!);
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
        SnackbarHelper.showError(
          context,
          'Could not get current location',
          seconds: 2,
        );
      }
    }
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

  Future<void> _loadServiceArea() async {
    if (_mapboxMap == null) return;
    
    try {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final barangayGeofence = locationService.getBarangayGeofence();

      // Only show boundary for pickup location selection
      if (widget.isForPickup && barangayGeofence != null && barangayGeofence.isNotEmpty) {
        final polygonPoints = barangayGeofence
            .map((coord) => [coord[1], coord[0]]) // Mapbox uses [lng, lat]
            .toList();

        // Ensure polygon is closed for Mapbox if needed, though usually it handles it
        if (polygonPoints.first[0] != polygonPoints.last[0] || polygonPoints.first[1] != polygonPoints.last[1]) {
          polygonPoints.add(polygonPoints.first);
        }

        if (_polygonAnnotationManager == null) {
          _polygonAnnotationManager = await _mapboxMap!.annotations.createPolygonAnnotationManager();
        } else {
          _polygonAnnotationManager!.deleteAll();
        }

        final color = Colors.green;
        
        final positions = polygonPoints.map((p) => mapbox.Position(p[0], p[1])).toList();

        await _polygonAnnotationManager!.create(
          mapbox.PolygonAnnotationOptions(
            geometry: mapbox.Polygon(coordinates: [positions]),
            fillColor: color.withOpacity(0.1).value,
            fillOutlineColor: color.value,
          ),
        );
      }
    } catch (e) {
      print('Error loading service area into Mapbox: $e');
    }
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _userLocationAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _polygonAnnotationManager = await mapboxMap.annotations.createPolygonAnnotationManager();

    // Load service area
    await _loadServiceArea();

    // Show user's current location marker (Google Maps style)
    if (_currentLocation != null) {
      _updateUserLocationMarker(_currentLocation!);
    }

    // Move camera to initial location or current location
    final targetLocation =
        _selectedLocation ??
        _currentLocation ??
        const LatLng(15.4817, 120.5979);
    
    _mapboxMap?.setCamera(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(targetLocation.longitude, targetLocation.latitude)),
        zoom: 15.0,
      ),
    );
  }

  void _onCameraChangeListener(mapbox.CameraChangedEventData event) {
    if (_ignoreCameraEventsUntil != null && DateTime.now().isBefore(_ignoreCameraEventsUntil!)) {
      return;
    }
    _debounceAddressFetch();
  }

  void _debounceAddressFetch() {
    _addressDebounceTimer?.cancel();
    _addressDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (_mapboxMap != null && mounted) {
        final cameraState = await _mapboxMap!.getCameraState();
        final location = LatLng(
          cameraState.center.coordinates.lat.toDouble(),
          cameraState.center.coordinates.lng.toDouble(),
        );
        _getAddressFromLocation(location);
      }
    });
  }

  void _onMapTapped(mapbox.MapContentGestureContext context) {
    final location = LatLng(context.point.coordinates.lat.toDouble(), context.point.coordinates.lng.toDouble());
    
    if (!mounted) return;
    
    // Instead of setting _selectedLocation and adding a marker,
    // just fly to the tapped location. The center pin will then
    // be at that location.
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(location.longitude, location.latitude)),
      ),
      mapbox.MapAnimationOptions(duration: 500),
    );
  }

  // Add user location marker (Google Maps style blue dot)
  Future<void> _updateUserLocationMarker(LatLng location) async {
    // User location marker removed as requested
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

  void _useCurrentLocation() {
    if (_currentLocation == null) {
      SnackbarHelper.showInfo(
        context,
        'Getting current location, please wait...',
        seconds: 3,
      );
      _getCurrentLocation();
      return;
    }

    setState(() {
      _selectedLocation = _currentLocation;
    });

    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(_currentLocation!.longitude, _currentLocation!.latitude)),
        zoom: 16.0,
      ),
      mapbox.MapAnimationOptions(duration: 1000),
    );

    _getAddressFromLocation(_currentLocation!);
  }

  Future<void> _performSearch(String query) async {
    _searchDebounceTimer?.cancel();
    
    if (query.length < 2) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _showSearchResults = false;
        });
      }
      return;
    }
    
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      
      setState(() {
        _isSearching = true;
        _showSearchResults = true;
      });
      
      try {
        LatLng? proximity = _currentLocation;
        // Try to use map center for better proximity search
        if (_mapboxMap != null) {
          try {
            final cameraState = await _mapboxMap!.getCameraState();
            proximity = LatLng(
              cameraState.center.coordinates.lat.toDouble(),
              cameraState.center.coordinates.lng.toDouble(),
            );
          } catch (_) {}
        }

        final results = await AddressSearchService.searchAddresses(
          query,
          proximity: proximity,
        );
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  void _selectSearchResult(AddressSearchResult result) {
    setState(() {
      _selectedLocation = result.coordinates;
      // Combine description (name) and address if they are different for better context
      _selectedAddress = (result.description != result.address && !result.address.contains(result.description))
          ? '${result.description}, ${result.address}'
          : result.address;
      _showSearchResults = false;
      _searchController.clear();
      // Ignore camera events for 2 seconds to prevent overwriting the selected address
      _ignoreCameraEventsUntil = DateTime.now().add(const Duration(seconds: 2));
    });
    
    _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(result.coordinates.longitude, result.coordinates.latitude),
        ),
        zoom: 16.0,
      ),
      mapbox.MapAnimationOptions(duration: 1000),
    );
  }

  Future<void> _confirmSelection() async {
    if (mounted) {
      setState(() {
        _isConfirming = true;
      });
    }

    try {
    LatLng? finalLocation;
    
    if (_mapboxMap != null) {
      // Use map center (where the blue pin is)
      final cameraState = await _mapboxMap!.getCameraState();
      finalLocation = LatLng(
        cameraState.center.coordinates.lat.toDouble(),
        cameraState.center.coordinates.lng.toDouble(),
      );
    }

    if (finalLocation == null) {
      if (_currentLocation != null) {
        // Fallback to current location if map center is somehow unavailable
        finalLocation = _currentLocation;
      } else {
        SnackbarHelper.showWarning(
          context,
          'Please select a location on the map',
        );
        return;
      }
    }

    _selectedLocation = finalLocation;
    
    // If we don't have an address yet, fetch it
    if (_selectedAddress.isEmpty || 
        _selectedAddress == 'Select where you want to be picked up' || 
        _selectedAddress == 'Select your destination' ||
        _selectedAddress == 'Unknown location') {
      
      try {
        final locationService = Provider.of<LocationService>(
          context,
          listen: false,
        );
        final address = await locationService.getAddressFromCoordinates(
          _selectedLocation!.latitude,
          _selectedLocation!.longitude,
        );
        if (mounted) {
          setState(() {
            _selectedAddress = address;
          });
        }
      } catch (e) {
        _selectedAddress = 'Selected location';
      }
    }

    if (!mounted) return;

    // Check geofence before confirming pickup location
    if (widget.isForPickup) {
      bool geofenceValid = false;
      try {
        final locationService = Provider.of<LocationService>(
          context,
          listen: false,
        );
        
        bool isInside = false;
        try {
          isInside = locationService.isInBarangayGeofence(
            _selectedLocation!.latitude,
            _selectedLocation!.longitude,
          );
        } catch (_) {
          // Geofence likely not loaded, treat as not inside for now
          isInside = false;
        }

        if (!isInside) {
          // Point is outside the currently loaded service area
          geofenceValid = false;
        }

        geofenceValid = isInside;

        if (!isInside) {
          // Show error and don't allow confirmation for pickup locations outside service area
          if (mounted) {
            SnackbarHelper.showError(
              context,
              'Pickup location must be within the service area. Please select a location inside the barangay.',
              seconds: 4,
            );
          }
        }
      } catch (e) {
        print('Geofence check failed/bypassed: $e');
        geofenceValid = false;
      }
      
      if (!geofenceValid) {
        return;
      }
    }

    if (mounted) {
      Navigator.pop(context, {
        'location': _selectedLocation,
        'address': _selectedAddress.isNotEmpty
            ? _selectedAddress
            : 'Selected location',
      });
    }
    } finally {
      if (mounted) {
        setState(() {
          _isConfirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Full Screen Map
          mapbox.MapWidget(
            key: const ValueKey("mapbox_picker"),
            onMapCreated: _onMapCreated,
            onTapListener: _onMapTapped,
            onCameraChangeListener: _onCameraChangeListener,
            cameraOptions: mapbox.CameraOptions(
              center: mapbox.Point(coordinates: mapbox.Position(120.5979, 15.4817)),
              zoom: 15.0,
            ),
          ),

          // Google Maps-style Floating Search Bar at top
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF5F6368)),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: _performSearch,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF202124),
                            ),
                            decoration: InputDecoration(
                              hintText: widget.isForPickup ? 'Search pickup location' : 'Search destination',
                              hintStyle: const TextStyle(
                                color: Color(0xFF70757A),
                                fontWeight: FontWeight.w400,
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (_isSearching)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A73E8)),
                            ),
                          )
                        else if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF5F6368), size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults = [];
                                _showSearchResults = false;
                              });
                            },
                          )
                        else
                          const Padding(
                            padding: EdgeInsets.only(right: 16),
                            child: Icon(Icons.search_rounded, color: Color(0xFF5F6368)),
                          ),
                      ],
                    ),
                  ),
                  
                  // Search Results Overlay (Google Maps Style)
                  if (_showSearchResults && _searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          separatorBuilder: (context, index) => const Divider(height: 1, indent: 64),
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            final placeType = _getPlaceType(result.address);
                            
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F3F4),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _getPlaceIcon(placeType),
                                  color: const Color(0xFF5F6368),
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                result.description,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF202124),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                result.address,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF70757A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _selectSearchResult(result),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Waze-inspired Center Pin (Blue Location Icon)
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 36), // Offset for pin point
              child: Icon(
                Icons.location_on_rounded,
                color: Color(0xFF1A73E8),
                size: 44,
              ),
            ),
          ),

          // Bottom Action Card (Google Maps / Waze Style)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (widget.isForPickup ? Colors.green : Colors.red).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isForPickup ? Icons.trip_origin_rounded : Icons.location_on_rounded,
                          color: widget.isForPickup ? Colors.green : Colors.red,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isForPickup ? 'Set Pickup Location' : 'Set Destination',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF202124),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedAddress.isNotEmpty 
                                ? _selectedAddress 
                                : (widget.isForPickup 
                                    ? 'Select where you want to be picked up' 
                                    : 'Select your destination'),
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedAddress.isNotEmpty ? const Color(0xFF5F6368) : const Color(0xFF70757A),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      // Current Location Button (Waze Style inside card)
                      Material(
                        color: const Color(0xFFF1F3F4),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: _useCurrentLocation,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            child: const Icon(Icons.my_location_rounded, color: Color(0xFF5F6368)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Confirm Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isConfirming ? null : _confirmSelection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A73E8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isConfirming
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Select',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Google Maps-like place type detection
  String _getPlaceType(String address) {
    final addrLower = address.toLowerCase();
    
    // Check for common place types
    if (addrLower.contains('mall') || addrLower.contains('shopping center') || 
        addrLower.contains('market') || addrLower.contains('store')) {
      return 'shopping';
    }
    if (addrLower.contains('restaurant') || addrLower.contains('food') || 
        addrLower.contains('cafe') || addrLower.contains('fast food')) {
      return 'food';
    }
    if (addrLower.contains('school') || addrLower.contains('university') || 
        addrLower.contains('college') || addrLower.contains('academy')) {
      return 'education';
    }
    if (addrLower.contains('hospital') || addrLower.contains('clinic') || 
        addrLower.contains('medical')) {
      return 'medical';
    }
    if (addrLower.contains('church') || addrLower.contains('mosque') || 
        addrLower.contains('temple')) {
      return 'religious';
    }
    if (addrLower.contains('airport') || addrLower.contains('terminal')) {
      return 'transport';
    }
    if (addrLower.contains('park') || addrLower.contains('plaza')) {
      return 'recreation';
    }
    if (addrLower.contains('bank') || addrLower.contains('atm')) {
      return 'financial';
    }
    if (addrLower.contains('hotel') || addrLower.contains('inn')) {
      return 'lodging';
    }
    
    // Check if it's a specific address
    if (RegExp(r'\d+').hasMatch(addrLower)) {
      return 'address';
    }
    
    return 'place'; // Default
  }

  // Get appropriate icon for place type (Google Maps style)
  IconData _getPlaceIcon(String placeType) {
    switch (placeType) {
      case 'shopping':
        return Icons.shopping_cart_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'education':
        return Icons.school_rounded;
      case 'medical':
        return Icons.local_hospital_rounded;
      case 'religious':
        return Icons.church_rounded;
      case 'transport':
        return Icons.flight_rounded;
      case 'recreation':
        return Icons.park_rounded;
      case 'financial':
        return Icons.account_balance_rounded;
      case 'lodging':
        return Icons.hotel_rounded;
      case 'address':
        return Icons.home_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  // Get icon color for place type (Google Maps style)
  Color _getPlaceIconColor(String placeType) {
    switch (placeType) {
      case 'shopping':
        return const Color(0xFF4285F4); // Blue
      case 'food':
        return const Color(0xFFEA4335); // Red
      case 'education':
        return const Color(0xFF34A853); // Green
      case 'medical':
        return const Color(0xFFEA4335); // Red
      case 'religious':
        return const Color(0xFF9C27B0); // Purple
      case 'transport':
        return const Color(0xFFFBBC04); // Yellow
      case 'recreation':
        return const Color(0xFF34A853); // Green
      case 'financial':
        return const Color(0xFF188038); // Dark Green
      case 'lodging':
        return const Color(0xFFEA4335); // Red
      case 'address':
        return const Color(0xFF5F6368); // Grey
      default:
        return const Color(0xFF5F6368); // Grey
    }
  }

  // Calculate distance between two points
  double _calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  // Format distance text like Google Maps
  String _getDistanceText(LatLng currentLocation, LatLng targetLocation) {
    final distanceInMeters = _calculateDistance(currentLocation, targetLocation);
    
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()} m';
    } else {
      final km = distanceInMeters / 1000;
      return '${km.toStringAsFixed(1)} km';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _addressDebounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    // Mapbox doesn't strictly need dispose in 2.x like GoogleMap did, 
    // but cleaning up managers is good.
    _circleAnnotationManager = null;
    _userLocationAnnotationManager = null;
    _polygonAnnotationManager = null;
    super.dispose();
  }
}
