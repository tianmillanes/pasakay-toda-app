import '../models/lat_lng.dart';
import 'package:geolocator/geolocator.dart';

/// Douglas-Peucker algorithm for polyline simplification
/// Reduces the number of points in a polyline while maintaining its shape
class PolylineSimplifier {
  /// Simplify a polyline using Douglas-Peucker algorithm
  /// 
  /// [points]: List of LatLng points to simplify
  /// [tolerance]: Maximum distance (in meters) a point can deviate from the line
  ///              Default: 10 meters (good for navigation)
  /// 
  /// Returns simplified list of points
  static List<LatLng> simplify(
    List<LatLng> points, {
    double tolerance = 10.0,
  }) {
    if (points.length <= 2) return points;

    // Find the point with the maximum distance from the line
    double maxDistance = 0;
    int maxIndex = 0;

    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], points[0], points[points.length - 1]);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    // If max distance is greater than tolerance, recursively simplify
    if (maxDistance > tolerance) {
      final leftSegment = simplify(
        points.sublist(0, maxIndex + 1),
        tolerance: tolerance,
      );
      final rightSegment = simplify(
        points.sublist(maxIndex),
        tolerance: tolerance,
      );

      // Combine results (remove duplicate point at maxIndex)
      return [...leftSegment.sublist(0, leftSegment.length - 1), ...rightSegment];
    } else {
      // Keep only start and end points
      return [points[0], points[points.length - 1]];
    }
  }

  /// Calculate perpendicular distance from a point to a line segment
  /// Returns distance in meters
  static double _perpendicularDistance(LatLng point, LatLng lineStart, LatLng lineEnd) {
    // Convert to approximate meters for calculation
    final A = point.latitude - lineStart.latitude;
    final B = point.longitude - lineStart.longitude;
    final C = lineEnd.latitude - lineStart.latitude;
    final D = lineEnd.longitude - lineStart.longitude;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;

    if (lenSq == 0) {
      // lineStart and lineEnd are the same point
      return _distanceInMeters(point, lineStart);
    }

    final param = dot / lenSq;
    final xx = lineStart.latitude + param * C;
    final yy = lineStart.longitude + param * D;

    return _distanceInMeters(point, LatLng(xx, yy));
  }

  /// Calculate distance between two points in meters
  static double _distanceInMeters(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// Simplify with adaptive tolerance based on zoom level
  /// Higher zoom = lower tolerance (more detail)
  /// Lower zoom = higher tolerance (less detail)
  static List<LatLng> simplifyAdaptive(
    List<LatLng> points, {
    double zoomLevel = 17.5,
  }) {
    // Adaptive tolerance: at zoom 17.5, use 10m; at zoom 15, use 30m
    final tolerance = 10.0 + (17.5 - zoomLevel) * 5.0;
    return simplify(points, tolerance: tolerance.clamp(5.0, 100.0));
  }

  /// Douglas-Peucker simplification with precise tolerance control
  /// This is an alias for the main simplify method with explicit naming
  static List<LatLng> simplifyDouglasPeucker(
    List<LatLng> points,
    double tolerance,
  ) {
    return simplify(points, tolerance: tolerance * 111320); // Convert degrees to meters approximately
  }
}
