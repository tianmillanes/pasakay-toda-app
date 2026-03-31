import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { passenger, driver, admin }

enum IdVerificationStatus { notSubmitted, pending, approved, rejected }

class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final String barangayId;
  final String barangayName;
  final DateTime createdAt;
  final bool isActive;
  // ID Verification fields
  final String? idType;
  final String? idImageUrl;
  final String? selfieUrl;
  final IdVerificationStatus idVerificationStatus;
  final String? idVerificationNote;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.barangayId,
    required this.barangayName,
    required this.createdAt,
    this.isActive = true,
    this.idType,
    this.idImageUrl,
    this.selfieUrl,
    this.idVerificationStatus = IdVerificationStatus.notSubmitted,
    this.idVerificationNote,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == data['role'],
        orElse: () => UserRole.passenger,
      ),
      barangayId: data['barangayId'] ?? '',
      barangayName: data['barangayName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isActive: data['isActive'] ?? true,
      idType: data['idType'],
      idImageUrl: data['idImageUrl'],
      selfieUrl: data['selfieUrl'],
      idVerificationStatus: IdVerificationStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (data['idVerificationStatus'] ?? 'notSubmitted'),
        orElse: () => IdVerificationStatus.notSubmitted,
      ),
      idVerificationNote: data['idVerificationNote'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.toString().split('.').last,
      'barangayId': barangayId,
      'barangayName': barangayName,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
      if (idType != null) 'idType': idType,
      if (idImageUrl != null) 'idImageUrl': idImageUrl,
      if (selfieUrl != null) 'selfieUrl': selfieUrl,
      'idVerificationStatus': idVerificationStatus.toString().split('.').last,
      if (idVerificationNote != null) 'idVerificationNote': idVerificationNote,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    bool? isActive,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      barangayId: barangayId,
      barangayName: barangayName,
      createdAt: createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
