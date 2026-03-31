import '../models/lat_lng.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class PolylineDecoder {
  /// Decode Mapbox polyline (GeoJSON LineString) into list of LatLng points
  /// Mapbox uses standard GeoJSON coordinates: [lng, lat]
  static List<LatLng> decodeGeoJsonLine(List<dynamic> coordinates) {
    final points = <LatLng>[];
    
    for (final coord in coordinates) {
      if (coord is List && coord.length >= 2) {
        final lng = coord[0].toDouble();
        final lat = coord[1].toDouble();
        points.add(LatLng(lat, lng));
      }
    }
    
    return points;
  }

  /// Decode Mapbox geometry from Directions API response
  /// Returns list of LatLng points for the route
  static List<LatLng> decodeMapboxGeometry(Map<String, dynamic> geometry) {
    if (geometry['type'] != 'LineString') {
      return [];
    }
    
    final coordinates = geometry['coordinates'] as List<dynamic>?;
    if (coordinates == null || coordinates.isEmpty) {
      return [];
    }
    
    return decodeGeoJsonLine(coordinates);
  }

  /// Decode polyline string (default format from Mapbox)
  /// Uses the standard Google Polyline Algorithm (Encoded Polyline Algorithm Format)
  static List<LatLng> decodePolyline(String polyline) {
    if (polyline.isEmpty) return [];
    
    final points = <LatLng>[];
    int index = 0;
    int len = polyline.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = polyline.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    
    return points;
  }

  /// Convert LatLng points to Mapbox Position list for LineAnnotation
  static List<mapbox.Position> toMapboxPositions(List<LatLng> points) {
    return points
        .map((point) => mapbox.Position(point.longitude, point.latitude))
        .toList();
  }
}
