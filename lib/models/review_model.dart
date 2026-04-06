import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String id;
  final String driverId;
  final String passengerId;
  final String passengerName;
  final String rideId;
  final double rating;
  final String feedback;
  final DateTime createdAt;
  final bool isPasabuy;

  ReviewModel({
    required this.id,
    required this.driverId,
    required this.passengerId,
    required this.passengerName,
    required this.rideId,
    required this.rating,
    required this.feedback,
    required this.createdAt,
    this.isPasabuy = false,
  });

  factory ReviewModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ReviewModel(
      id: doc.id,
      driverId: data['driverId'] ?? '',
      passengerId: data['passengerId'] ?? '',
      passengerName: data['passengerName'] ?? '',
      rideId: data['rideId'] ?? '',
      rating: (data['rating'] ?? 0.0).toDouble(),
      feedback: data['feedback'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPasabuy: data['isPasabuy'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'driverId': driverId,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'rideId': rideId,
      'rating': rating,
      'feedback': feedback,
      'createdAt': FieldValue.serverTimestamp(),
      'isPasabuy': isPasabuy,
    };
  }
}
