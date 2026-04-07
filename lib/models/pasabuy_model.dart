import 'package:cloud_firestore/cloud_firestore.dart';

enum PasaBuyStatus {
  pending,
  accepted,
  driver_going_to_pickup, // Driver heading to pickup location (to get money)
  driver_on_way, // Alias for driver_going_to_pickup (used in notification handlers)
  arrived_at_pickup, // Driver arrived at pickup location
  arrived_pickup, // Alias for arrived_at_pickup (used in notification handlers)
  driver_going_to_store, // Driver heading to store (to buy items)
  arrived_at_store, // Driver arrived at store
  delivery_in_progress, // Items bought, delivery started
  completed,
  cancelled,
}

class PasaBuyModel {
  final String id;
  final String passengerId;
  final String passengerName;
  final String passengerPhone;
  final GeoPoint pickupLocation; // Where driver gets money
  final String pickupAddress;
  final GeoPoint? storeLocation; // Where driver buys items (optional, can be same as pickup)
  final String? storeAddress;
  final GeoPoint dropoffLocation; // Where items are delivered
  final String dropoffAddress;
  final String itemDescription;
  final String itemQuantity;
  final double fare;
  final PasaBuyStatus status;
  final String? driverId;
  final String? driverName;
  final String? assignedDriverId; // Current assigned driver from queue
  final List<String> declinedBy; // Drivers who declined this request
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAtPickupAt;
  final DateTime? arrivedAtStoreAt;
  final DateTime? shoppingStartedAt;
  final DateTime? purchaseCompletedAt;
  final DateTime? deliveryStartedAt;
  final DateTime? completedAt;
  final List<Map<String, dynamic>> workflowLogs;
  final DateTime? expiresAt;
  final String? barangayId;
  final String? barangayName;
  final bool isRated;
  final double? rating;

  PasaBuyModel({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    required this.passengerPhone,
    required this.pickupLocation,
    required this.pickupAddress,
    this.storeLocation,
    this.storeAddress,
    required this.dropoffLocation,
    required this.dropoffAddress,
    required this.itemDescription,
    required this.itemQuantity,
    required this.fare,
    required this.status,
    this.driverId,
    this.driverName,
    this.assignedDriverId,
    this.declinedBy = const [],
    required this.createdAt,
    this.acceptedAt,
    this.arrivedAtPickupAt,
    this.arrivedAtStoreAt,
    this.shoppingStartedAt,
    this.purchaseCompletedAt,
    this.deliveryStartedAt,
    this.completedAt,
    this.expiresAt,
    this.barangayId,
    this.barangayName,
    this.workflowLogs = const [],
    this.isRated = false,
    this.rating,
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
      storeLocation: data['storeLocation'] as GeoPoint?,
      storeAddress: data['storeAddress'],
      dropoffLocation: data['dropoffLocation'] as GeoPoint,
      dropoffAddress: data['dropoffAddress'] ?? '',
      itemDescription: data['itemDescription'] ?? '',
      itemQuantity: data['itemQuantity'] ?? '1',
      fare: (data['fare'] ?? data['budget'] ?? 0.0).toDouble(),
      status: _parseStatus(data['status']),
      driverId: data['driverId'],
      driverName: data['driverName'],
      assignedDriverId: data['assignedDriverId'],
      declinedBy: List<String>.from(data['declinedBy'] as List? ?? []),
      createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
      acceptedAt: data['acceptedAt'] != null ? (data['acceptedAt'] as Timestamp).toDate() : null,
      arrivedAtPickupAt: data['arrivedAtPickupAt'] != null ? (data['arrivedAtPickupAt'] as Timestamp).toDate() : null,
      arrivedAtStoreAt: data['arrivedAtStoreAt'] != null ? (data['arrivedAtStoreAt'] as Timestamp).toDate() : null,
      shoppingStartedAt: data['shoppingStartedAt'] != null ? (data['shoppingStartedAt'] as Timestamp).toDate() : null,
      purchaseCompletedAt: data['purchaseCompletedAt'] != null ? (data['purchaseCompletedAt'] as Timestamp).toDate() : null,
      deliveryStartedAt: data['deliveryStartedAt'] != null ? (data['deliveryStartedAt'] as Timestamp).toDate() : null,
      completedAt: data['completedAt'] != null ? (data['completedAt'] as Timestamp).toDate() : null,
      expiresAt: data['expiresAt'] != null ? (data['expiresAt'] as Timestamp).toDate() : null,
      barangayId: data['barangayId'],
      barangayName: data['barangayName'],
      workflowLogs: List<Map<String, dynamic>>.from(data['workflowLogs'] ?? []),
      isRated: data['isRated'] ?? false,
      rating: data['rating'] != null ? (data['rating'] as num).toDouble() : null,
    );
  }

  static PasaBuyStatus _parseStatus(String? status) {
    switch (status) {
      case 'accepted':
        return PasaBuyStatus.accepted;
      case 'driver_going_to_pickup':
        return PasaBuyStatus.driver_going_to_pickup;
      case 'arrived_at_pickup':
        return PasaBuyStatus.arrived_at_pickup;
      case 'driver_going_to_store':
        return PasaBuyStatus.driver_going_to_store;
      case 'arrived_at_store':
        return PasaBuyStatus.arrived_at_store;
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
      'storeLocation': storeLocation,
      'storeAddress': storeAddress,
      'dropoffLocation': dropoffLocation,
      'dropoffAddress': dropoffAddress,
      'itemDescription': itemDescription,
      'itemQuantity': itemQuantity,
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
      'isRated': isRated,
      if (rating != null) 'rating': rating,
    };
  }

  PasaBuyModel copyWith({
    String? driverId,
    String? driverName,
    String? assignedDriverId,
    List<String>? declinedBy,
    PasaBuyStatus? status,
    DateTime? acceptedAt,
    DateTime? arrivedAtPickupAt,
    DateTime? arrivedAtStoreAt,
    DateTime? completedAt,
    DateTime? expiresAt,
    bool? isRated,
    double? rating,
  }) {
    return PasaBuyModel(
      id: id,
      passengerId: passengerId,
      passengerName: passengerName,
      passengerPhone: passengerPhone,
      pickupLocation: pickupLocation,
      pickupAddress: pickupAddress,
      storeLocation: storeLocation,
      storeAddress: storeAddress,
      dropoffLocation: dropoffLocation,
      dropoffAddress: dropoffAddress,
      itemDescription: itemDescription,
      itemQuantity: itemQuantity,
      fare: fare,
      status: status ?? this.status,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      assignedDriverId: assignedDriverId ?? this.assignedDriverId,
      declinedBy: declinedBy ?? this.declinedBy,
      createdAt: createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      arrivedAtPickupAt: arrivedAtPickupAt ?? this.arrivedAtPickupAt,
      arrivedAtStoreAt: arrivedAtStoreAt ?? this.arrivedAtStoreAt,
      completedAt: completedAt ?? this.completedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      barangayId: barangayId,
      barangayName: barangayName,
      isRated: isRated ?? this.isRated,
      rating: rating ?? this.rating,
    );
  }
}
