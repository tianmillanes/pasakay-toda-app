import 'dart:async';
import 'dart:collection';

/// Simple in-memory cache for API responses
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final Map<String, _CacheEntry> _cache = {};
  static const Duration _defaultExpiration = Duration(minutes: 5);

  /// Store data in cache with optional expiration time
  void put<T>(String key, T data, {Duration? expiration}) {
    _cache[key] = _CacheEntry<T>(
      data: data,
      timestamp: DateTime.now(),
      expiration: expiration ?? _defaultExpiration,
    );
  }

  /// Retrieve data from cache if not expired
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (DateTime.now().difference(entry.timestamp) > entry.expiration) {
      _cache.remove(key);
      return null;
    }

    return entry.data as T?;
  }

  /// Check if key exists and is not expired
  bool contains(String key) {
    final entry = _cache[key];
    if (entry == null) return false;

    if (DateTime.now().difference(entry.timestamp) > entry.expiration) {
      _cache.remove(key);
      return false;
    }

    return true;
  }

  /// Remove specific entry from cache
  void remove(String key) {
    _cache.remove(key);
  }

  /// Clear all cache entries
  void clear() {
    _cache.clear();
  }

  /// Clear expired entries
  void clearExpired() {
    final now = DateTime.now();
    _cache.removeWhere((key, entry) {
      return now.difference(entry.timestamp) > entry.expiration;
    });
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    int expiredCount = 0;
    int validCount = 0;

    for (final entry in _cache.values) {
      if (now.difference(entry.timestamp) > entry.expiration) {
        expiredCount++;
      } else {
        validCount++;
      }
    }

    return {
      'total': _cache.length,
      'valid': validCount,
      'expired': expiredCount,
    };
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  final Duration expiration;

  _CacheEntry({
    required this.data,
    required this.timestamp,
    required this.expiration,
  });
}
