import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../models/lat_lng.dart';
import '../config/credentials_config.dart';

class OfflineMapService {
  static final OfflineMapService _instance = OfflineMapService._internal();
  factory OfflineMapService() => _instance;
  OfflineMapService._internal();

  Directory? _offlineDir;
  final Map<String, dynamic> _cachedTiles = {};

  Future<void> initialize() async {
    if (kIsWeb) {
      print('ℹ️  Offline maps not supported on web platform');
      return;
    }
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _offlineDir = Directory('${appDir.path}/offline_maps');
      
      if (!await _offlineDir!.exists()) {
        await _offlineDir!.create(recursive: true);
      }
      
      print('📁 Offline maps directory initialized: ${_offlineDir!.path}');
    } catch (e) {
      print('❌ Error initializing offline maps: $e');
    }
  }

  Future<bool> isAreaCached(LatLng center, double radiusKm) async {
    if (kIsWeb) return false;
    if (_offlineDir == null) return false;

    final cacheKey = _generateCacheKey(center, radiusKm);
    return _cachedTiles.containsKey(cacheKey);
  }

  Future<void> cacheMapArea(LatLng center, double radiusKm) async {
    if (kIsWeb) {
      print('ℹ️  Offline map caching not supported on web platform');
      return;
    }
    
    if (_offlineDir == null) {
      await initialize();
    }

    try {
      final cacheKey = _generateCacheKey(center, radiusKm);
      
      // Check if already cached
      if (_cachedTiles.containsKey(cacheKey)) {
        print('📍 Area already cached: $cacheKey');
        return;
      }

      print('🗺️  Caching map area around ${center.latitude}, ${center.longitude}');
      
      // For now, we'll simulate caching with basic tile data
      // In a real implementation, you would download Mapbox vector tiles
      final cacheData = {
        'center': {
          'lat': center.latitude,
          'lng': center.longitude,
        },
        'radiusKm': radiusKm,
        'cachedAt': DateTime.now().toIso8601String(),
        'tileCount': 100, // Simulated
      };

      // Save to file
      final file = File('${_offlineDir!.path}/$cacheKey.json');
      await file.writeAsString(json.encode(cacheData));
      
      // Update memory cache
      _cachedTiles[cacheKey] = cacheData;
      
      print('✅ Map area cached successfully: $cacheKey');
    } catch (e) {
      print('❌ Error caching map area: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getCachedAreas() async {
    if (kIsWeb) return [];
    
    if (_offlineDir == null) await initialize();

    try {
      final files = await _offlineDir!.list().toList();
      final areas = <Map<String, dynamic>>[];

      for (final file in files) {
        if (file is File && file.path.endsWith('.json')) {
          final content = await file.readAsString();
          final data = json.decode(content) as Map<String, dynamic>;
          
          areas.add({
            'file': file.path,
            'data': data,
            'sizeBytes': await file.length(),
          });
        }
      }

      return areas;
    } catch (e) {
      print('❌ Error getting cached areas: $e');
      return [];
    }
  }

  Future<void> clearCache() async {
    if (kIsWeb) {
      print('ℹ️  Offline map cache clearing not supported on web platform');
      return;
    }
    
    if (_offlineDir == null) return;

    try {
      if (await _offlineDir!.exists()) {
        await _offlineDir!.delete(recursive: true);
        await _offlineDir!.create(recursive: true);
      }
      
      _cachedTiles.clear();
      print('🗑️  Offline map cache cleared');
    } catch (e) {
      print('❌ Error clearing cache: $e');
    }
  }

  Future<int> getCacheSize() async {
    if (kIsWeb) return 0;
    
    if (_offlineDir == null) return 0;

    try {
      int totalSize = 0;
      await for (final entity in _offlineDir!.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      print('❌ Error calculating cache size: $e');
      return 0;
    }
  }

  String _generateCacheKey(LatLng center, double radiusKm) {
    final lat = center.latitude.toStringAsFixed(4);
    final lng = center.longitude.toStringAsFixed(4);
    final radius = radiusKm.toStringAsFixed(1);
    return '${lat}_${lng}_${radius}km';
  }

  String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Check if device has sufficient storage for offline maps
  Future<bool> hasSufficientStorage(int requiredBytes) async {
    if (kIsWeb) return true; // Assume sufficient storage on web
    
    try {
      // This is a simplified check - in reality you'd need to query free disk space
      // For now, we'll assume there's enough space if less than 100MB is required
      return requiredBytes < 100 * 1024 * 1024; // 100MB limit
    } catch (e) {
      print('❌ Error checking storage: $e');
      return false;
    }
  }

  // Preload common areas (like city centers)
  Future<void> preloadCommonAreas() async {
    if (kIsWeb) {
      print('ℹ️  Offline map preloading not supported on web platform');
      return;
    }
    
    final commonAreas = [
      LatLng(15.4806, 120.6571), // Tarlac City
      LatLng(14.5995, 120.9842), // Manila
      LatLng(10.3157, 123.8854), // Cebu City
      LatLng(7.0731, 125.6128), // Davao City
    ];

    for (final area in commonAreas) {
      await cacheMapArea(area, 10.0); // 10km radius
    }
  }
}
