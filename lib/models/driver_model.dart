import 'package:cloud_firestore/cloud_firestore.dart';

enum DriverStatus { offline, available, busy, onTrip }

class DriverModel {
  final String id;
  final String userId;
  final String name;
  final String vehicleType;
  final String plateNumber;
  final String licenseNumber;
  final DriverStatus status;
  final GeoPoint? currentLocation;
  final DateTime? lastLocationUpdate;
  final bool isInQueue;
  final int queuePosition;
  final bool isApproved;
  final DateTime? approvedAt;
  final String? approvedBy;

  DriverModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.vehicleType,
    required this.plateNumber,
    required this.licenseNumber,
    this.status = DriverStatus.offline,
    this.currentLocation,
    this.lastLocationUpdate,
    this.isInQueue = false,
    this.queuePosition = 0,
    this.isApproved = false,
    this.approvedAt,
    this.approvedBy,
  });

  factory DriverModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DriverModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      name: data['name'] ?? '',
      vehicleType: data['vehicleType'] ?? '',
      plateNumber: data['plateNumber'] ?? '',
      licenseNumber: data['licenseNumber'] ?? '',
      status: DriverStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => DriverStatus.offline,
      ),
      currentLocation: data['currentLocation'] as GeoPoint?,
      lastLocationUpdate: data['lastLocationUpdate'] != null
          ? (data['lastLocationUpdate'] as Timestamp).toDate()
          : null,
      isInQueue: data['isInQueue'] ?? false,
      queuePosition: data['queuePosition'] ?? 0,
      isApproved: data['isApproved'] ?? false,
      approvedAt: data['approvedAt'] != null
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
      approvedBy: data['approvedBy'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'vehicleType': vehicleType,
      'plateNumber': plateNumber,
      'licenseNumber': licenseNumber,
      'status': status.toString().split('.').last,
      'currentLocation': currentLocation,
      'lastLocationUpdate': lastLocationUpdate != null
          ? Timestamp.fromDate(lastLocationUpdate!)
          : null,
      'isInQueue': isInQueue,
      'queuePosition': queuePosition,
      'isApproved': isApproved,
      'approvedAt': approvedAt != null
          ? Timestamp.fromDate(approvedAt!)
          : null,
      'approvedBy': approvedBy,
    };
  }

  DriverModel copyWith({
    String? name,
    String? vehicleType,
    String? plateNumber,
    String? licenseNumber,
    DriverStatus? status,
    GeoPoint? currentLocation,
    DateTime? lastLocationUpdate,
    bool? isInQueue,
    int? queuePosition,
    bool? isApproved,
    DateTime? approvedAt,
    String? approvedBy,
  }) {
    return DriverModel(
      id: id,
      userId: userId,
      name: name ?? this.name,
      vehicleType: vehicleType ?? this.vehicleType,
      plateNumber: plateNumber ?? this.plateNumber,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      status: status ?? this.status,
      currentLocation: currentLocation ?? this.currentLocation,
      lastLocationUpdate: lastLocationUpdate ?? this.lastLocationUpdate,
      isInQueue: isInQueue ?? this.isInQueue,
      queuePosition: queuePosition ?? this.queuePosition,
      isApproved: isApproved ?? this.isApproved,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
    );
  }
}
