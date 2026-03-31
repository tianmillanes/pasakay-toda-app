import 'package:cloud_firestore/cloud_firestore.dart';

enum DriverStatus { offline, available, busy, onTrip }

class DriverModel {
  final String id;
  final String userId;
  final String name;
  final String vehicleType;
  final String plateNumber;
  final String licenseNumber;
  final String? plateNumberImageUrl; // Image URL for plate number verification
  final String? licenseNumberImageUrl; // Image URL for license number verification
  final String? tricyclePlateNumber; // Actual tricycle plate number from input
  final String? driverLicenseNumber; // Actual driver license number from input
  final String barangayId; // Barangay where driver operates
  final String barangayName;
  final DriverStatus status;
  final GeoPoint? currentLocation;
  final DateTime? lastLocationUpdate;
  final bool isInQueue;
  final int queuePosition;
  final bool isApproved;
  final DateTime? approvedAt;
  final String? approvedBy;
  final DateTime? rejectedAt;
  final String? rejectedBy;
  final bool isActive;
  final bool isPaid;
  final DateTime? lastPaidAt;
  final String? paidBy;
  final String? paymentProofImageBase64; // Proof of payment image (base64)
  final DateTime? paymentProofUploadedAt;

  DriverModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.vehicleType,
    required this.plateNumber,
    required this.licenseNumber,
    required this.barangayId,
    required this.barangayName,
    this.plateNumberImageUrl,
    this.licenseNumberImageUrl,
    this.tricyclePlateNumber,
    this.driverLicenseNumber,
    this.status = DriverStatus.offline,
    this.currentLocation,
    this.lastLocationUpdate,
    this.isInQueue = false,
    this.queuePosition = 0,
    this.isApproved = false,
    this.approvedAt,
    this.approvedBy,
    this.rejectedAt,
    this.rejectedBy,
    this.isActive = true,
    this.isPaid = false,
    this.lastPaidAt,
    this.paidBy,
    this.paymentProofImageBase64,
    this.paymentProofUploadedAt,
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
      barangayId: data['barangayId'] ?? '',
      barangayName: data['barangayName'] ?? '',
      plateNumberImageUrl: data['plateNumberImageUrl'],
      licenseNumberImageUrl: data['licenseNumberImageUrl'],
      tricyclePlateNumber: data['tricyclePlateNumber'],
      driverLicenseNumber: data['driverLicenseNumber'],
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
      rejectedAt: data['rejectedAt'] != null
          ? (data['rejectedAt'] as Timestamp).toDate()
          : null,
      rejectedBy: data['rejectedBy'],
      isActive: data['isActive'] ?? true,
      isPaid: data['isPaid'] ?? false,
      lastPaidAt: data['lastPaidAt'] != null
          ? (data['lastPaidAt'] as Timestamp).toDate()
          : null,
      paidBy: data['paidBy'],
      paymentProofImageBase64: data['paymentProofImageBase64'],
      paymentProofUploadedAt: data['paymentProofUploadedAt'] != null
          ? (data['paymentProofUploadedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    final data = <String, dynamic>{
      'userId': userId,
      'name': name,
      'vehicleType': vehicleType,
      'plateNumber': plateNumber,
      'licenseNumber': licenseNumber,
      'barangayId': barangayId,
      'barangayName': barangayName,
      'status': status.toString().split('.').last,
      'isInQueue': isInQueue,
      'queuePosition': queuePosition,
      'isApproved': isApproved,
      'isActive': isActive,
      'isPaid': isPaid,
    };

    // Only add optional fields if they have values
    if (plateNumberImageUrl != null) data['plateNumberImageUrl'] = plateNumberImageUrl;
    if (licenseNumberImageUrl != null) data['licenseNumberImageUrl'] = licenseNumberImageUrl;
    if (tricyclePlateNumber != null) data['tricyclePlateNumber'] = tricyclePlateNumber;
    if (driverLicenseNumber != null) data['driverLicenseNumber'] = driverLicenseNumber;
    if (currentLocation != null) data['currentLocation'] = currentLocation;
    if (lastLocationUpdate != null) data['lastLocationUpdate'] = Timestamp.fromDate(lastLocationUpdate!);
    if (approvedAt != null) data['approvedAt'] = Timestamp.fromDate(approvedAt!);
    if (approvedBy != null) data['approvedBy'] = approvedBy;
    if (rejectedAt != null) data['rejectedAt'] = Timestamp.fromDate(rejectedAt!);
    if (rejectedBy != null) data['rejectedBy'] = rejectedBy;
    if (lastPaidAt != null) data['lastPaidAt'] = Timestamp.fromDate(lastPaidAt!);
    if (paidBy != null) data['paidBy'] = paidBy;
    if (paymentProofImageBase64 != null) data['paymentProofImageBase64'] = paymentProofImageBase64;
    if (paymentProofUploadedAt != null) data['paymentProofUploadedAt'] = Timestamp.fromDate(paymentProofUploadedAt!);

    return data;
  }

  DriverModel copyWith({
    String? name,
    String? vehicleType,
    String? plateNumber,
    String? licenseNumber,
    String? tricyclePlateNumber,
    String? driverLicenseNumber,
    DriverStatus? status,
    GeoPoint? currentLocation,
    DateTime? lastLocationUpdate,
    bool? isInQueue,
    int? queuePosition,
    bool? isApproved,
    DateTime? approvedAt,
    String? approvedBy,
    DateTime? rejectedAt,
    String? rejectedBy,
    bool? isActive,
    bool? isPaid,
    DateTime? lastPaidAt,
    String? paidBy,
  }) {
    return DriverModel(
      id: id,
      userId: userId,
      name: name ?? this.name,
      vehicleType: vehicleType ?? this.vehicleType,
      plateNumber: plateNumber ?? this.plateNumber,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      tricyclePlateNumber: tricyclePlateNumber ?? this.tricyclePlateNumber,
      driverLicenseNumber: driverLicenseNumber ?? this.driverLicenseNumber,
      barangayId: barangayId,
      barangayName: barangayName,
      status: status ?? this.status,
      currentLocation: currentLocation ?? this.currentLocation,
      lastLocationUpdate: lastLocationUpdate ?? this.lastLocationUpdate,
      isInQueue: isInQueue ?? this.isInQueue,
      queuePosition: queuePosition ?? this.queuePosition,
      isApproved: isApproved ?? this.isApproved,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      rejectedBy: rejectedBy ?? this.rejectedBy,
      isActive: isActive ?? this.isActive,
      isPaid: isPaid ?? this.isPaid,
      lastPaidAt: lastPaidAt ?? this.lastPaidAt,
      paidBy: paidBy ?? this.paidBy,
    );
  }
}
