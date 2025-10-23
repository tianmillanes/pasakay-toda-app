import 'package:cloud_firestore/cloud_firestore.dart';

enum RideStatus {
  pending,
  accepted,
  driverOnWay,
  driverArrived,
  inProgress,
  completed,
  cancelled,
  failed,
}

class RideModel {
  final String id;
  final String passengerId;
  final String? driverId;
  final String? assignedDriverId;
  final GeoPoint pickupLocation;
  final GeoPoint dropoffLocation;
  final String pickupAddress;
  final String dropoffAddress;
  final RideStatus status;
  final double fare;
  final int estimatedDuration; // in minutes
  final double? distance; // in kilometers
  final DateTime requestedAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? notes;

  RideModel({
    required this.id,
    required this.passengerId,
    this.driverId,
    this.assignedDriverId,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.pickupAddress,
    required this.dropoffAddress,
    this.status = RideStatus.pending,
    required this.fare,
    required this.estimatedDuration,
    this.distance,
    required this.requestedAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.notes,
  });

  factory RideModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Safely handle GeoPoint with null checks and default values
    GeoPoint pickupGeoPoint;
    if (data['pickupLocation'] != null && data['pickupLocation'] is GeoPoint) {
      pickupGeoPoint = data['pickupLocation'] as GeoPoint;
    } else {
      // Default to Tarlac City coordinates if null
      pickupGeoPoint = const GeoPoint(15.4817, 120.5979);
    }

    GeoPoint dropoffGeoPoint;
    if (data['dropoffLocation'] != null &&
        data['dropoffLocation'] is GeoPoint) {
      dropoffGeoPoint = data['dropoffLocation'] as GeoPoint;
    } else {
      // Default to Tarlac City coordinates if null
      dropoffGeoPoint = const GeoPoint(15.4817, 120.5979);
    }

    return RideModel(
      id: doc.id,
      passengerId: data['passengerId'] ?? '',
      driverId: data['driverId'],
      assignedDriverId: data['assignedDriverId'],
      pickupLocation: pickupGeoPoint,
      dropoffLocation: dropoffGeoPoint,
      pickupAddress: data['pickupAddress'] ?? '',
      dropoffAddress: data['dropoffAddress'] ?? '',
      status: RideStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => RideStatus.pending,
      ),
      fare: (data['fare'] ?? 0.0).toDouble(),
      estimatedDuration: data['estimatedDuration'] ?? 0,
      distance: data['distance']?.toDouble(),
      requestedAt:
          (data['requestedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      acceptedAt: data['acceptedAt'] != null
          ? (data['acceptedAt'] as Timestamp).toDate()
          : null,
      startedAt: data['startedAt'] != null
          ? (data['startedAt'] as Timestamp).toDate()
          : null,
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
      notes: data['notes'],
    );
  }

  String? get passengerName => null;

  Map<String, dynamic> toFirestore() {
    return {
      'passengerId': passengerId,
      'driverId': driverId,
      'assignedDriverId': assignedDriverId,
      'pickupLocation': pickupLocation,
      'dropoffLocation': dropoffLocation,
      'pickupAddress': pickupAddress,
      'dropoffAddress': dropoffAddress,
      'status': status.toString().split('.').last,
      'fare': fare,
      'estimatedDuration': estimatedDuration,
      'distance': distance,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'completedAt': completedAt != null
          ? Timestamp.fromDate(completedAt!)
          : null,
      'notes': notes,
    };
  }

  RideModel copyWith({
    String? driverId,
    RideStatus? status,
    DateTime? acceptedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? notes,
  }) {
    return RideModel(
      id: id,
      passengerId: passengerId,
      driverId: driverId ?? this.driverId,
      pickupLocation: pickupLocation,
      dropoffLocation: dropoffLocation,
      pickupAddress: pickupAddress,
      dropoffAddress: dropoffAddress,
      status: status ?? this.status,
      fare: fare,
      estimatedDuration: estimatedDuration,
      requestedAt: requestedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
    );
  }
}
