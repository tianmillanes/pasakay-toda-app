import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../services/location_service.dart';
import '../../services/location_storage_service.dart';
import '../../utils/app_theme.dart';

class LocationSuggestionsSheet extends StatefulWidget {
  final Function(String address, LatLng location) onLocationSelected;
  final bool isPickupLocation;

  const LocationSuggestionsSheet({
    super.key,
    required this.onLocationSelected,
    required this.isPickupLocation,
  });

  @override
  State<LocationSuggestionsSheet> createState() => _LocationSuggestionsSheetState();
}

class _LocationSuggestionsSheetState extends State<LocationSuggestionsSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<String> _recentSearches = [];
  List<SavedLocation> _savedLocations = [];
  bool _isLoadingCurrentLocation = false;
  LatLng? _currentLocation;
  String _currentAddress = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final recents = await LocationStorageService.getRecentSearches();
    final saved = await LocationStorageService.getSavedLocations();
    
    if (mounted) {
      setState(() {
        _recentSearches = recents;
        _savedLocations = saved;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingCurrentLocation = true;
    });

    try {
      final locationService = Provider.of<LocationService>(context, listen: false);
      final position = await locationService.getCurrentLocation();
      
      if (position != null && mounted) {
        final latLng = LatLng(position.latitude, position.longitude);
        final address = await locationService.getAddressFromCoordinates(
          position.latitude,
          position.longitude,
        );
        
        setState(() {
          _currentLocation = latLng;
          _currentAddress = address;
          _isLoadingCurrentLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCurrentLocation = false;
        });
      }
    }
  }

  void _selectCurrentLocation() {
    if (_currentLocation != null) {
      widget.onLocationSelected(_currentAddress, _currentLocation!);
      Navigator.of(context).pop();
    }
  }

  void _selectRecentSearch(String address) async {
    // For recent searches without coordinates, we need to geocode
    // For now, just pass null and let the parent handle it
    Navigator.of(context).pop();
    // The parent will need to handle geocoding
  }

  void _selectSavedLocation(SavedLocation location) {
    widget.onLocationSelected(location.address, location.coordinates);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  widget.isPickupLocation ? Icons.trip_origin : Icons.location_on,
                  color: widget.isPickupLocation ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.isPickupLocation ? 'Select Pickup Location' : 'Select Destination',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
          ),

          // Current Location Card
          if (widget.isPickupLocation)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _currentLocation != null ? _selectCurrentLocation : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.my_location,
                          color: Color(0xFF4CAF50),
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Current Location',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2D2D2D),
                                ),
                              ),
                              const SizedBox(height: 4),
                              _isLoadingCurrentLocation
                                  ? const Text(
                                      'Getting your location...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF757575),
                                      ),
                                    )
                                  : Text(
                                      _currentAddress.isNotEmpty ? _currentAddress : 'Location unavailable',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF757575),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ],
                          ),
                        ),
                        if (_isLoadingCurrentLocation)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF4CAF50),
                            ),
                          )
                        else if (_currentLocation != null)
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Color(0xFF757575),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: const Color(0xFF2D2D2D),
              unselectedLabelColor: const Color(0xFF757575),
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(
                  icon: Icon(Icons.history, size: 20),
                  text: 'Recent',
                ),
                Tab(
                  icon: Icon(Icons.star, size: 20),
                  text: 'Favorites',
                ),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRecentTab(),
                _buildFavoritesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTab() {
    if (_recentSearches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No recent searches',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your recent locations will appear here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _recentSearches.length,
      itemBuilder: (context, index) {
        final search = _recentSearches[index];
        return _buildLocationItem(
          icon: Icons.history,
          iconColor: const Color(0xFF757575),
          title: search,
          subtitle: '',
          onTap: () => _selectRecentSearch(search),
        );
      },
    );
  }

  Widget _buildFavoritesTab() {
    if (_savedLocations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.star_border,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No saved locations',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Save your favorite places for quick access',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _savedLocations.length,
      itemBuilder: (context, index) {
        final location = _savedLocations[index];
        IconData iconData;
        Color iconColor;
        
        switch (location.iconName) {
          case 'home':
            iconData = Icons.home;
            iconColor = const Color(0xFF4CAF50);
            break;
          case 'work':
            iconData = Icons.work;
            iconColor = const Color(0xFF2196F3);
            break;
          case 'school':
            iconData = Icons.school;
            iconColor = const Color(0xFFFF9800);
            break;
          case 'local_hospital':
            iconData = Icons.local_hospital;
            iconColor = const Color(0xFFFF5252);
            break;
          case 'shopping_cart':
            iconData = Icons.shopping_cart;
            iconColor = const Color(0xFF9C27B0);
            break;
          case 'restaurant':
            iconData = Icons.restaurant;
            iconColor = const Color(0xFFFF5722);
            break;
          default:
            iconData = Icons.location_on;
            iconColor = AppTheme.primaryBlue;
        }

        return _buildLocationItem(
          icon: iconData,
          iconColor: iconColor,
          title: location.name,
          subtitle: location.address,
          onTap: () => _selectSavedLocation(location),
          showFavoriteIcon: true,
        );
      },
    );
  }

  Widget _buildLocationItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showFavoriteIcon = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: iconColor,
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D2D2D),
                        ),
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
                if (showFavoriteIcon)
                  const Icon(
                    Icons.star,
                    size: 18,
                    color: Color(0xFFFFC107),
                  )
                else
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
  }
}
