import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  Stream<List<ConnectivityResult>>? _connectivityStream;
  bool _isConnected = true;

  bool get isConnected => _isConnected;

  /// Initialize the connectivity service
  Future<void> initialize() async {
    // Check initial connectivity status
    final result = await _connectivity.checkConnectivity();
    _isConnected = await _isConnectionAvailable(result);

    // Listen for connectivity changes
    _connectivityStream = _connectivity.onConnectivityChanged;
    _connectivityStream!.listen((result) async {
      _isConnected = await _isConnectionAvailable(result);
    });
  }

  /// Check if connection is available with actual internet access test
  Future<bool> _isConnectionAvailable(List<ConnectivityResult> result) async {
    // First check if device is connected to any network
    if (result.contains(ConnectivityResult.none)) {
      return false;
    }
    
    // Skip actual internet access test on Web as InternetAddress.lookup is not supported
    if (kIsWeb) {
      return true;
    }
    
    // If connected to a network, test actual internet access
    try {
      final response = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return response.isNotEmpty && response[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      // Catch other potential errors on different platforms
      return false;
    }
  }

  /// Check connectivity status and show error if disconnected
  Future<bool> checkConnectivity(BuildContext context) async {
    final result = await _connectivity.checkConnectivity();
    
    _isConnected = await _isConnectionAvailable(result);
    
    if (!_isConnected) {
      _showNoConnectionDialog(context);
      return false;
    }
    
    return true;
  }

  /// Show no connection dialog
  void _showNoConnectionDialog(BuildContext context) {
    // Ensure the context is still valid
    if (!context.mounted) return;
    
    // Use a post frame callback to ensure the dialog is shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.wifi_off, color: Colors.red),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Connection Issue',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
            content: const Text(
              'Your internet connection appears to be slow or unavailable. ' 
              'Please check your connection and try again.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    });
  }

  /// Get user-friendly error message based on error type
  String getErrorMessage(dynamic error) {
    final errorString = error.toString();
    final lowerError = errorString.toLowerCase();
    
    // If it's a simple string error (not a technical exception string), return it directly
    if (error is String && !lowerError.contains('exception') && !lowerError.contains('error:')) {
      return error;
    }
    
    if (lowerError.contains('timeout') || lowerError.contains('timed out')) {
      return 'Connection timed out. Please check your internet connection and try again.';
    } else if (lowerError.contains('network') || 
               lowerError.contains('connection') ||
               lowerError.contains('connect') ||
               lowerError.contains('socket') ||
               lowerError.contains('unreachable')) {
      return 'Network error. Please check your internet connection and try again.';
    } else if (lowerError.contains('permission-denied')) {
      return 'Access denied. Please contact support if this persists.';
    } else if (lowerError.contains('not found')) {
      return 'The requested resource was not found.';
    } else {
      // If we don't recognize the technical error, but it's a reasonably short message, 
      // it might be a user-friendly message from another service
      if (errorString.length < 100 && !errorString.contains('StackTrace')) {
        return errorString;
      }
      return 'An unexpected error occurred. Please try again later.';
    }
  }
}
