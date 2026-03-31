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
  final String? barangayId;
  final String? barangayName;
  final int passengerCount; // Number of passengers (1-4)
  final bool isPasaBuy;
  final String? itemDescription;
  final DateTime? expiresAt;

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
    this.barangayId,
    this.barangayName,
    this.passengerCount = 1, // Default to 1 passenger
    this.isPasaBuy = false,
    this.itemDescription,
    this.expiresAt,
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
      status: _parseStatus(data['status']),
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
      barangayId: data['barangayId'],
      barangayName: data['barangayName'],
      passengerCount: data['passengerCount'] ?? 1,
      isPasaBuy: data['isPasaBuy'] ?? false,
      itemDescription: data['itemDescription'],
      expiresAt: data['expiresAt'] != null
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
    );
  }

  static RideStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
        return RideStatus.pending;
      case 'accepted':
        return RideStatus.accepted;
      case 'driverOnWay':
      case 'driver_on_way':
      case 'on_the_way':
      case 'onTheWay':
        return RideStatus.driverOnWay;
      case 'driverArrived':
      case 'driver_arrived':
      case 'arrived_pickup':
      case 'arrived':
        return RideStatus.driverArrived;
      case 'inProgress':
      case 'in_progress':
      case 'started':
      case 'onTrip':
        return RideStatus.inProgress;
      case 'completed':
        return RideStatus.completed;
      case 'cancelled':
      case 'canceled':
        return RideStatus.cancelled;
      case 'failed':
      case 'interrupted':
        return RideStatus.failed;
      default:
        return RideStatus.pending;
    }
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
      'barangayId': barangayId,
      'barangayName': barangayName,
      'passengerCount': passengerCount,
      'isPasaBuy': isPasaBuy,
      'itemDescription': itemDescription,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    };
  }

  RideModel copyWith({
    String? driverId,
    RideStatus? status,
    DateTime? acceptedAt,
    DateTime? startedAt,
    DateTime? completedAt,
    String? notes,
    bool? isPasaBuy,
    String? itemDescription,
    DateTime? expiresAt,
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
      barangayId: barangayId,
      barangayName: barangayName,
      isPasaBuy: isPasaBuy ?? this.isPasaBuy,
      itemDescription: itemDescription ?? this.itemDescription,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
