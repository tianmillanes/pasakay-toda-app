import 'package:google_maps_flutter/google_maps_flutter.dart';

class SavedLocation {
  final String id;
  final String name;
  final String address;
  final LatLng coordinates;
  final String iconName;
  final String colorHex;

  SavedLocation({
    required this.id,
    required this.name,
    required this.address,
    required this.coordinates,
    this.iconName = 'location_on',
    this.colorHex = '#007AFF',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': coordinates.latitude,
      'longitude': coordinates.longitude,
      'iconName': iconName,
      'colorHex': colorHex,
    };
  }

  factory SavedLocation.fromJson(Map<String, dynamic> json) {
    return SavedLocation(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      coordinates: LatLng(json['latitude'], json['longitude']),
      iconName: json['iconName'] ?? 'location_on',
      colorHex: json['colorHex'] ?? '#007AFF',
    );
  }
}

class LocationStorageService {
  // In-memory storage for demo purposes
  static List<SavedLocation> _savedLocations = [];
  static List<String> _recentSearches = [];
  static bool _initialized = false;

  // Get all saved locations
  static Future<List<SavedLocation>> getSavedLocations() async {
    if (!_initialized) {
      await initializeDefaultLocations();
    }
    return List.from(_savedLocations);
  }

  // Save a new location
  static Future<bool> saveLocation(SavedLocation location) async {
    try {
      // Check if location already exists
      final existingIndex = _savedLocations.indexWhere((loc) => loc.id == location.id);
      
      if (existingIndex != -1) {
        // Update existing location
        _savedLocations[existingIndex] = location;
      } else {
        // Add new location
        _savedLocations.add(location);
      }
      
      return true;
    } catch (e) {
      print('Error saving location: $e');
      return false;
    }
  }

  // Delete a saved location
  static Future<bool> deleteLocation(String locationId) async {
    try {
      _savedLocations.removeWhere((loc) => loc.id == locationId);
      return true;
    } catch (e) {
      print('Error deleting location: $e');
      return false;
    }
  }

  // Get recent searches
  static Future<List<String>> getRecentSearches() async {
    return List.from(_recentSearches);
  }

  // Add to recent searches
  static Future<void> addRecentSearch(String searchTerm) async {
    if (searchTerm.trim().isEmpty) return;
    
    // Remove if already exists
    _recentSearches.remove(searchTerm);
    
    // Add to beginning
    _recentSearches.insert(0, searchTerm);
    
    // Keep only last 10 searches
    if (_recentSearches.length > 10) {
      _recentSearches.removeRange(10, _recentSearches.length);
    }
  }

  // Clear recent searches
  static Future<void> clearRecentSearches() async {
    _recentSearches.clear();
  }

  // Get default locations (if no saved locations exist)
  static List<SavedLocation> getDefaultLocations() {
    return [
      SavedLocation(
        id: 'home',
        name: 'Home',
        address: 'Tarlac City, Tarlac',
        coordinates: const LatLng(15.4817, 120.5979),
        iconName: 'home',
        colorHex: '#4CAF50',
      ),
      SavedLocation(
        id: 'work',
        name: 'Work',
        address: 'SM City Tarlac, Tarlac',
        coordinates: const LatLng(15.4900, 120.5950),
        iconName: 'work',
        colorHex: '#2196F3',
      ),
      SavedLocation(
        id: 'school',
        name: 'School',
        address: 'Tarlac State University, Tarlac',
        coordinates: const LatLng(15.4750, 120.5900),
        iconName: 'school',
        colorHex: '#FF9800',
      ),
    ];
  }

  // Initialize with default locations if none exist
  static Future<void> initializeDefaultLocations() async {
    if (_initialized) return;
    
    _initialized = true;
    
    if (_savedLocations.isEmpty) {
      final defaultLocations = getDefaultLocations();
      for (final location in defaultLocations) {
        await saveLocation(location);
      }
    }
  }
}
