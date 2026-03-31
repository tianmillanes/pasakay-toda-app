import 'dart:async';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

/// Comprehensive error handling service for all connection and app errors
class ErrorHandlingService {
  /// Error categories
  static const String categoryNetwork = 'network';
  static const String categoryFirebase = 'firebase';
  static const String categoryLocation = 'location';
  static const String categoryPermission = 'permission';
  static const String categoryTimeout = 'timeout';
  static const String categoryValidation = 'validation';
  static const String categoryUnknown = 'unknown';

  /// Network error keywords to detect no internet scenarios
  static const List<String> networkErrorKeywords = [
    'network',
    'connection',
    'timeout',
    'socket',
    'failed host lookup',
    'connection refused',
    'connection reset',
    'network is unreachable',
    'no route to host',
    'connection timed out',
    'broken pipe',
    'connection aborted',
    'host unreachable',
    'network unreachable',
    'temporary failure',
    'name or service not known',
    'getaddrinfo failed',
    'econnrefused',
    'econnreset',
    'enetunreach',
    'ehostunreach',
    'etimedout',
  ];

  /// Get user-friendly error message based on exception type
  static String getUserFriendlyMessage(dynamic error, {String? context}) {
    if (error == null) {
      return 'An unexpected error occurred. Please try again.';
    }

    // Network errors - check first as they're most common
    if (_isNetworkError(error)) {
      return _getNetworkErrorMessage(error);
    }

    // Network errors
    if (error is SocketException) {
      return _handleSocketException(error);
    }

    if (error is TimeoutException) {
      return 'Connection timed out. Please check your internet and try again.';
    }

    // Firebase errors
    if (error is FirebaseException) {
      return _handleFirebaseException(error);
    }

    // Platform errors
    if (error is PlatformException) {
      return _handlePlatformException(error);
    }

    // String errors (from custom exceptions)
    if (error is String) {
      return _handleStringError(error);
    }

    // Generic exception
    if (error is Exception) {
      return _handleGenericException(error);
    }

    // Fallback
    return 'Something went wrong. Please try again later.';
  }

  /// Get error category for analytics/logging
  static String getErrorCategory(dynamic error) {
    if (_isNetworkError(error)) return categoryNetwork;
    if (error is SocketException) return categoryNetwork;
    if (error is TimeoutException) return categoryTimeout;
    if (error is FirebaseException) return categoryFirebase;
    if (error is PlatformException) {
      if (error.code.contains('location')) return categoryLocation;
      if (error.code.contains('permission')) return categoryPermission;
    }
    if (error is String && error.contains('permission')) return categoryPermission;
    return categoryUnknown;
  }

  /// Check if error is a network error (comprehensive check)
  static bool _isNetworkError(dynamic error) {
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is FirebaseException && error.code == 'unavailable') return true;
    
    // Check string representation for network keywords
    final errorStr = error.toString().toLowerCase();
    for (final keyword in networkErrorKeywords) {
      if (errorStr.contains(keyword)) {
        return true;
      }
    }
    
