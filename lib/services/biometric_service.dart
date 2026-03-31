import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Result of a biometric action with detailed status and user-friendly message
class BiometricResult {
  final bool success;
  final BiometricStatus status;
  final String userMessage;
  final String? debugMessage;

  BiometricResult({
    required this.success,
    required this.status,
    required this.userMessage,
    this.debugMessage,
  });

  @override
  String toString() => 'BiometricResult(success: $success, status: $status, message: $userMessage)';
}

/// Detailed status codes for biometric operations
enum BiometricStatus {
  success,
  notAvailable,
  notEnrolled,
  locked,
  permanentlyLocked,
  userCancelled,
  userFallback,
  timeout,
  platformError,
  unknown,
}

class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  
  factory BiometricService() {
    return _instance;
  }
  
  BiometricService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// Check if biometric authentication is available
  Future<bool> isBiometricAvailable() async {
    try {
      // Biometric auth not supported on web
      if (kIsWeb) {
        _logDebug('Biometric authentication not available on web');
        return false;
      }

      final isDeviceSupported = await _localAuth.canCheckBiometrics;
      return isDeviceSupported;
    } catch (e) {
      _logDebug('Error checking biometric availability: $e');
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      // Biometric auth not supported on web
      if (kIsWeb) {
        _logDebug('Biometric authentication not available on web');
        return [];
      }

      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      _logDebug('Error getting available biometrics: $e');
      return [];
    }
  }

  /// Authenticate using biometrics with detailed result
  Future<BiometricResult> authenticate({
    required String reason,
    bool useErrorDialogs = true,
    bool stickyAuth = false,
  }) async {
    try {
      // Biometric auth not supported on web
      if (kIsWeb) {
        _logDebug('Biometric authentication not available on web');
        return BiometricResult(
          success: false,
          status: BiometricStatus.notAvailable,
          userMessage: 'Biometric authentication is not available on web.',
          debugMessage: 'Web platform does not support biometric authentication',
        );
      }

      _logDebug('🔵 Starting biometric authentication...');
      
      // Check if device can check biometrics
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      _logDebug('🔵 Can check biometrics: $canCheckBiometrics');
      
      if (!canCheckBiometrics) {
        _logDebug('❌ Biometric not available on this device');
        return BiometricResult(
          success: false,
          status: BiometricStatus.notAvailable,
          userMessage: 'Biometric authentication is not available on this device.',
          debugMessage: 'Device does not support biometric authentication',
        );
      }

      // Get available biometrics
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      _logDebug('🔵 Available biometrics: $availableBiometrics');
      
      if (availableBiometrics.isEmpty) {
        _logDebug('❌ No biometric types available');
        return BiometricResult(
          success: false,
          status: BiometricStatus.notEnrolled,
          userMessage: 'No biometric data enrolled. Please set up fingerprint or face recognition in your device settings.',
          debugMessage: 'No biometric types available on device',
        );
      }

      _logDebug('🔵 Showing biometric prompt with reason: $reason');
      
      bool isAuthenticated = false;
      
      try {
        isAuthenticated = await _localAuth.authenticate(
          localizedReason: reason,
          options: AuthenticationOptions(
            stickyAuth: stickyAuth,
            biometricOnly: false,
            useErrorDialogs: useErrorDialogs,
          ),
        );
        
        if (isAuthenticated) {
          _logDebug('✅ Biometric authentication successful');
          return BiometricResult(
            success: true,
            status: BiometricStatus.success,
            userMessage: 'Authentication successful!',
          );
        } else {
          _logDebug('⚠️ Biometric authentication cancelled by user');
          return BiometricResult(
            success: false,
            status: BiometricStatus.userCancelled,
            userMessage: 'Authentication cancelled. Please try again.',
            debugMessage: 'User cancelled biometric authentication',
          );
        }
      } on PlatformException catch (e) {
        return _handleBiometricPlatformException(e);
      } catch (e) {
        _logDebug('❌ Exception during authenticate: $e');
        return BiometricResult(
          success: false,
          status: BiometricStatus.unknown,
          userMessage: 'An error occurred during authentication. Please try again.',
          debugMessage: 'Unexpected exception: $e',
        );
      }
    } catch (e) {
      _logDebug('❌ Unexpected error in biometric authentication: $e');
      return BiometricResult(
        success: false,
        status: BiometricStatus.unknown,
        userMessage: 'An unexpected error occurred. Please try again.',
        debugMessage: 'Unexpected error: $e',
      );
    }
  }

  /// Handle platform-specific biometric exceptions
  BiometricResult _handleBiometricPlatformException(PlatformException e) {
    _logDebug('❌ PlatformException: code=${e.code}, message=${e.message}, details=${e.details}');
    
    final code = e.code.toLowerCase();
    
    // User cancelled authentication
    if (code.contains('usercancelled') || code.contains('user_cancelled')) {
      return BiometricResult(
        success: false,
        status: BiometricStatus.userCancelled,
        userMessage: 'Authentication cancelled. Please try again.',
        debugMessage: 'User cancelled authentication (${e.code})',
      );
    }
    
    // User chose to use fallback (password)
    if (code.contains('userfallback') || code.contains('user_fallback')) {
      return BiometricResult(
        success: false,
        status: BiometricStatus.userFallback,
        userMessage: 'Using password authentication instead.',
        debugMessage: 'User selected fallback authentication (${e.code})',
      );
    }
    
    // Biometric locked due to too many attempts
    if (code.contains('lockout') || code.contains('locked')) {
      return BiometricResult(
        success: false,
        status: BiometricStatus.locked,
        userMessage: 'Too many failed attempts. Please try again later or use your password.',
        debugMessage: 'Biometric temporarily locked (${e.code})',
      );
    }
    
    // Biometric permanently locked
    if (code.contains('permanentlylocked') || code.contains('permanently_locked')) {
      return BiometricResult(
        success: false,
        status: BiometricStatus.permanentlyLocked,
        userMessage: 'Biometric authentication is permanently locked. Please use your password.',
        debugMessage: 'Biometric permanently locked (${e.code})',
      );
    }
    
    // Timeout
    if (code.contains('timeout')) {
      return BiometricResult(
        success: false,
        status: BiometricStatus.timeout,
        userMessage: 'Authentication timed out. Please try again.',
        debugMessage: 'Biometric authentication timeout (${e.code})',
      );
    }
    
    // Biometric not available
    if (code.contains('notavailable') || code.contains('not_available')) {
      return BiometricResult(
        success: false,
        status: BiometricStatus.notAvailable,
        userMessage: 'Biometric authentication is not available. Please use your password.',
        debugMessage: 'Biometric not available (${e.code})',
      );
    }
    
    // Biometric not enrolled
    if (code.contains('notenrolled') || code.contains('not_enrolled')) {
      return BiometricResult(
        success: false,
        status: BiometricStatus.notEnrolled,
        userMessage: 'No biometric data enrolled. Please set up fingerprint or face recognition.',
        debugMessage: 'Biometric not enrolled (${e.code})',
      );
    }
    
    // Generic platform error
    return BiometricResult(
      success: false,
      status: BiometricStatus.platformError,
      userMessage: 'Authentication failed. Please try again or use your password.',
      debugMessage: 'Platform error: ${e.code} - ${e.message}',
    );
  }

  /// Legacy method for backward compatibility - returns bool
  Future<bool> authenticateLegacy({
    required String reason,
    bool useErrorDialogs = true,
    bool stickyAuth = false,
  }) async {
    final result = await authenticate(
      reason: reason,
      useErrorDialogs: useErrorDialogs,
      stickyAuth: stickyAuth,
    );
    return result.success;
  }

  /// Save credentials securely for biometric login
  Future<void> saveCredentials({
    required String email,
    required String password,
  }) async {
    try {
      await _secureStorage.write(
        key: 'biometric_email',
        value: email,
      );
      await _secureStorage.write(
        key: 'biometric_password',
        value: password,
      );
      _logDebug('Credentials saved securely for biometric login');
    } catch (e) {
      _logDebug('Error saving credentials: $e');
      rethrow;
    }
  }

  /// Retrieve saved credentials
  Future<Map<String, String>?> getCredentials() async {
    try {
      final email = await _secureStorage.read(key: 'biometric_email');
      final password = await _secureStorage.read(key: 'biometric_password');

      if (email != null && password != null) {
        return {'email': email, 'password': password};
      }
      return null;
    } catch (e) {
      _logDebug('Error retrieving credentials: $e');
      return null;
    }
  }

  /// Check if credentials are saved
  Future<bool> hasCredentialsSaved() async {
    try {
      final email = await _secureStorage.read(key: 'biometric_email');
      return email != null;
    } catch (e) {
      _logDebug('Error checking saved credentials: $e');
      return false;
    }
  }

  /// Clear saved credentials
  Future<void> clearCredentials() async {
    try {
      await _secureStorage.delete(key: 'biometric_email');
      await _secureStorage.delete(key: 'biometric_password');
      _logDebug('Credentials cleared');
    } catch (e) {
      _logDebug('Error clearing credentials: $e');
      rethrow;
    }
  }

  /// Secure logging - only logs in debug mode
  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint('[BiometricService] $message');
    }
  }
}
