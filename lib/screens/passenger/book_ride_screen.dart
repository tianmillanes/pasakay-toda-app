import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/location_service.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../services/fare_service.dart';
import '../../services/address_search_service.dart';
import '../../models/ride_model.dart';
import '../../widgets/usability_helpers.dart';
import 'map_picker_screen.dart';

class BookRideScreen extends StatefulWidget {
  final LatLng? initialPickupLocation;
  final String? initialPickupAddress;
  final LatLng? initialDropoffLocation;
  final String? initialDropoffAddress;

  const BookRideScreen({
    super.key,
    this.initialPickupLocation,
    this.initialPickupAddress,
    this.initialDropoffLocation,
    this.initialDropoffAddress,
  });

  @override
  State<BookRideScreen> createState() => _BookRideScreenState();
}

class _BookRideScreenState extends State<BookRideScreen> {
  LatLng? _pickupLocation, _dropoffLocation, _currentLocation;
  String _pickupAddress = '',
      _dropoffAddress = '',
      _currentLocationAddress = '';
  double? _estimatedFare, _distance;
  int? _estimatedDuration;
  bool _isLoadingFare = false,
      _isBooking = false,
      _showPickupSuggestions = false;
  bool _showDestinationSuggestions = false, _isSearching = false;
  List<Map<String, dynamic>> _recentPickups = [],
      _recentDestinations = [],
      _searchResults = [];

