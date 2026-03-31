import 'package:flutter/services.dart';

class AndroidForegroundService {
  static const platform = MethodChannel('com.toda.transport.booking/notification_service');

  /// Start the foreground service to keep app alive in background
  static Future<void> startForegroundService() async {
    try {
      print('🚀 Starting Android foreground service...');
      await platform.invokeMethod('startForegroundService');
      print('✅ Foreground service started');
    } catch (e) {
      print('❌ Error starting foreground service: $e');
    }
  }

  /// Stop the foreground service
  static Future<void> stopForegroundService() async {
    try {
      print('🛑 Stopping Android foreground service...');
      await platform.invokeMethod('stopForegroundService');
      print('✅ Foreground service stopped');
    } catch (e) {
      print('❌ Error stopping foreground service: $e');
    }
  }
}
