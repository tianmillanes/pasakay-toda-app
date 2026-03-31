import 'package:cloud_firestore/cloud_firestore.dart';

class GcashQrModel {
  final String id;
  final String qrImageUrl;
  final String accountName;
  final String accountNumber;
  final DateTime uploadedAt;
  final String uploadedBy;
  final String uploadedByName;
  final bool isActive;

  GcashQrModel({
    required this.id,
    required this.qrImageUrl,
    required this.accountName,
    required this.accountNumber,
    required this.uploadedAt,
    required this.uploadedBy,
    required this.uploadedByName,
    required this.isActive,
  });

  factory GcashQrModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GcashQrModel(
      id: doc.id,
      qrImageUrl: data['qrImageUrl'] ?? '',
      accountName: data['accountName'] ?? '',
      accountNumber: data['accountNumber'] ?? '',
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      uploadedBy: data['uploadedBy'] ?? '',
      uploadedByName: data['uploadedByName'] ?? '',
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'qrImageUrl': qrImageUrl,
      'accountName': accountName,
      'accountNumber': accountNumber,
      'uploadedAt': uploadedAt,
      'uploadedBy': uploadedBy,
      'uploadedByName': uploadedByName,
      'isActive': isActive,
    };
  }
}
