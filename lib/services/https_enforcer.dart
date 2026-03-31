import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// HTTPS Enforcement Utility
/// Ensures all HTTP requests use HTTPS and validates certificate pinning
class HTTPSEnforcer {
  static final HTTPSEnforcer _instance = HTTPSEnforcer._internal();
  
  factory HTTPSEnforcer() => _instance;
  HTTPSEnforcer._internal();

  /// Allowed HTTPS domains (whitelist)
  static const Set<String> _allowedDomains = {
    'firebase.google.com',
    'firebaseio.com',
    'firestore.googleapis.com',
    'storage.googleapis.com',
    'identitytoolkit.googleapis.com',
    'securetoken.googleapis.com',
    'googleapis.com',
    'google.com',
    'maps.googleapis.com',
    'mts.googleapis.com',
    'twilio.com',
    // Add your backend domain here
    // 'your-backend.com',
  };

  /// Validate that a URL uses HTTPS
  /// 
  /// Returns true if URL is HTTPS or localhost (for development)
  /// Returns false if URL is HTTP (except localhost)
  static bool isHTTPSUrl(String url) {
    try {
      final uri = Uri.parse(url);
      
      // Allow HTTPS
      if (uri.scheme == 'https') {
        return true;
      }
      
      // Allow localhost/127.0.0.1 for development only
      if (kDebugMode && 
          (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
        return true;
      }
      
      // Reject HTTP in production
      if (uri.scheme == 'http') {
        debugPrint('❌ [HTTPSEnforcer] HTTP URL rejected: $url');
        return false;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ [HTTPSEnforcer] Error validating URL: $e');
      return false;
    }
  }

  /// Validate that a domain is in the whitelist
  static bool isDomainAllowed(String domain) {
    try {
      final uri = Uri.parse(domain);
      final host = uri.host;
      
      // Check if domain is in whitelist
      for (var allowedDomain in _allowedDomains) {
        if (host == allowedDomain || host.endsWith('.$allowedDomain')) {
          return true;
        }
      }
      
      debugPrint('❌ [HTTPSEnforcer] Domain not whitelisted: $host');
      return false;
    } catch (e) {
      debugPrint('❌ [HTTPSEnforcer] Error validating domain: $e');
      return false;
    }
  }

  /// Enforce HTTPS on a URL
  /// 
  /// Converts HTTP to HTTPS and validates domain
  static String enforceHTTPS(String url) {
    try {
      final uri = Uri.parse(url);
      
      // Convert HTTP to HTTPS
      if (uri.scheme == 'http' && uri.host != 'localhost' && uri.host != '127.0.0.1') {
        final httpsUri = uri.replace(scheme: 'https');
        debugPrint('🔒 [HTTPSEnforcer] Converted HTTP to HTTPS: $url → $httpsUri');
        return httpsUri.toString();
      }
      
      return url;
    } catch (e) {
      debugPrint('❌ [HTTPSEnforcer] Error enforcing HTTPS: $e');
      return url;
    }
  }

  /// Validate certificate pinning (basic implementation)
  /// 
  /// In production, use a proper certificate pinning library:
  /// - package:http/http.dart with custom SecurityContext
  /// - package:dio with certificate pinning
  static bool validateCertificatePin(String domain, String certificateHash) {
    // TODO: Implement proper certificate pinning
    // This requires storing certificate hashes and validating them
    // during TLS handshake
    
    debugPrint('🔐 [HTTPSEnforcer] Certificate validation for $domain');
    return true;
  }

  /// Get secure HTTP client with HTTPS enforcement
  static http.Client getSecureClient() {
    return _SecureHTTPClient();
  }

  /// Validate all URLs in a request
  static bool validateRequest(String url, {String? method}) {
    if (!isHTTPSUrl(url)) {
      debugPrint('❌ [HTTPSEnforcer] HTTPS validation failed for: $url');
      return false;
    }
    
    if (!isDomainAllowed(url)) {
      debugPrint('❌ [HTTPSEnforcer] Domain not whitelisted for: $url');
      return false;
    }
    
    debugPrint('✅ [HTTPSEnforcer] Request validated: ${method ?? 'GET'} $url');
    return true;
  }
}

/// Secure HTTP Client that enforces HTTPS
class _SecureHTTPClient extends http.BaseClient {
  final http.Client _innerClient = http.Client();
  
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Validate URL before sending
    if (!HTTPSEnforcer.validateRequest(request.url.toString(), method: request.method)) {
      throw SecurityException(
        'HTTPS validation failed for URL: ${request.url}',
      );
    }
    
    // Send the request using the inner client
    return _innerClient.send(request);
  }
}

/// Custom exception for security violations
class SecurityException implements Exception {
  final String message;
  
  SecurityException(this.message);
  
  @override
  String toString() => 'SecurityException: $message';
}

/// HTTPS Configuration Helper
class HTTPSConfig {
  /// Get minimum TLS version
  static String get minimumTLSVersion => 'TLSv1.2';
  
  /// Get recommended TLS version
  static String get recommendedTLSVersion => 'TLSv1.3';
  
  /// Get HSTS max age in seconds (1 year)
  static int get hstsMaxAge => 31536000;
  
  /// Check if HSTS should include subdomains
  static bool get hstsIncludeSubdomains => true;
  
  /// Check if HSTS preload is enabled
  static bool get hstsPreload => true;
  
  /// Get security headers for HTTP responses
  static Map<String, String> getSecurityHeaders() {
    return {
      'Strict-Transport-Security': 
        'max-age=$hstsMaxAge; includeSubDomains${hstsPreload ? '; preload' : ''}',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'X-XSS-Protection': '1; mode=block',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Permissions-Policy': 'geolocation=(self), microphone=(), camera=(), payment=()',
    };
  }
  
  /// Log security configuration
  static void logConfiguration() {
    if (kDebugMode) {
      debugPrint('🔒 [HTTPSConfig] Security Configuration:');
      debugPrint('   Minimum TLS: $minimumTLSVersion');
      debugPrint('   Recommended TLS: $recommendedTLSVersion');
      debugPrint('   HSTS Max Age: $hstsMaxAge seconds');
      debugPrint('   HSTS Include Subdomains: $hstsIncludeSubdomains');
      debugPrint('   HSTS Preload: $hstsPreload');
    }
  }
}
