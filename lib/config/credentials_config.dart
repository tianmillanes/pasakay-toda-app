/// Secure Credentials Configuration
/// 
/// This file loads credentials from environment variables or .env file
/// NEVER hardcode sensitive credentials in the app!
/// 
/// Setup Instructions:
/// 1. Copy .env.example to .env
/// 2. Fill in your actual credentials in .env
/// 3. Add .env to .gitignore
/// 4. Run: flutter pub get
/// 5. Restart the app

import 'package:flutter_dotenv/flutter_dotenv.dart';

class CredentialsConfig {
  // ============================================================================
  // EMAIL CONFIGURATION
  // ============================================================================
  
  /// Gmail SMTP email address
  /// From: .env EMAIL_ADDRESS
  static String get emailAddress {
    return _getEnvVariable(
      'EMAIL_ADDRESS',
      defaultValue: 'pasakaytoda@gmail.com',
      isRequired: true,
    );
  }
  
  /// Gmail App Password (NOT regular password)
  /// From: .env EMAIL_PASSWORD
  /// 
  /// To generate:
  /// 1. Go to Google Account > Security
  /// 2. Enable 2-Step Verification
  /// 3. Go to App passwords
  /// 4. Generate new app password for "Mail" and "Windows Computer"
  /// 5. Copy the 16-character password
  static String get emailPassword {
    return _getEnvVariable(
      'EMAIL_PASSWORD',
      defaultValue: '',
      isRequired: true,
    );
  }
  
  /// Email sender name (display name in emails)
  /// From: .env EMAIL_SENDER_NAME
  static String get emailSenderName {
    return _getEnvVariable(
      'EMAIL_SENDER_NAME',
      defaultValue: 'Pasakay Toda',
      isRequired: false,
    );
  }
  
  /// SMTP host for email sending
  /// From: .env EMAIL_SMTP_HOST
  static String get smtpHost {
    return _getEnvVariable(
      'EMAIL_SMTP_HOST',
      defaultValue: 'smtp.gmail.com',
      isRequired: false,
    );
  }
  
  /// SMTP port for email sending
  /// From: .env EMAIL_SMTP_PORT
  static int get smtpPort {
    final portStr = _getEnvVariable(
      'EMAIL_SMTP_PORT',
      defaultValue: '587',
      isRequired: false,
    );
    return int.tryParse(portStr) ?? 587;
  }
  
  // ============================================================================
  // FIREBASE CONFIGURATION
  // ============================================================================
  
  /// Firebase Project ID
  /// From: .env FIREBASE_PROJECT_ID
  static String get firebaseProjectId {
    return _getEnvVariable(
      'FIREBASE_PROJECT_ID',
      defaultValue: '',
      isRequired: false,
    );
  }
  
  /// Firebase API Key
  /// From: .env FIREBASE_API_KEY
  static String get firebaseApiKey {
    return _getEnvVariable(
      'FIREBASE_API_KEY',
      defaultValue: '',
      isRequired: false,
    );
  }
  
  // ============================================================================
  // APP CONFIGURATION
  // ============================================================================
  
  /// Application name
  /// From: .env APP_NAME
  static String get appName {
    return _getEnvVariable(
      'APP_NAME',
      defaultValue: 'Pasakay Toda',
      isRequired: false,
    );
  }
  
  /// Application version
  /// From: .env APP_VERSION
  static String get appVersion {
    return _getEnvVariable(
      'APP_VERSION',
      defaultValue: '1.0.0',
      isRequired: false,
    );
  }
  
  /// Environment (development, staging, production)
  /// From: .env ENVIRONMENT
  static String get environment {
    return _getEnvVariable(
      'ENVIRONMENT',
      defaultValue: 'development',
      isRequired: false,
    );
  }
  
  /// Check if running in production
  static bool get isProduction => environment == 'production';
  
  /// Check if running in development
  static bool get isDevelopment => environment == 'development';
  
  // ============================================================================
  // MAP CONFIGURATION
  // ============================================================================
  
