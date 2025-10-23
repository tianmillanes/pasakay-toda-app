import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';

class AddressSearchResult {
  final String address;
  final String description;
  final LatLng coordinates;
  final String placeId;

  AddressSearchResult({
    required this.address,
    required this.description,
    required this.coordinates,
    required this.placeId,
  });
}

class AddressSearchService {
  // Simulated places database for Tarlac area
  static final List<Map<String, dynamic>> _places = [
    {
      'name': 'SM City Tarlac',
      'address': 'MacArthur Highway, San Roque, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4900, 120.5950),
      'type': 'shopping_mall',
    },
    {
      'name': 'Tarlac State University',
      'address': 'Romulo Boulevard, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4750, 120.5900),
      'type': 'university',
    },
    {
      'name': 'Tarlac Provincial Hospital',
      'address': 'Magsaysay Avenue, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4800, 120.6000),
      'type': 'hospital',
    },
    {
      'name': 'Tarlac City Hall',
      'address': 'Zamora Street, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4820, 120.5980),
      'type': 'government',
    },
    {
      'name': 'Central Luzon State University',
      'address': 'Science City of Muñoz, Nueva Ecija',
      'coordinates': const LatLng(15.7250, 120.9000),
      'type': 'university',
    },
    {
      'name': 'Robinsons Starmills Pampanga',
      'address': 'Jose Abad Santos Avenue, San Fernando, Pampanga',
      'coordinates': const LatLng(15.0394, 120.6897),
      'type': 'shopping_mall',
    },
    {
      'name': 'Clark International Airport',
      'address': 'Clark Freeport Zone, Pampanga',
      'coordinates': const LatLng(15.1859, 120.5600),
      'type': 'airport',
    },
    {
      'name': 'Subic Bay Freeport Zone',
      'address': 'Subic Bay Freeport Zone, Zambales',
      'coordinates': const LatLng(14.8167, 120.2833),
      'type': 'freeport',
    },
    {
      'name': 'Baguio City Public Market',
      'address': 'Magsaysay Avenue, Baguio City',
      'coordinates': const LatLng(16.4023, 120.5960),
      'type': 'market',
    },
    {
      'name': 'Session Road',
      'address': 'Session Road, Baguio City',
      'coordinates': const LatLng(16.4120, 120.5930),
      'type': 'street',
    },
    // Add more Tarlac-specific locations
    {
      'name': 'Tarlac Recreation Center',
      'address': 'F. Tanedo Street, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4850, 120.5920),
      'type': 'recreation',
    },
    {
      'name': 'Metrotown Tarlac',
      'address': 'MacArthur Highway, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4880, 120.5940),
      'type': 'shopping_center',
    },
    {
      'name': 'Tarlac Bus Terminal',
      'address': 'MacArthur Highway, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4870, 120.5960),
      'type': 'transport',
    },
    {
      'name': 'Aquino Center',
      'address': 'Romulo Boulevard, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4790, 120.5890),
      'type': 'memorial',
    },
    {
      'name': 'Tarlac Public Market',
      'address': 'A. Mabini Street, Tarlac City, Tarlac',
      'coordinates': const LatLng(15.4830, 120.5970),
      'type': 'market',
    },
  ];

  // Search for addresses based on query
  static Future<List<AddressSearchResult>> searchAddresses(String query) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    if (query.trim().isEmpty) {
      return [];
    }

    final lowercaseQuery = query.toLowerCase();
    final results = <AddressSearchResult>[];

    // Search through places
    for (final place in _places) {
      final name = place['name'].toString().toLowerCase();
      final address = place['address'].toString().toLowerCase();

      if (name.contains(lowercaseQuery) || address.contains(lowercaseQuery)) {
        results.add(AddressSearchResult(
          address: place['address'],
          description: place['name'],
          coordinates: place['coordinates'],
          placeId: place['name'].toString().replaceAll(' ', '_').toLowerCase(),
        ));
      }
    }

