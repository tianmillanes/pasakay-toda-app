import 'dart:convert';
import 'dart:math' show cos, sqrt, asin, pi;
import 'package:http/http.dart' as http;
import '../models/lat_lng.dart';
import '../config/credentials_config.dart';
import 'cache_service.dart';

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
  // ============================================================================
  // GEOGRAPHIC RESTRICTIONS - PHILIPPINES ONLY
  // ============================================================================
  // This service is restricted to Philippines region only.
  
  static const String _baseUrl = 'https://api.mapbox.com/geocoding/v5/mapbox.places';
  static String get _accessToken => CredentialsConfig.mapboxAccessToken;
  static final CacheService _cache = CacheService();
  static final http.Client _client = http.Client(); // Persistent client for better performance

  // Use Mapbox Geocoding API with Google Maps-like behavior - PHILIPPINES ONLY
  static Future<List<AddressSearchResult>> searchAddresses(String query, {LatLng? proximity}) async {
    if (query.trim().isEmpty) return [];

    // Include proximity in cache key to ensure context-aware results
    String cacheKey = 'search_$query';
    if (proximity != null) {
      // Round to ~110m precision (3 decimal places) to allow some cache hits while moving slightly
      final lat = proximity.latitude.toStringAsFixed(3);
      final lng = proximity.longitude.toStringAsFixed(3);
      cacheKey += '_${lat}_$lng';
    }
    
    // Check cache first
    final cached = _cache.get<List<AddressSearchResult>>(cacheKey);
    if (cached != null) {
      return cached;
    }

    final String accessToken = _accessToken;
    
    // Google Maps-like search parameters restricted to Philippines
    String url = '$_baseUrl/${Uri.encodeComponent(query)}.json'
        '?access_token=$accessToken'
        '&limit=10'                    // Max limit for Mapbox Geocoding API
        '&types=poi,address,place,locality,neighborhood,district,region,postcode'  // All types for establishments (Jollibee, McDo, etc.)
        '&autocomplete=true'             // Enable autocomplete-like behavior
        '&fuzzyMatch=true'             // Enable fuzzy matching for typos
        '&routing=false'                // Faster response without routing data
        '&language=en'                  // English results with local names
        '&country=PH';                  // RESTRICT TO PHILIPPINES ONLY

    // Add proximity to prioritize nearest results (Google Maps-like behavior)
    if (proximity != null) {
      url += '&proximity=${proximity.longitude},${proximity.latitude}';
    }

    try {
            // Use persistent client for better performance
            final response = await _client.get(Uri.parse(url));

            if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List features = data['features'];

        // Sort results by relevance, proximity, and importance (Google Maps-like ranking)
        final sortedResults = _sortResultsByRelevance(features, query, proximity);

        // Limit to top 10 most relevant results for better UX
        final topResults = sortedResults.take(10).toList();

        // Cache the results for 5 minutes
        _cache.put(cacheKey, topResults, expiration: Duration(minutes: 5));
        return topResults.map((f) {
          final List center = f['center']; // [lng, lat]
          final context = f['context'] as List<dynamic>? ?? [];
          
          // Build comprehensive address like Google Maps
          String fullAddress = _buildFullAddress(f, context);
          
          return AddressSearchResult(
            address: fullAddress,
            description: f['text'] ?? '',
            coordinates: LatLng(center[1].toDouble(), center[0].toDouble()),
            placeId: f['id'] ?? '',
          );
        }).toList();
      } else {
            // Log error for debugging (Mapbox Best Practice: Monitor API health)
            print('Mapbox Search Error: ${response.statusCode} - ${response.body}');
            return [];
          }
        } catch (e) {
          print('Error searching Mapbox addresses: $e');
          return [];
        }
  }

  // Sort results like Google Maps - by proximity (distance), relevance, and importance
  static List<Map<String, dynamic>> _sortResultsByRelevance(
    List features, 
    String query, 
    LatLng? userLocation,
  ) {
    final queryLower = query.toLowerCase();
    
    // Calculate comprehensive score for each result
    final scoredResults = features.map((feature) {
      final text = (feature['text'] as String? ?? '').toLowerCase();
      final placeName = (feature['place_name'] as String? ?? '').toLowerCase();
      // Safely handle relevance which might be int or double
      final relevance = (feature['relevance'] as num?)?.toDouble() ?? 0.0;
      
      double score = relevance * 100; // Base score from Mapbox relevance
      
      // === TEXT MATCHING SCORING (Google Maps-like) ===
      // Exact matches get highest boost
      if (text == queryLower || placeName == queryLower) {
        score += 100;
      }
      // Starts with query gets strong boost
      else if (text.startsWith(queryLower) || placeName.startsWith(queryLower)) {
        score += 60;
      }
      // Contains query gets moderate boost
      else if (text.contains(queryLower) || placeName.contains(queryLower)) {
        score += 30;
      }
      
      // === PROXIMITY SCORING (MOST IMPORTANT - like Google Maps) ===
      if (userLocation != null) {
        final List center = feature['center'];
        // Safely convert coordinates which might be int or double
        final resultLat = (center[1] as num).toDouble();
        final resultLng = (center[0] as num).toDouble();
        final resultLocation = LatLng(resultLat, resultLng);
        
        // Calculate distance in meters
        final distance = _calculateDistance(userLocation, resultLocation);
        
        // Proximity scoring - HEAVILY weight closer locations (Google Maps style)
        // Ensure continuity in scoring function
        
        // < 500m: Extreme boost for immediate vicinity (walking distance)
        if (distance < 500) {
           score += 1000 - (distance * 0.2); // 1000 -> 900
        }
        // 500m - 2km: Strong boost for local area (tricycle distance)
        else if (distance < 2000) {
           score += 800 - ((distance - 500) * 0.2); // 900 -> 600
        }
        // 2km - 10km: Moderate boost for city-wide
        else if (distance < 10000) {
           score += 400 - ((distance - 2000) * 0.0375); // 600 -> 300
        }
        // 10km - 50km: Slight boost for region
        else if (distance < 50000) {
           score += 100 - ((distance - 10000) * 0.002); // 300 -> 220 (decay slower)
        }
        // > 50km: Minimal boost
        else {
           score += 50 * (50000 / distance);
        }
      }
      
      // === PLACE TYPE SCORING ===
      final placeType = _getPlaceType(feature);
      if (placeType == 'poi') score += 25; // Points of interest - very useful
      if (placeType == 'address') score += 20; // Specific addresses - most precise
      if (placeType == 'place') score += 15; // Cities/towns - common searches
      if (placeType == 'locality') score += 12; // Localities
      if (placeType == 'district') score += 10; // Districts
      
      // === CONTEXT SCORING (populated areas) ===
      final context = feature['context'] as List<dynamic>? ?? [];
      bool hasPlaceContext = false;
      for (final ctx in context) {
        final ctxId = ctx['id']?.toString() ?? '';
        if (ctxId.contains('place')) {
          score += 8; // In a city/town
          hasPlaceContext = true;
        }
        if (ctxId.contains('region') && hasPlaceContext) {
          score += 5; // In a known region
        }
      }
      
      return {
        'feature': feature,
        'score': score,
      };
    }).toList();
    
    // Sort by score (highest first) - nearest and most relevant locations appear first
    scoredResults.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    return scoredResults.map((r) => r['feature'] as Map<String, dynamic>).toList();
  }

  // Calculate distance between two coordinates (Haversine formula)
  static double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // meters
    
    final double lat1Rad = point1.latitude * (pi / 180);
    final double lat2Rad = point2.latitude * (pi / 180);
    final double deltaLat = (point2.latitude - point1.latitude) * (pi / 180);
    final double deltaLng = (point2.longitude - point1.longitude) * (pi / 180);
    
    final double a = (1 - cos(deltaLat)) / 2 +
        cos(lat1Rad) * cos(lat2Rad) *
        (1 - cos(deltaLng)) / 2;
        
    final double c = 2 * asin(sqrt(a));
    
    return earthRadius * c;
  }

  // Determine place type for ranking
  static String _getPlaceType(Map<String, dynamic> feature) {
    final types = feature['place_type'] as List<dynamic>? ?? [];
    if (types.contains('poi')) return 'poi';
    if (types.contains('address')) return 'address';
    if (types.contains('place')) return 'place';
    if (types.contains('region')) return 'region';
    if (types.contains('district')) return 'district';
    if (types.contains('locality')) return 'locality';
    return 'neighborhood';
  }

  // Build comprehensive address like Google Maps
  static String _buildFullAddress(Map<String, dynamic> feature, List<dynamic> context) {
    String address = feature['place_name'] ?? '';
    String text = feature['text'] ?? '';
    
    // Remove "Philippines" from the end to keep it shorter
    if (address.endsWith(', Philippines')) {
      address = address.substring(0, address.length - 13);
    }
    
    // Return full address including place name for text field
    return address;
  }

  static Future<LatLng?> getCoordinatesFromAddress(String address, {LatLng? proximity}) async {
    final results = await searchAddresses(address, proximity: proximity);
    if (results.isNotEmpty) {
      return results.first.coordinates;
    }
    return null;
  }

  static Future<String?> getAddressFromCoordinates(LatLng coordinates) async {
    final String accessToken = _accessToken;
    final String url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/${coordinates.longitude},${coordinates.latitude}.json'
        '?access_token=$accessToken'
        '&limit=1'
        '&country=PH';  // Restrict to Philippines

    try {
      final response = await _client.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List features = data['features'];

        if (features.isNotEmpty) {
          return features.first['place_name'];
        }
      }
    } catch (e) {
      print('Error reverse geocoding Mapbox: $e');
    }
    return null;
  }
}
