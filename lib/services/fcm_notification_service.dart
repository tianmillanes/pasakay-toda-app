import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('🔔 Background notification received: ${message.messageId}');
  print('   Title: ${message.notification?.title}');
  print('   Body: ${message.notification?.body}');
  print('   Data: ${message.data}');
}

class FCMNotificationService {
  static final FCMNotificationService _instance = FCMNotificationService._internal();
  factory FCMNotificationService() => _instance;
  FCMNotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _fcmToken;
  bool _isInitialized = false;

  /// Initialize FCM and local notifications
  Future<void> initialize() async {
    if (_isInitialized) {
      print('FCM already initialized');
      return;
    }

    try {
      print('🔧 Initializing FCM Notification Service...');

      // Request notification permissions
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
        provisional: false,
      );

      print('📱 Notification permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Initialize local notifications for Android
        await _initializeLocalNotifications();

        // Get FCM token
        _fcmToken = await _firebaseMessaging.getToken();
        print('🔑 FCM Token: $_fcmToken');

        // Listen to token refresh
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          print('🔄 FCM Token refreshed: $newToken');
          _fcmToken = newToken;
        });

        // Configure foreground notification presentation
        await _firebaseMessaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Set up message handlers
        _setupMessageHandlers();

        _isInitialized = true;
        print('✅ FCM Notification Service initialized successfully');
      } else {
        print('❌ Notification permission denied');
      }
    } catch (e) {
      print('❌ Error initializing FCM: $e');
    }
  }

  /// Initialize local notifications (for Android foreground notifications)
  Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    print('✅ Local notifications initialized');
  }

  /// Set up message handlers for different app states
  void _setupMessageHandlers() {
    // Handler for when app is in FOREGROUND
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('🔔 Foreground notification received');
      print('   Title: ${message.notification?.title}');
      print('   Body: ${message.notification?.body}');
      print('   Data: ${message.data}');

      // Show local notification when app is in foreground
      _showLocalNotification(message);
    });

    // Handler for when notification is tapped (app in background/terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('🔔 Notification tapped (app was in background)');
      print('   Data: ${message.data}');
      
      // Handle navigation based on notification data
      _handleNotificationTap(message.data);
    });

    // Check if app was opened from a terminated state via notification
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('🔔 App opened from terminated state via notification');
        print('   Data: ${message.data}');
        _handleNotificationTap(message.data);
      }
    });
  }

  /// Show local notification (for foreground messages)
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'ride_requests', // channel ID
      'Ride Requests', // channel name
      channelDescription: 'Notifications for new ride requests',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
      notificationDetails,
      payload: jsonEncode(message.data),
    );

    print('✅ Local notification shown');
  }

  /// Handle notification tap
  void _onNotificationTap(NotificationResponse response) {
    print('🔔 Local notification tapped');
    if (response.payload != null) {
      final data = jsonDecode(response.payload!);
      _handleNotificationTap(data);
    }
  }

  /// Handle notification data (navigate to appropriate screen)
  void _handleNotificationTap(Map<String, dynamic> data) {
    print('📱 Handling notification tap with data: $data');
    
    // You can add navigation logic here based on notification type
    final type = data['type'];
    final rideId = data['rideId'];

    if (type == 'ride_request' && rideId != null) {
      // Navigate to ride request screen
      print('   -> Navigate to ride request: $rideId');
      // TODO: Implement navigation using your app's navigation system
    } else if (type == 'ride_accepted' && rideId != null) {
      print('   -> Navigate to active ride: $rideId');
      // TODO: Implement navigation
    }
  }

  /// Get FCM token
  String? get fcmToken => _fcmToken;

  /// Update FCM token in Firestore for a user
  Future<void> updateUserFCMToken(String userId) async {
    if (_fcmToken == null) {
      print('⚠️ FCM token not available yet');
      return;
    }

    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': _fcmToken,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ FCM token updated for user: $userId');
    } catch (e) {
      print('❌ Error updating FCM token: $e');
    }
  }

  /// Delete FCM token (call on logout)
  Future<void> deleteFCMToken(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      });
      await _firebaseMessaging.deleteToken();
      _fcmToken = null;
      print('✅ FCM token deleted for user: $userId');
    } catch (e) {
      print('❌ Error deleting FCM token: $e');
    }
  }

  /// Send notification to a specific user via FCM
  /// This is a CLIENT-SIDE implementation (no Cloud Functions needed!)
  /// 
  /// IMPORTANT: For production, you should use a backend server to send FCM
  /// notifications for better security. This is a simplified version.
  Future<void> sendNotificationToUser({
    required String targetUserId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      // Get target user's FCM token
      final userDoc = await _firestore.collection('users').doc(targetUserId).get();
      
      if (!userDoc.exists) {
        print('❌ User not found: $targetUserId');
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final targetToken = userData['fcmToken'] as String?;

      if (targetToken == null || targetToken.isEmpty) {
        print('❌ No FCM token found for user: $targetUserId');
        return;
      }

      print('📤 Sending notification to user: $targetUserId');
      print('   Title: $title');
      print('   Body: $body');

      // ⚠️ IMPORTANT: For production, move this to a secure backend server
      // This is using Legacy FCM API which requires your server key
      // Get your Server Key from: Firebase Console -> Project Settings -> Cloud Messaging
      
      // For now, we'll use Firestore to trigger notifications via a collection
      // that your backend (or Cloud Functions free tier) can watch
      await _createNotificationRequest(
        targetUserId: targetUserId,
        title: title,
        body: body,
        data: data,
      );

    } catch (e) {
      print('❌ Error sending notification: $e');
    }
  }

  /// Create notification request in Firestore
  /// A simple backend service can watch this collection and send FCM notifications
  Future<void> _createNotificationRequest({
    required String targetUserId,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _firestore.collection('notification_requests').add({
        'targetUserId': targetUserId,
        'title': title,
        'body': body,
        'data': data,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      print('✅ Notification request created in Firestore');
      print('   -> A backend service can process this and send FCM notification');
    } catch (e) {
      print('❌ Error creating notification request: $e');
    }
  }

  /// Alternative: Send direct FCM notification using HTTP API
  /// ⚠️ This requires your Firebase Server Key - should be done on backend
  Future<void> sendDirectFCMNotification({
    required String fcmToken,
    required String title,
    required String body,
    required Map<String, dynamic> data,
    required String serverKey, // Your Firebase Server Key
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$serverKey',
        },
        body: jsonEncode({
          'to': fcmToken,
          'notification': {
            'title': title,
            'body': body,
            'sound': 'default',
          },
          'data': data,
          'priority': 'high',
          'content_available': true,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ FCM notification sent successfully');
      } else {
        print('❌ Failed to send FCM notification: ${response.statusCode}');
        print('   Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Error sending direct FCM notification: $e');
    }
  }
}