    return false;
  }

  /// Get network-specific error message
  static String _getNetworkErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    
    // Check for specific network error types
    if (errorStr.contains('timeout') || errorStr.contains('etimedout')) {
      return 'Connection timeout. Please check your internet connection and try again.';
    }
    
    if (errorStr.contains('connection refused') || errorStr.contains('econnrefused')) {
      return 'Unable to connect to the server. Please check your internet connection.';
    }
    
    if (errorStr.contains('connection reset') || errorStr.contains('econnreset')) {
      return 'Connection was interrupted. Please check your internet and try again.';
    }
    
    if (errorStr.contains('network is unreachable') || 
        errorStr.contains('enetunreach') ||
        errorStr.contains('no route to host')) {
      return 'No internet connection detected. Please check your network settings.';
    }
    
    if (errorStr.contains('host unreachable') || errorStr.contains('ehostunreach')) {
      return 'Unable to reach the server. Please check your internet connection.';
    }
    
    if (errorStr.contains('failed host lookup') || 
        errorStr.contains('name or service not known') ||
        errorStr.contains('getaddrinfo failed')) {
      return 'Unable to connect to the server. Please check your internet connection.';
    }
    
    if (errorStr.contains('broken pipe')) {
      return 'Connection lost. Please check your internet and try again.';
    }
    
    if (errorStr.contains('temporary failure')) {
      return 'Temporary network issue. Please try again.';
    }
    
    // Generic network error
    return 'Network connection failed. Please check your internet and try again.';
  }

  /// Handle socket exceptions (network connectivity issues)
  static String _handleSocketException(SocketException error) {
    if (error.message.contains('Connection refused')) {
      return 'Unable to connect to the server. Please check your internet connection.';
    }
    if (error.message.contains('Connection reset')) {
      return 'Connection was interrupted. Please check your internet and try again.';
    }
    if (error.message.contains('Network is unreachable')) {
      return 'No internet connection detected. Please check your network settings.';
    }
    if (error.message.contains('Name or service not known')) {
      return 'Unable to reach the server. Please check your internet connection.';
    }
    return 'Network connection failed. Please check your internet and try again.';
  }

  /// Handle Firebase exceptions
  static String _handleFirebaseException(FirebaseException error) {
    // Check for network-related Firebase errors first
    if (error.code == 'unavailable' || error.message?.toLowerCase().contains('network') == true) {
      return 'Network connection failed. Please check your internet and try again.';
    }
    
    switch (error.code) {
      case 'permission-denied':
        return 'You don\'t have permission to access this resource. Please contact support if you believe this is an error.';
      case 'not-found':
        return 'The requested resource was not found. It may have been deleted.';
      case 'already-exists':
        return 'This resource already exists. Please try with a different value.';
      case 'invalid-argument':
        return 'Invalid data provided. Please check your input and try again.';
      case 'failed-precondition':
        return 'The operation could not be completed. Please try again later.';
      case 'out-of-range':
        return 'The value provided is out of range. Please check and try again.';
      case 'unauthenticated':
        return 'Your session has expired. Please log in again.';
      case 'unavailable':
        return 'The service is temporarily unavailable. Please check your internet connection and try again.';
      case 'internal':
        return 'An internal server error occurred. Please try again later.';
      case 'deadline-exceeded':
        return 'The operation took too long. Please check your internet connection and try again.';
      case 'data-loss':
        return 'Data loss occurred. Please contact support.';
      case 'unknown':
        return 'An unknown error occurred. Please try again.';
      default:
        return 'Firebase error: ${error.message ?? 'Unknown error'}. Please try again.';
    }
  }

  /// Handle platform exceptions
  static String _handlePlatformException(PlatformException error) {
    final code = error.code.toLowerCase();

    // Location-related errors
    if (code.contains('location')) {
      if (code.contains('denied')) {
        return 'Location permission denied. Please enable location access in settings to use this feature.';
      }
      if (code.contains('disabled')) {
        return 'Location services are disabled. Please enable them in your device settings.';
      }
      if (code.contains('unavailable')) {
        return 'Location services are unavailable. Please try again later.';
      }
      return 'Unable to get your location. Please try again.';
    }

    // Permission-related errors
    if (code.contains('permission')) {
      if (code.contains('denied')) {
        return 'Permission denied. Please enable this permission in your app settings.';
      }
      if (code.contains('restricted')) {
        return 'This permission is restricted on your device.';
      }
      return 'Permission error. Please check your app settings.';
    }

    // Biometric errors
    if (code.contains('biometric') || code.contains('auth')) {
      if (code.contains('unavailable')) {
        return 'Biometric authentication is not available on this device.';
      }
      if (code.contains('not_enrolled')) {
        return 'No biometric data enrolled. Please set up biometric authentication in your device settings.';
      }
      if (code.contains('locked_out')) {
        return 'Too many failed attempts. Please try again later.';
      }
      if (code.contains('user_canceled')) {
        return 'Authentication was cancelled.';
      }
      return 'Biometric authentication failed. Please try again.';
    }

    // Network errors
    if (code.contains('network')) {
      return 'Network error. Please check your internet connection.';
    }

    return 'An error occurred: ${error.message ?? 'Unknown error'}. Please try again.';
  }

  /// Handle string errors (custom exceptions)
  static String _handleStringError(String error) {
    final lowerError = error.toLowerCase();

    // Check for network errors first
    for (final keyword in networkErrorKeywords) {
      if (lowerError.contains(keyword)) {
        return _getNetworkErrorMessage(error);
      }
    }

    if (lowerError.contains('permission')) {
      return 'You don\'t have permission to perform this action.';
    }
    if (lowerError.contains('not found')) {
      return 'The requested item was not found.';
    }
    if (lowerError.contains('invalid')) {
      return 'Invalid data provided. Please check and try again.';
    }
    if (lowerError.contains('expired')) {
      return 'Your session has expired. Please log in again.';
    }
    if (lowerError.contains('unauthorized')) {
      return 'You are not authorized to perform this action.';
    }

    return error;
  }

  /// Handle generic exceptions
  static String _handleGenericException(Exception error) {
    final message = error.toString();
    return _handleStringError(message);
  }

  /// Get detailed error information for logging
  static Map<String, dynamic> getErrorDetails(dynamic error, {String? context}) {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'context': context,
      'errorType': error.runtimeType.toString(),
      'category': getErrorCategory(error),
      'message': getUserFriendlyMessage(error, context: context),
      'rawError': error.toString(),
      'stackTrace': StackTrace.current.toString(),
    };
  }

  /// Check if error is a network/connectivity error
  static bool isNetworkError(dynamic error) {
    return _isNetworkError(error);
  }

  /// Check if error is a permission error
  static bool isPermissionError(dynamic error) {
    if (error is FirebaseException && error.code == 'permission-denied') return true;
    if (error is PlatformException && error.code.toLowerCase().contains('permission')) return true;
    if (error is String && error.toLowerCase().contains('permission')) return true;
    return false;
  }

  /// Check if error is an authentication error
  static bool isAuthError(dynamic error) {
    if (error is FirebaseException && error.code == 'unauthenticated') return true;
    if (error is String && error.toLowerCase().contains('unauthorized')) return true;
    return false;
  }

  /// Check if error is a timeout error
  static bool isTimeoutError(dynamic error) {
    if (error is TimeoutException) return true;
    if (error is FirebaseException && error.code == 'deadline-exceeded') return true;
    if (error is String && error.toLowerCase().contains('timeout')) return true;
    return false;
  }

  /// Get retry recommendation
  static bool shouldRetry(dynamic error) {
    // Retry on network errors
    if (isNetworkError(error)) return true;
    // Retry on timeout
    if (isTimeoutError(error)) return true;
    // Retry on temporary Firebase errors
    if (error is FirebaseException) {
      return error.code == 'unavailable' || error.code == 'deadline-exceeded';
    }
    return false;
  }

  /// Get retry delay in milliseconds
  static int getRetryDelay(int attemptNumber) {
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s (max)
    final delay = Duration(seconds: 1 << attemptNumber.clamp(0, 4));
    return delay.inMilliseconds;
  }
}
