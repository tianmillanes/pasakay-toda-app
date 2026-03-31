import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;
import '../models/chat_message_model.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream of messages for a specific context (Ride or PasaBuy)
  Stream<List<ChatMessage>> getMessagesStream(String collectionPath, String docId) {
    return _firestore
        .collection(collectionPath)
        .doc(docId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList();
    });
  }

  // Send a message
  Future<void> sendMessage({
    required String collectionPath,
    required String docId,
    required String senderId,
    required String receiverId,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;

    await _firestore
        .collection(collectionPath)
        .doc(docId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'type': 'text',
      'imageUrl': null,
    });
  }

  // Send an image message
  Future<void> sendImageMessage({
    required String collectionPath,
    required String docId,
    required String senderId,
    required String receiverId,
    required File imageFile,
  }) async {
    try {
      if (!imageFile.existsSync()) {
        throw 'Image file does not exist at path: ${imageFile.path}';
      }

      // Read file
      final bytes = await imageFile.readAsBytes();
      
      // Decode image
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw 'Failed to decode image';
      }

      // Resize if too large (max width 600 for safety and speed)
      img.Image resizedImage = image;
      if (image.width > 600) {
        resizedImage = img.copyResize(image, width: 600);
      }

      // Compress to JPEG with quality 50
      // This usually results in < 100KB images
      List<int> compressedBytes = img.encodeJpg(resizedImage, quality: 50);

      // Check size (must be < 500KB for Firestore safe limit)
      // Base64 adds ~33% overhead. 500KB -> ~665KB.
      if (compressedBytes.length > 500 * 1024) {
         // Try reducing quality further if still too big
         compressedBytes = img.encodeJpg(resizedImage, quality: 30);
         if (compressedBytes.length > 500 * 1024) {
             throw 'Image is too large to send directly. Please use a smaller image.';
         }
      }

      // Convert to Base64
      final base64Image = base64Encode(compressedBytes);

      // Add message to Firestore
      await _firestore
          .collection(collectionPath)
          .doc(docId)
          .collection('messages')
          .add({
        'senderId': senderId,
        'receiverId': receiverId,
        'text': 'Sent an image',
        'imageUrl': base64Image, // Storing Base64 string directly
        'type': 'image',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
      
      print('Image message added to Firestore (Base64). Size: ${base64Image.length} chars');

    } catch (e) {
      print('Error sending image: $e');
      rethrow;
    }
  }

  // Mark messages as read (when user opens chat)
  // This marks all unread messages sent by the OTHER user as read.
  Future<void> markMessagesAsRead({
    required String collectionPath,
    required String docId,
    required String currentUserId,
  }) async {
    final batch = _firestore.batch();
    
    // Get all unread messages first, then filter locally
    final unreadMessages = await _firestore
        .collection(collectionPath)
        .doc(docId)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .get();

    for (var doc in unreadMessages.docs) {
      if (doc['senderId'] != currentUserId) {
        batch.update(doc.reference, {'isRead': true});
      }
    }

    await batch.commit();
  }
  
  // Get unread count stream
  Stream<int> getUnreadCountStream({
    required String collectionPath,
    required String docId,
    required String currentUserId,
  }) {
    return _firestore
        .collection(collectionPath)
        .doc(docId)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      // Filter locally to avoid composite index requirements
      return snapshot.docs
          .where((doc) => doc['senderId'] != currentUserId)
          .length;
    });
  }
}
