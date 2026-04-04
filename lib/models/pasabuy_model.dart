import 'package:cloud_firestore/cloud_firestore.dart';

enum PasaBuyStatus {
  pending,
  accepted,
  driver_on_way, // Driver is heading to the store
  arrived_pickup, // Driver arrived at store/pickup
  delivery_in_progress, // Items bought, delivery started
  completed,
  cancelled,
}

class PasaBuyModel {
  final String id;
  final String passengerId;
  final String passengerName;
  final String passengerPhone;
  final GeoPoint pickupLocation;
  final String pickupAddress;
  final GeoPoint dropoffLocation;
  final String dropoffAddress;
  final String itemDescription;
  final double fare;
  final PasaBuyStatus status;
  final String? driverId;
  final String? driverName;
  final String? assignedDriverId; // Current assigned driver from queue
  final List<String> declinedBy; // Drivers who declined this request
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAtPickupAt;
  final DateTime? shoppingStartedAt;
  final DateTime? purchaseCompletedAt;
  final DateTime? deliveryStartedAt;
  final DateTime? completedAt;
  final List<Map<String, dynamic>> workflowLogs;
  final DateTime? expiresAt;
  final String? barangayId;
  final String? barangayName;

  PasaBuyModel({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.passengerPhone,
    required this.pickupLocation,
    required this.pickupAddress,
    required this.dropoffLocation,
    required this.dropoffAddress,
    required this.itemDescription,
    required this.fare,
    required this.status,
    this.driverId,
    this.driverName,
    this.assignedDriverId,
    this.declinedBy = const [],
    required this.createdAt,
    this.acceptedAt,
    this.arrivedAtPickupAt,
    this.shoppingStartedAt,
    this.purchaseCompletedAt,
    this.deliveryStartedAt,
    this.completedAt,
    this.expiresAt,
    this.barangayId,
    this.barangayName,
    this.workflowLogs = const [],
  });

  factory PasaBuyModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    
    return PasaBuyModel(
      id: doc.id,
      passengerId: data['passengerId'] ?? '',
      passengerName: data['passengerName'] ?? '',
      passengerPhone: data['passengerPhone'] ?? '',
      pickupLocation: data['pickupLocation'] as GeoPoint,
      pickupAddress: data['pickupAddress'] ?? '',
      dropoffLocation: data['dropoffLocation'] as GeoPoint,
      dropoffAddress: data['dropoffAddress'] ?? '',
      itemDescription: data['itemDescription'] ?? '',
      fare: (data['fare'] ?? data['budget'] ?? 0.0).toDouble(),
      status: _parseStatus(data['status']),
      driverId: data['driverId'],
      driverName: data['driverName'],
      assignedDriverId: data['assignedDriverId'],
      declinedBy: List<String>.from(data['declinedBy'] as List? ?? []),
      createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
      acceptedAt: data['acceptedAt'] != null ? (data['acceptedAt'] as Timestamp).toDate() : null,
      arrivedAtPickupAt: data['arrivedAtPickupAt'] != null ? (data['arrivedAtPickupAt'] as Timestamp).toDate() : null,
      shoppingStartedAt: data['shoppingStartedAt'] != null ? (data['shoppingStartedAt'] as Timestamp).toDate() : null,
      purchaseCompletedAt: data['purchaseCompletedAt'] != null ? (data['purchaseCompletedAt'] as Timestamp).toDate() : null,
      deliveryStartedAt: data['deliveryStartedAt'] != null ? (data['deliveryStartedAt'] as Timestamp).toDate() : null,
      completedAt: data['completedAt'] != null ? (data['completedAt'] as Timestamp).toDate() : null,
      expiresAt: data['expiresAt'] != null ? (data['expiresAt'] as Timestamp).toDate() : null,
      barangayId: data['barangayId'],
      barangayName: data['barangayName'],
      workflowLogs: List<Map<String, dynamic>>.from(data['workflowLogs'] ?? []),
    );
  }

  static PasaBuyStatus _parseStatus(String? status) {
    switch (status) {
      case 'accepted':
        return PasaBuyStatus.accepted;
      case 'driver_on_way':
        return PasaBuyStatus.driver_on_way;
      case 'arrived_pickup':
        return PasaBuyStatus.arrived_pickup;
      case 'delivery_in_progress':
        return PasaBuyStatus.delivery_in_progress;
      case 'completed':
        return PasaBuyStatus.completed;
      case 'cancelled':
        return PasaBuyStatus.cancelled;
      default:
        return PasaBuyStatus.pending;
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'pickupLocation': pickupLocation,
      'pickupAddress': pickupAddress,
      'dropoffLocation': dropoffLocation,
      'dropoffAddress': dropoffAddress,
      'itemDescription': itemDescription,
      'fare': fare,
      'status': status.toString().split('.').last,
      'driverId': driverId,
      'driverName': driverName,
      'assignedDriverId': assignedDriverId,
      'declinedBy': declinedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
      'barangayId': barangayId,
      'barangayName': barangayName,
    };
  }

  PasaBuyModel copyWith({
    String? driverId,
    String? driverName,
    String? assignedDriverId,
    List<String>? declinedBy,
    PasaBuyStatus? status,
    DateTime? acceptedAt,
    DateTime? completedAt,
    DateTime? expiresAt,
  }) {
    return PasaBuyModel(
      id: id,
      passengerId: passengerId,
      passengerName: passengerName,
      passengerPhone: passengerPhone,
      pickupLocation: pickupLocation,
      pickupAddress: pickupAddress,
      dropoffLocation: dropoffLocation,
      dropoffAddress: dropoffAddress,
      itemDescription: itemDescription,
      fare: fare,
      status: status ?? this.status,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      assignedDriverId: assignedDriverId ?? this.assignedDriverId,
      declinedBy: declinedBy ?? this.declinedBy,
      createdAt: createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      completedAt: completedAt ?? this.completedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      barangayId: barangayId,
      barangayName: barangayName,
    );
  }
}