  final _pickupController = TextEditingController(),
      _dropoffController = TextEditingController();
  final _pickupFocusNode = FocusNode(), _dropoffFocusNode = FocusNode();
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initializeLocations();
    _getCurrentLocation();
    _loadRecentLocations();
    _pickupController.addListener(
      () => _pickupController.text.isEmpty
          ? setState(() => _searchResults = [])
          : _performSearch(_pickupController.text),
    );
    _dropoffController.addListener(
      () => _dropoffController.text.isEmpty
          ? setState(() => _searchResults = [])
          : _performSearch(_dropoffController.text),
    );
  }

  void _initializeLocations() {
    // Pre-fill pickup location if provided
    if (widget.initialPickupLocation != null && widget.initialPickupAddress != null) {
      _pickupLocation = widget.initialPickupLocation;
      _pickupAddress = widget.initialPickupAddress!;
      _pickupController.text = widget.initialPickupAddress!;
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.initialPickupLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    // Pre-fill dropoff location if provided
    if (widget.initialDropoffLocation != null && widget.initialDropoffAddress != null) {
      _dropoffLocation = widget.initialDropoffLocation;
      _dropoffAddress = widget.initialDropoffAddress!;
      _dropoffController.text = widget.initialDropoffAddress!;
      _markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: widget.initialDropoffLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
      );
      
      // Calculate fare if both locations are provided
      if (_pickupLocation != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _calculateFareAndETA();
        });
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.length < 3) return setState(() => _searchResults = []);
    setState(() => _isSearching = true);
    try {
      final results = await AddressSearchService.searchAddresses(query);
      if (mounted)
        setState(() {
          _searchResults = results
              .map(
                (r) => {
                  'address': r.address,
                  'description': r.description,
                  'coordinates': r.coordinates,
                },
              )
              .toList();
          _isSearching = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
    }
  }

  Future<void> _openMapPicker(bool isForPickup) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => MapPickerScreen(
          isForPickup: isForPickup,
          initialLocation: isForPickup ? _pickupLocation : _dropoffLocation,
        ),
      ),
    );
    if (result != null && mounted) {
      final address = result['address'] as String,
          location = result['location'] as LatLng;
      setState(() {
        if (isForPickup) {
          _pickupController.text = address;
          _pickupAddress = address;
          _pickupLocation = location;
          _markers.removeWhere((m) => m.markerId.value == 'pickup');
          _markers.add(
            Marker(
              markerId: const MarkerId('pickup'),
              position: location,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          );
        } else {
          _dropoffController.text = address;
          _dropoffAddress = address;
          _dropoffLocation = location;
          _markers.removeWhere((m) => m.markerId.value == 'dropoff');
          _markers.add(
            Marker(
              markerId: const MarkerId('dropoff'),
              position: location,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            ),
          );
        }
      });
      if (_pickupLocation != null && _dropoffLocation != null)
        _calculateFareAndETA();
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
      final address = await locationService.getAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );
      setState(() {
        _currentLocation = latLng;
        _currentLocationAddress = address;
      });
    }
  }

  Future<void> _loadRecentLocations() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final ridesSnapshot = await FirebaseFirestore.instance
          .collection('rides')
          .where('passengerId', isEqualTo: authService.currentUser!.uid)
          .where(
            'status',
            isEqualTo: RideStatus.completed.toString().split('.').last,
          )
          .orderBy('requestedAt', descending: true)
          .limit(10)
          .get();

      Map<String, Map<String, dynamic>> pickupMap = {}, destinationMap = {};
      for (var doc in ridesSnapshot.docs) {
        final data = doc.data();
        final pickupAddr = data['pickupAddress'] as String?,
            dropoffAddr = data['dropoffAddress'] as String?;
        final pickupLoc = data['pickupLocation'] as GeoPoint?,
            dropoffLoc = data['dropoffLocation'] as GeoPoint?;
        if (pickupAddr != null &&
            pickupLoc != null &&
            !pickupMap.containsKey(pickupAddr)) {
          pickupMap[pickupAddr] = {
            'address': pickupAddr,
            'location': LatLng(pickupLoc.latitude, pickupLoc.longitude),
          };
        }
        if (dropoffAddr != null &&
            dropoffLoc != null &&
            !destinationMap.containsKey(dropoffAddr)) {
          destinationMap[dropoffAddr] = {
            'address': dropoffAddr,
            'location': LatLng(dropoffLoc.latitude, dropoffLoc.longitude),
          };
        }
      }
      if (mounted)
        setState(() {
          _recentPickups = pickupMap.values.toList();
          _recentDestinations = destinationMap.values.toList();
        });
    } catch (e) {}
  }

  Future<void> _calculateFareAndETA() async {
    if (_pickupLocation == null || _dropoffLocation == null) return;
    setState(() => _isLoadingFare = true);
    try {
      final result = await FareService.calculateFareAndETA(
        pickupLat: _pickupLocation!.latitude,
        pickupLng: _pickupLocation!.longitude,
        dropoffLat: _dropoffLocation!.latitude,
        dropoffLng: _dropoffLocation!.longitude,
      );
      setState(() {
        _estimatedFare = result['fare'] as double;
        _estimatedDuration = result['duration'] as int;
        _distance = result['distance'] as double;
        _isLoadingFare = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFare = false);
        SnackbarHelper.showError(context, 'Error calculating fare: $e');
      }
    }
  }

  Future<void> _bookRide() async {
    if (_pickupLocation == null ||
        _dropoffLocation == null ||
        _estimatedFare == null)
      return;

    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );

    // CRITICAL SECURITY: Check passenger's ACTUAL physical GPS location
    final currentPosition = await locationService.getCurrentLocation();
    if (currentPosition == null) {
      SnackbarHelper.showError(
        context,
        'Cannot determine your current location. Please enable GPS and try again.',
        seconds: 5,
      );
      return; // Block if no GPS
    }

    // VALIDATION 1: Passenger's REAL location must be inside service area
    if (!locationService.isInBarangayGeofence(
      currentPosition.latitude,
      currentPosition.longitude,
    )) {
      SnackbarHelper.showError(
        context,
        'You are currently outside the service area. You must be physically inside the barangay to book a ride.',
        seconds: 5,
      );
      return; // Block the booking - passenger is physically outside
    }

    // VALIDATION 2: Pickup location must also be within service area
    if (!locationService.isInBarangayGeofence(
      _pickupLocation!.latitude,
      _pickupLocation!.longitude,
    )) {
      SnackbarHelper.showError(
        context,
        'Pickup location must be within the service area. Please choose a location inside the barangay.',
        seconds: 5,
      );
      return; // Block the booking - selected location is outside
    }

    setState(() => _isBooking = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );
      final ride = RideModel(
        id: '',
        passengerId: authService.currentUser!.uid,
        pickupLocation: GeoPoint(
          _pickupLocation!.latitude,
          _pickupLocation!.longitude,
        ),
        dropoffLocation: GeoPoint(
          _dropoffLocation!.latitude,
          _dropoffLocation!.longitude,
        ),
        pickupAddress: _pickupAddress,
        dropoffAddress: _dropoffAddress,
        fare: _estimatedFare!,
        estimatedDuration: _estimatedDuration ?? 0,
        requestedAt: DateTime.now(),
      );
      final result = await firestoreService.createRideWithDriverCheck(ride);
      if (mounted) {
        if (result['success'] == true) {
          final driverAssigned = result['driverAssigned'] ?? false,
              onlineCount = result['onlineDriverCount'] ?? 0;
          SnackbarHelper.showSuccess(
            context,
            driverAssigned
                ? 'Ride booked successfully! Driver assigned.'
                : 'Ride booked! Finding driver ($onlineCount online)...',
            seconds: 3,
          );
          // Go back to dashboard
          Navigator.of(context).pop();
        } else {
          SnackbarHelper.showError(
            context,
            result['error'] ?? 'Failed to book ride',
            seconds: 5,
          );
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Error booking ride: $e');
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F5),
    appBar: AppBar(
      title: const Text('Book a Ride'),
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF2D2D2D),
      elevation: 0,
    ),
    body: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              _buildSearchField(true),
              const SizedBox(height: 12),
              _buildSearchField(false),
              if (_showPickupSuggestions || _showDestinationSuggestions)
                _buildInlineSuggestions(),
            ],
          ),
        ),
        if (_showPickupSuggestions || _showDestinationSuggestions)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _showPickupSuggestions = false;
                _showDestinationSuggestions = false;
              }),
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
          )
        else if (_pickupLocation != null && _dropoffLocation != null)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildRideDetails(),
            ),
          )
        else
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_taxi, size: 64, color: Colors.grey[300]),
                    const SizedBox(height: 16),
                    Text(
                      'Enter pickup and destination',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Type an address or tap the map icon to select',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _buildSearchField(bool isPickup) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isPickup ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
        width: 1.5,
      ),
    ),
    child: TextField(
      controller: isPickup ? _pickupController : _dropoffController,
      focusNode: isPickup ? _pickupFocusNode : _dropoffFocusNode,
      style: const TextStyle(
        fontSize: 15,
        color: Color(0xFF2D2D2D),
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: isPickup ? 'Enter pickup location' : 'Enter destination',
        hintStyle: const TextStyle(
          fontSize: 15,
          color: Color(0xFF757575),
          fontWeight: FontWeight.normal,
        ),
        prefixIcon: Icon(
          isPickup ? Icons.trip_origin : Icons.location_on,
          color: isPickup ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
          size: 20,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.map,
                size: 20,
                color: isPickup
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFFF5252),
              ),
              onPressed: () => _openMapPicker(isPickup),
              tooltip: 'Select on map',
            ),
            if ((isPickup ? _pickupController : _dropoffController)
                .text
                .isNotEmpty)
              IconButton(
                icon: const Icon(
                  Icons.clear,
                  size: 20,
                  color: Color(0xFF757575),
                ),
                onPressed: () {
                  (isPickup ? _pickupController : _dropoffController).clear();
                  setState(() {
                    if (isPickup) {
                      _pickupAddress = '';
                      _pickupLocation = null;
                      _markers.removeWhere((m) => m.markerId.value == 'pickup');
                    } else {
                      _dropoffAddress = '';
                      _dropoffLocation = null;
                      _markers.removeWhere(
                        (m) => m.markerId.value == 'dropoff',
                      );
                    }
                    _estimatedFare = null;
                    _searchResults = [];
                  });
                },
              ),
          ],
        ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      onTap: () => setState(() {
        _showPickupSuggestions = isPickup;
        _showDestinationSuggestions = !isPickup;
      }),
    ),
  );

  Widget _buildInlineSuggestions() {
    final isPickup = _showPickupSuggestions;
    final recents = isPickup ? _recentPickups : _recentDestinations;
    final currentQuery = isPickup
        ? _pickupController.text
        : _dropoffController.text;
    final showSearchResults =
        currentQuery.length >= 3 && _searchResults.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
            ),
            child: Row(
              children: [
                Icon(
                  isPickup ? Icons.trip_origin : Icons.location_on,
                  color: isPickup
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFFF5252),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  isPickup ? 'Select Pickup Location' : 'Select Destination',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: _isSearching
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                        color: Color(0xFF2D2D2D),
                      ),
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      if (showSearchResults) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.search,
                                size: 16,
                                color: Color(0xFF757575),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Search Results',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._searchResults
                            .map(
                              (result) => _buildSuggestionItem(
                                icon: Icons.location_on,
                                iconColor: const Color(0xFF2196F3),
                                title: result['address'],
                                subtitle: result['description'],
                                onTap: () {
                                  final coords =
                                      result['coordinates'] as LatLng;
                                  setState(() {
                                    if (isPickup) {
                                      _pickupController.text =
                                          result['address'];
                                      _pickupLocation = coords;
                                      _pickupAddress = result['address'];
                                      _showPickupSuggestions = false;
                                      _searchResults = [];
                                      _markers.removeWhere(
                                        (m) => m.markerId.value == 'pickup',
                                      );
                                      _markers.add(
                                        Marker(
                                          markerId: const MarkerId('pickup'),
                                          position: coords,
                                          icon:
                                              BitmapDescriptor.defaultMarkerWithHue(
                                                BitmapDescriptor.hueGreen,
                                              ),
                                        ),
                                      );
                                    } else {
                                      _dropoffController.text =
                                          result['address'];
                                      _dropoffLocation = coords;
                                      _dropoffAddress = result['address'];
                                      _showDestinationSuggestions = false;
                                      _searchResults = [];
                                      _markers.removeWhere(
                                        (m) => m.markerId.value == 'dropoff',
                                      );
                                      _markers.add(
                                        Marker(
                                          markerId: const MarkerId('dropoff'),
                                          position: coords,
                                          icon:
                                              BitmapDescriptor.defaultMarkerWithHue(
                                                BitmapDescriptor.hueRed,
                                              ),
                                        ),
                                      );
                                      if (_pickupLocation != null)
                                        _calculateFareAndETA();
                                    }
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ] else ...[
                        if (isPickup && _currentLocation != null)
                          _buildSuggestionItem(
                            icon: Icons.my_location,
                            iconColor: const Color(0xFF4CAF50),
                            title: 'Current Location',
                            subtitle: _currentLocationAddress,
                            onTap: () {
                              setState(() {
                                _pickupController.text =
                                    _currentLocationAddress;
                                _pickupLocation = _currentLocation;
                                _pickupAddress = _currentLocationAddress;
                                _showPickupSuggestions = false;
                                _markers.removeWhere(
                                  (m) => m.markerId.value == 'pickup',
                                );
                                _markers.add(
                                  Marker(
                                    markerId: const MarkerId('pickup'),
                                    position: _currentLocation!,
                                    icon: BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueGreen,
                                    ),
                                  ),
                                );
                              });
                              if (_dropoffLocation != null)
                                _calculateFareAndETA();
                            },
                          ),
                        if (recents.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.history,
                                  size: 16,
                                  color: Color(0xFF757575),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Recent',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...recents
                              .map(
                                (location) => _buildSuggestionItem(
                                  icon: Icons.history,
                                  iconColor: const Color(0xFF757575),
                                  title: location['address'],
                                  subtitle: '',
                                  onTap: () {
                                    setState(() {
                                      if (isPickup) {
                                        _pickupController.text =
                                            location['address'];
                                        _pickupLocation = location['location'];
                                        _pickupAddress = location['address'];
                                        _showPickupSuggestions = false;
                                        _markers.removeWhere(
                                          (m) => m.markerId.value == 'pickup',
                                        );
                                        _markers.add(
                                          Marker(
                                            markerId: const MarkerId('pickup'),
                                            position: location['location'],
                                            icon:
                                                BitmapDescriptor.defaultMarkerWithHue(
                                                  BitmapDescriptor.hueGreen,
                                                ),
                                          ),
                                        );
                                      } else {
                                        _dropoffController.text =
                                            location['address'];
                                        _dropoffLocation = location['location'];
                                        _dropoffAddress = location['address'];
                                        _showDestinationSuggestions = false;
                                        _markers.removeWhere(
                                          (m) => m.markerId.value == 'dropoff',
                                        );
                                        _markers.add(
                                          Marker(
                                            markerId: const MarkerId('dropoff'),
                                            position: location['location'],
                                            icon:
                                                BitmapDescriptor.defaultMarkerWithHue(
                                                  BitmapDescriptor.hueRed,
                                                ),
                                          ),
                                        );
                                        if (_pickupLocation != null)
                                          _calculateFareAndETA();
                                      }
                                    });
                                  },
                                ),
                              )
                              .toList(),
                        ] else
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 48,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No recent ${isPickup ? 'pickups' : 'destinations'}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Your recent locations will appear here after you complete rides',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Semantics(
    label: subtitle.isNotEmpty ? '$title, $subtitle' : title,
    button: true,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF2D2D2D),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF757575),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Color(0xFF757575),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildRideDetails() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0E0E0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ride Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2D2D),
          ),
        ),
        const SizedBox(height: 20),
        if (_isLoadingFare)
          const Padding(
            padding: EdgeInsets.all(32),
            child: ProgressIndicatorWithMessage(
              message: 'Calculating fare...',
              subtitle: 'Please wait while we estimate your ride cost',
            ),
          )
        else if (_estimatedFare != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      color: Color(0xFF000000),
                      size: 24,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Estimated Fare',
                      style: TextStyle(fontSize: 15, color: Color(0xFF757575)),
                    ),
                  ],
                ),
                Text(
                  FareService.formatFare(_estimatedFare!),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000000),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
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
                        Icons.straighten,
                        color: Color(0xFF2D2D2D),
                        size: 20,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        FareService.formatDistance(_distance ?? 0),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF000000),
                        ),
                      ),
                      const Text(
                        'Distance',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF757575),
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
                        size: 20,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        FareService.formatDuration(_estimatedDuration ?? 0),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF000000),
                        ),
                      ),
                      const Text(
                        'Duration',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF757575),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Semantics(
            label: 'Book ride button',
            button: true,
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isBooking ? null : _bookRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2D2D2D),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isBooking
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Booking...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Book Ride',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _pickupFocusNode.dispose();
    _dropoffFocusNode.dispose();
    super.dispose();
  }
}