  /// Mapbox Access Token
  /// From: .env MAPBOX_ACCESS_TOKEN
  static String get mapboxAccessToken {
    return _getEnvVariable(
      'MAPBOX_ACCESS_TOKEN',
      defaultValue: 'pk.eyJ1IjoidGlhbnRpYW5tbGxucyIsImEiOiJjbWp4cWtiMXc0bmF4M2ZxMTNncWw5ZGp0In0.O8JyI2F8BrZ1U8KmWj-3xw',
      isRequired: true,
    );
  }
  
  // ============================================================================
  // VALIDATION
  // ============================================================================
  
  /// Check if all required credentials are configured
  static bool get isConfigured {
    try {
      // Check email credentials
      final hasEmail = emailAddress.isNotEmpty && 
                       emailAddress != 'your-pasakay-app@gmail.com';
      final hasPassword = emailPassword.isNotEmpty && 
                          emailPassword != 'your-app-password-here';
      
      if (!hasEmail || !hasPassword) {
        print('❌ Email credentials not configured. Check .env file.');
        return false;
      }
      
      print('✅ Credentials configured successfully');
      return true;
    } catch (e) {
      print('❌ Error validating credentials: $e');
      return false;
    }
  }
  
  /// Get all configured credentials (for debugging, masks sensitive data)
  static Map<String, String> getConfigurationSummary() {
    return {
      'Email Address': emailAddress,
      'Email Password': _maskSensitiveData(emailPassword),
      'SMTP Host': smtpHost,
      'SMTP Port': smtpPort.toString(),
      'Sender Name': emailSenderName,
      'App Name': appName,
      'App Version': appVersion,
      'Environment': environment,
      'Firebase Project ID': firebaseProjectId.isEmpty ? '(not set)' : _maskSensitiveData(firebaseProjectId),
      'Mapbox Access Token': _maskSensitiveData(mapboxAccessToken),
    };
  }
  
  // ============================================================================
  // PRIVATE HELPERS
  // ============================================================================
  
  /// Get environment variable with fallback
  static String _getEnvVariable(
    String key, {
    required String defaultValue,
    required bool isRequired,
  }) {
    try {
      final value = dotenv.env[key] ?? defaultValue;
      
      if (isRequired && value.isEmpty) {
        print('⚠️  Warning: Required environment variable "$key" not set. Using default.');
      }
      
      return value;
    } catch (e) {
      print('❌ Error reading environment variable "$key": $e');
      return defaultValue;
    }
  }
  
  /// Mask sensitive data for logging (shows first and last 3 chars)
  static String _maskSensitiveData(String data) {
    if (data.length <= 6) return '***';
    return '${data.substring(0, 3)}***${data.substring(data.length - 3)}';
  }
  
  /// Initialize credentials from .env file
  /// Call this in main() before using any credentials
  static Future<void> initialize() async {
    try {
      print('🔍 Attempting to load .env file...');
      
      // Try different paths for .env file
      List<String> pathsToTry = [
        '.env',
        'assets/.env',
        'lib/.env',
      ];
      
      bool loaded = false;
      for (String path in pathsToTry) {
        try {
          print('   Trying path: $path');
          await dotenv.load(fileName: path);
          print('✅ Successfully loaded .env from: $path');
          loaded = true;
          break;
        } catch (e) {
          print('   ❌ Failed to load from $path: $e');
        }
      }
      
      if (!loaded) {
        print('⚠️  Could not load .env file from any path');
        print('💡 Make sure .env file exists in project root');
      }
      
      // Validate configuration
      if (!isConfigured) {
        print('⚠️  Warning: Email credentials are not properly configured');
        print('📋 Configuration Summary:');
        getConfigurationSummary().forEach((key, value) {
          print('   $key: $value');
        });
      } else {
        print('✅ Email credentials are properly configured');
      }
    } catch (e) {
      print('❌ Error during credentials initialization: $e');
      print('💡 Make sure .env file exists in project root');
      print('💡 Copy from .env.example if needed');
    }
  }
}
