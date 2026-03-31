import 'package:cloud_firestore/cloud_firestore.dart';

class BarangayModel {
  final String id;
  final String name;
  final String municipality;
  final String province;
  final GeoPoint? centerLocation;
  final double? latitude;
  final double? longitude;
  final String? adminId;
  final int totalDrivers;
  final int totalPassengers;
  final DateTime createdAt;
  final bool isActive;
  final List<List<double>>? geofenceCoordinates;
  final List<List<double>>? terminalGeofenceCoordinates;

  BarangayModel({
    required this.id,
    required this.name,
    required this.municipality,
    required this.province,
    this.centerLocation,
    this.latitude,
    this.longitude,
    this.adminId,
    this.totalDrivers = 0,
    this.totalPassengers = 0,
    required this.createdAt,
    this.isActive = true,
    this.geofenceCoordinates,
    this.terminalGeofenceCoordinates,
  });

  factory BarangayModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    
    // Parse geofence coordinates if available
    List<List<double>>? geofenceCoords;
    if (data['geofenceCoordinates'] is List) {
      geofenceCoords = (data['geofenceCoordinates'] as List).map((coord) {
        if (coord is Map) {
          return [
            (coord['lat'] as num).toDouble(),
            (coord['lng'] as num).toDouble(),
          ];
        }
        return [0.0, 0.0];
      }).toList();
    }
    
    // Parse terminal geofence coordinates if available
    List<List<double>>? terminalGeofenceCoords;
    if (data['terminalGeofenceCoordinates'] is List) {
      terminalGeofenceCoords = (data['terminalGeofenceCoordinates'] as List).map((coord) {
        if (coord is Map) {
          return [
            (coord['lat'] as num).toDouble(),
            (coord['lng'] as num).toDouble(),
          ];
        }
        return [0.0, 0.0];
      }).toList();
    }
    
    return BarangayModel(
      id: doc.id,
      name: data['name'] ?? '',
      municipality: data['municipality'] ?? '',
      province: data['province'] ?? '',
      centerLocation: data['centerLocation'] as GeoPoint?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      adminId: data['adminId'],
      totalDrivers: data['totalDrivers'] ?? 0,
      totalPassengers: data['totalPassengers'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isActive: data['isActive'] ?? true,
      geofenceCoordinates: geofenceCoords,
      terminalGeofenceCoordinates: terminalGeofenceCoords,
    );
  }

  Map<String, dynamic> toFirestore() {
    // Convert geofence coordinates to map format for Firestore
    List<Map<String, double>>? geofenceMaps;
    if (geofenceCoordinates != null) {
      geofenceMaps = geofenceCoordinates!.map((coord) => {
        'lat': coord[0],
        'lng': coord[1],
      }).toList();
    }
    
    // Convert terminal geofence coordinates to map format for Firestore
    List<Map<String, double>>? terminalGeofenceMaps;
    if (terminalGeofenceCoordinates != null) {
      terminalGeofenceMaps = terminalGeofenceCoordinates!.map((coord) => {
        'lat': coord[0],
        'lng': coord[1],
      }).toList();
    }
    
    return {
      'name': name,
      'municipality': municipality,
      'province': province,
      'centerLocation': centerLocation,
      'latitude': latitude,
      'longitude': longitude,
      'adminId': adminId,
      'totalDrivers': totalDrivers,
      'totalPassengers': totalPassengers,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      'geofenceCoordinates': geofenceMaps,
      'terminalGeofenceCoordinates': terminalGeofenceMaps,
    };
  }

  BarangayModel copyWith({
    String? name,
    String? municipality,
    String? province,
    GeoPoint? centerLocation,
    double? latitude,
    double? longitude,
    String? adminId,
    int? totalDrivers,
    int? totalPassengers,
    bool? isActive,
    List<List<double>>? geofenceCoordinates,
    List<List<double>>? terminalGeofenceCoordinates,
  }) {
    return BarangayModel(
      id: id,
      name: name ?? this.name,
      municipality: municipality ?? this.municipality,
      province: province ?? this.province,
      centerLocation: centerLocation ?? this.centerLocation,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      adminId: adminId ?? this.adminId,
      totalDrivers: totalDrivers ?? this.totalDrivers,
      totalPassengers: totalPassengers ?? this.totalPassengers,
      createdAt: createdAt,
      isActive: isActive ?? this.isActive,
      geofenceCoordinates: geofenceCoordinates ?? this.geofenceCoordinates,
      terminalGeofenceCoordinates: terminalGeofenceCoordinates ?? this.terminalGeofenceCoordinates,
    );
  }
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BarangayModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
