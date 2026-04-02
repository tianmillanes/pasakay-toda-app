import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;

class IdVerificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Upload government ID image and selfie as Base64 encoded strings to avoid Firebase Storage usage
  static Future<void> submitVerification({
    required String userId,
    required String idType,
    required Uint8List idImageBytes,
    required Uint8List selfieImageBytes,
  }) async {
    // Compress heavily to ensure the base64 fits well within Firestore 1MB limits
    final compressedIdBytes = await _compressToBytes(idImageBytes);
    final compressedSelfieBytes = await _compressToBytes(selfieImageBytes);

    final idBase64 = base64Encode(compressedIdBytes);
    final selfieBase64 = base64Encode(compressedSelfieBytes);

    // Convert to Data URI format (consistent with drivers' system)
    final idDataUri = 'data:image/jpeg;base64,$idBase64';
    final selfieDataUri = 'data:image/jpeg;base64,$selfieBase64';

    // Store directly in the user document (matching driver behavior)
    // This ensures photos don't "vanish" and are always available
    await _firestore.collection('users').doc(userId).update({
      'idType': idType,
      'idVerificationStatus': 'pending',
      'idVerificationSubmittedAt': FieldValue.serverTimestamp(),
      'idImageUrl': idDataUri,
      'selfieUrl': selfieDataUri,
    });

    // Create admin notification
    await _firestore.collection('notifications').add({
      'type': 'id_verification_request',
      'userId': userId,
      'title': 'New ID Verification Request',
      'body': 'A passenger has submitted their government ID for verification.',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin: approve a passenger ID verification
  static Future<void> approveVerification({
    required String userId,
    required String adminId,
  }) async {
    await _firestore.collection('users').doc(userId).update({
      'idVerificationStatus': 'approved',
      'idVerificationNote': 'Your government ID has been verified.',
      'idVerificationReviewedAt': FieldValue.serverTimestamp(),
      'idVerificationReviewedBy': adminId,
    });

    // We NO LONGER delete the photos. They stay in the user profile permanently 
    // for future reference, just like driver licenses.

    // Notify passenger
    await _firestore.collection('notifications').add({
      'type': 'id_verification_result',
      'userId': userId,
      'title': 'ID Verified ✅',
      'body': 'Your government ID has been successfully verified by admin.',
      'status': 'approved',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin: reject a passenger ID verification
  static Future<void> rejectVerification({
    required String userId,
    required String adminId,
    required String reason,
  }) async {
    await _firestore.collection('users').doc(userId).update({
      'idVerificationStatus': 'rejected',
      'idVerificationNote': reason,
      'idVerificationReviewedAt': FieldValue.serverTimestamp(),
      'idVerificationReviewedBy': adminId,
    });

    // We NO LONGER delete the photos. This allows them to see why they were
    // rejected and re-submit if needed.

    // Notify passenger
    await _firestore.collection('notifications').add({
      'type': 'id_verification_result',
      'userId': userId,
      'title': 'ID Verification Rejected ❌',
      'body': 'Reason: $reason. Please re-submit with a clearer photo.',
      'status': 'rejected',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Extremely aggressive compression to guarantee we bypass the 1MB Firestore limit
  static Future<Uint8List> _compressToBytes(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    // Resize to max 600px wide (perfectly readable for ID details, tiny file size)
    final resized = img.copyResize(decoded, width: decoded.width > 600 ? 600 : decoded.width);
    
    // Quality 60 gives amazing size reduction with almost unnoticeable artifacting
    final compressed = img.encodeJpg(resized, quality: 60);

    return compressed;
  }

  /// Fetch the verification photos for an admin
  static Future<Map<String, String>?> getVerificationPhotos(String userId) async {
    try {
      final doc = await _firestore.collection('user_verifications').doc(userId).get();
      if (!doc.exists) return null;
      return {
        'idBase64': doc.data()?['idBase64'] as String? ?? '',
        'selfieBase64': doc.data()?['selfieBase64'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  /// Get all pending passenger verification requests
  static Stream<List<Map<String, dynamic>>> getPendingVerifications() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'passenger')
        .where('idVerificationStatus', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }
}