    // Add some generic street addresses if query looks like an address
    if (query.length > 3) {
      results.addAll(_generateGenericAddresses(query));
    }

    // Sort by relevance (exact matches first)
    results.sort((a, b) {
      final aExact = a.description.toLowerCase().startsWith(lowercaseQuery) ? 0 : 1;
      final bExact = b.description.toLowerCase().startsWith(lowercaseQuery) ? 0 : 1;
      return aExact.compareTo(bExact);
    });

    return results.take(8).toList(); // Limit to 8 results
  }

  // Generate some generic addresses for the area
  static List<AddressSearchResult> _generateGenericAddresses(String query) {
    final results = <AddressSearchResult>[];
    final random = Random();

    // Common street names in Tarlac
    final streets = [
      'MacArthur Highway',
      'Romulo Boulevard',
      'Magsaysay Avenue',
      'Zamora Street',
      'F. Tanedo Street',
      'A. Mabini Street',
      'Jose Rizal Street',
      'Andres Bonifacio Street',
    ];

    // Generate some addresses that might match the query
    for (int i = 0; i < 3; i++) {
      final street = streets[random.nextInt(streets.length)];
      final number = random.nextInt(500) + 1;
      final address = '$number $street, Tarlac City, Tarlac';
      
      if (address.toLowerCase().contains(query.toLowerCase())) {
        // Generate coordinates near Tarlac City center
        final lat = 15.4800 + (random.nextDouble() - 0.5) * 0.02;
        final lng = 120.5950 + (random.nextDouble() - 0.5) * 0.02;
        
        results.add(AddressSearchResult(
          address: address,
          description: address,
          coordinates: LatLng(lat, lng),
          placeId: 'generated_${i}_${query.hashCode}',
        ));
      }
    }

    return results;
  }

  // Get coordinates from address (reverse of search)
  static Future<LatLng?> getCoordinatesFromAddress(String address) async {
    await Future.delayed(const Duration(milliseconds: 200));

    // Try to find exact match first
    for (final place in _places) {
      if (place['address'].toString().toLowerCase() == address.toLowerCase() ||
          place['name'].toString().toLowerCase() == address.toLowerCase()) {
        return place['coordinates'] as LatLng;
      }
    }

    // If no exact match, generate coordinates based on address
    if (address.toLowerCase().contains('tarlac')) {
      final random = Random(address.hashCode);
      final lat = 15.4800 + (random.nextDouble() - 0.5) * 0.02;
      final lng = 120.5950 + (random.nextDouble() - 0.5) * 0.02;
      return LatLng(lat, lng);
    }

    return null;
  }

  // Get address from coordinates (geocoding)
  static Future<String?> getAddressFromCoordinates(LatLng coordinates) async {
    await Future.delayed(const Duration(milliseconds: 200));

    // Find closest place
    double minDistance = double.infinity;
    String? closestAddress;

    for (final place in _places) {
      final placeCoords = place['coordinates'] as LatLng;
      final distance = _calculateDistance(coordinates, placeCoords);
      
      if (distance < minDistance) {
        minDistance = distance;
        closestAddress = place['address'];
      }
    }

    // If very close to a known place (within 100m), return that address
    if (minDistance < 0.1) {
      return closestAddress;
    }

    // Otherwise, generate a generic address
    return 'Near ${coordinates.latitude.toStringAsFixed(4)}, ${coordinates.longitude.toStringAsFixed(4)}, Tarlac City, Tarlac';
  }

  // Calculate distance between two coordinates (in km)
  static double _calculateDistance(LatLng coord1, LatLng coord2) {
    const double earthRadius = 6371; // Earth's radius in km

    final double lat1Rad = coord1.latitude * (pi / 180);
    final double lat2Rad = coord2.latitude * (pi / 180);
    final double deltaLatRad = (coord2.latitude - coord1.latitude) * (pi / 180);
    final double deltaLngRad = (coord2.longitude - coord1.longitude) * (pi / 180);

    final double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }
}
