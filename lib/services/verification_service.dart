import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/email_config.dart';

// Mailer package for sending emails
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

// Platform-specific imports
import 'dart:io' if (dart.library.html) 'dart:html' as platform;

enum VerificationType { sms, email }

class VerificationData {
  final String code;
  final DateTime expiresAt;
  final String target; // phone or email
  final VerificationType type;
  final bool isVerified;

  VerificationData({
    required this.code,
    required this.expiresAt,
    required this.target,
    required this.type,
    this.isVerified = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'target': target,
      'type': type.toString().split('.').last,
      'isVerified': isVerified,
    };
  }

  factory VerificationData.fromMap(Map<String, dynamic> map) {
    return VerificationData(
      code: map['code'] ?? '',
      expiresAt: (map['expiresAt'] as Timestamp).toDate(),
      target: map['target'] ?? '',
      type: VerificationType.values.firstWhere(
        (e) => e.toString().split('.').last == map['type'],
        orElse: () => VerificationType.email,
      ),
      isVerified: map['isVerified'] ?? false,
    );
  }
}

class VerificationService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Cache for verification codes
  final Map<String, VerificationData> _verificationCache = {};
  
  // Cache for resend cooldowns
  final Map<String, DateTime> _resendCooldowns = {};
  
  // Cooldown duration for resending codes
  static const Duration RESEND_COOLDOWN = Duration(minutes: 1);
  
  // For SMS verification
  String? _verificationId;
  int? _resendToken;
  
  // SMS Quota Management (Firebase free tier: 10 SMS/day)
  static const int SMS_DAILY_LIMIT = 10;
  static int _dailySMSCount = 0;
  static DateTime? _lastResetDate;
  
  // Email configuration is now in EmailConfig class
  
  /// Check and reset SMS quota if new day
  void _checkAndResetSMSQuota() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_lastResetDate == null || _lastResetDate!.isBefore(today)) {
      _dailySMSCount = 0;
      _lastResetDate = today;
      // SMS quota reset. Available: $SMS_DAILY_LIMIT SMS today
    }
  }
  
  /// Get remaining SMS quota for today
  int getRemainingDailySMS() {
    _checkAndResetSMSQuota();
    return SMS_DAILY_LIMIT - _dailySMSCount;
  }
  
  /// Check if SMS quota is available
  bool hasSMSQuotaAvailable() {
    _checkAndResetSMSQuota();
    return _dailySMSCount < SMS_DAILY_LIMIT;
  }
  
  /// Generate a 6-digit verification code
  String _generateCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Format phone number to international format
  String _formatPhoneNumber(String phone) {
    // Remove all non-digit characters except +
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    
    // Original phone: $phone
    // Clean phone: $cleanPhone
    
    // If it starts with 09, convert to +639
    if (cleanPhone.startsWith('09')) {
      cleanPhone = '+63${cleanPhone.substring(1)}';
    }
    // If it starts with 63, add +
    else if (cleanPhone.startsWith('63') && !cleanPhone.startsWith('+63')) {
      cleanPhone = '+$cleanPhone';
    }
    // If it doesn't start with +, assume it needs +63
    else if (!cleanPhone.startsWith('+')) {
      cleanPhone = '+63$cleanPhone';
    }
    
    // Formatted phone: $cleanPhone
    
    // Validate the final format
    if (!_isValidPhoneFormat(cleanPhone)) {
      // Warning: Phone format may be invalid: $cleanPhone
    }
    
    return cleanPhone;
  }

  /// Validate phone number format
  bool _isValidPhoneFormat(String phone) {
    // Should be +63 followed by 10 digits (9xxxxxxxxx)
    final regex = RegExp(r'^\+639\d{9}$');
    return regex.hasMatch(phone);
  }

  /// Send SMS OTP
  Future<bool> sendSMSVerification(String phoneNumber) async {
    _resendCooldowns[phoneNumber] = DateTime.now().add(RESEND_COOLDOWN);
    notifyListeners();
    
    // Check strictly for Firebase daily quota (10 SMS/day on Spark plan)
    if (!hasSMSQuotaAvailable()) {
      print('❌ SMS Quota exceeded. Daily limit of 10 reached.');
      return false;
    }
    _dailySMSCount++;

    final formattedPhone = _formatPhoneNumber(phoneNumber);
    if (kIsWeb) {
      return await _sendSMSWeb(formattedPhone, phoneNumber);
    } else {
      return await _sendSMSNative(formattedPhone, phoneNumber);
    }
  }

  /// Send SMS on web platform with reCAPTCHA
  Future<bool> _sendSMSWeb(String formattedPhone, String originalPhone) async {
    try {
      // Web SMS verification for: $formattedPhone
      final completer = Completer<bool>();
      
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) {
          // Web auto-verification completed
          _verificationCache[originalPhone] = VerificationData(
            code: 'auto-verified',
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            target: originalPhone,
            type: VerificationType.sms,
            isVerified: true,
          );
          completer.complete(true);
        },
        verificationFailed: (FirebaseAuthException e) {
          // Web SMS verification failed: ${e.code} - ${e.message}
          
          // Handle specific billing error
          if (e.code == 'billing-not-enabled') {
            // Firebase billing not enabled for SMS verification
            // Please enable Firebase Blaze plan to use SMS verification
            // Go to: https://console.firebase.google.com/project/[your-project]/usage/details
          }
          
          completer.complete(false);
        },
        codeSent: (String verificationId, int? resendToken) {
          // Web SMS code sent successfully
          _verificationId = verificationId;
          _resendToken = resendToken;
          
          _verificationCache[originalPhone] = VerificationData(
            code: verificationId,
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            target: originalPhone,
            type: VerificationType.sms,
          );
          
          completer.complete(true);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Web auto-retrieval timeout
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
      
      return await completer.future;
    } catch (e) {
      // Web SMS error: $e
      return false;
    }
  }

  /// Send SMS on native platforms
  Future<bool> _sendSMSNative(String formattedPhone, String originalPhone) async {
    try {
      // Native SMS verification for: $formattedPhone
      final completer = Completer<bool>();
      
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) {
          // Auto-verification completed for $formattedPhone
          // Store as verified
          _verificationCache[originalPhone] = VerificationData(
            code: 'auto-verified',
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            target: originalPhone,
            type: VerificationType.sms,
            isVerified: true,
          );
          completer.complete(true);
        },
        verificationFailed: (FirebaseAuthException e) {
          // SMS verification failed for $formattedPhone
          // Error Code: ${e.code}
          // Error Message: ${e.message}
          // Error Details: ${e.toString()}
          
          // Provide specific error messages
          String errorMessage = 'SMS verification failed';
          switch (e.code) {
            case 'billing-not-enabled':
              errorMessage = 'SMS verification requires Firebase Blaze plan. Please upgrade your Firebase project.';
              // Firebase billing not enabled for SMS verification
              // Please enable Firebase Blaze plan to use SMS verification
              // Go to: https://console.firebase.google.com/project/[your-project]/usage/details
              break;
            case 'invalid-phone-number':
              errorMessage = 'Invalid phone number format';
              break;
            case 'too-many-requests':
              errorMessage = 'Too many SMS requests. Please try again later';
              break;
            case 'quota-exceeded':
              errorMessage = 'SMS quota exceeded. Please try again later';
              break;
            case 'captcha-check-failed':
              errorMessage = 'reCAPTCHA verification failed. Please try again';
              break;
            case 'missing-phone-number':
              errorMessage = 'Phone number is required';
              break;
            default:
              errorMessage = e.message ?? 'Unknown SMS error';
          }
          
          // User-friendly error: $errorMessage
          completer.complete(false);
        },
        codeSent: (String verificationId, int? resendToken) {
          // SMS code sent successfully to $formattedPhone
          // Verification ID: ${verificationId.substring(0, 10)}...
          
          _verificationId = verificationId;
          _resendToken = resendToken;
          
          // Store verification data with the verification ID
          _verificationCache[originalPhone] = VerificationData(
            code: verificationId,
            expiresAt: DateTime.now().add(const Duration(minutes: 5)),
            target: originalPhone,
            type: VerificationType.sms,
          );
          
          completer.complete(true);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          // Auto-retrieval timeout for $formattedPhone
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 120), // Increased timeout
      );
      
      return await completer.future.timeout(
        const Duration(seconds: 130),
        onTimeout: () {
          // SMS verification timeout for $formattedPhone
          return false;
        },
      );
    } catch (e) {
      // Exception in SMS verification: $e
      // Stack trace: ${StackTrace.current}
      return false;
    }
  }

  /// Verify SMS OTP code (Twilio)
  Future<bool> verifySMSCode(String phoneNumber, String code) async {
    try {
      // Check if verification data exists
      if (!_verificationCache.containsKey(phoneNumber)) {
        // No verification code sent to this phone number
        return false;
      }

      final verificationData = _verificationCache[phoneNumber]!;

      // Check if code has expired
      if (verificationData.isExpired) {
        // Verification code has expired
        return false;
      }

      // Verify the code matches
      if (verificationData.code != code) {
        // Invalid verification code
        return false;
      }

      // Mark as verified
      _verificationCache[phoneNumber] = VerificationData(
        code: verificationData.code,
        expiresAt: verificationData.expiresAt,
        target: phoneNumber,
        type: VerificationType.sms,
        isVerified: true,
      );

      // SMS verification successful for: $phoneNumber
      return true;
    } catch (e) {
      // SMS verification error: $e
      return false;
    }
  }

  /// Send email verification code
  Future<bool> sendEmailVerification(String email) async {
    try {
      final code = _generateCode();
      
      // Set resend cooldown
      _resendCooldowns[email] = DateTime.now().add(RESEND_COOLDOWN);
      notifyListeners();
      
      // Store verification data
      _verificationCache[email] = VerificationData(
        code: code,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        target: email,
        type: VerificationType.email,
      );

      // Platform-specific email sending
      if (kIsWeb) {
        return await _sendEmailWeb(email, code);
      } else {
        return await _sendEmailNative(email, code);
      }
    } catch (e) {
      print('Error sending email: $e');
      return false;
    }
  }

  /// Send email on web platform (simulated for now)
  Future<bool> _sendEmailWeb(String email, String code) async {
    try {
      // For web platform, we'll simulate email sending
      // In production, you'd use a backend service or Firebase Functions
      print('🌐 Web platform: Cannot send real emails directly');
      print('💡 Check console for verification code');
      
      // Show the code prominently in console for testing
      print('');
      print('🔥🔥🔥 EMAIL VERIFICATION CODE 🔥🔥🔥');
      print('📧 To: $email');
      print('🔢 Code: $code');
      print('⏰ Expires: ${DateTime.now().add(const Duration(minutes: 5))}');
      print('👆 USE THIS CODE IN YOUR APP 👆');
      print('🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥🔥');
      print('');
      
      // For demo purposes, we'll return true
      // In production, implement proper backend email service
      return true;
    } catch (e) {
      print('Web email error: $e');
      return false;
    }
  }

  /// Send email on native platforms (mobile/desktop)
  Future<bool> _sendEmailNative(String email, String code) async {
    try {
      print('📧 Sending email to: $email');
      print('🔍 Checking email configuration...');
      
      // Check if email config is set up
      if (!EmailConfig.isConfigured) {
        print('❌ Email NOT configured!');
        print('   - Email Address: ${EmailConfig.senderEmail}');
        print('   - Email Password: ${EmailConfig.senderPassword.isEmpty ? '(empty)' : '(set)'}');
        print('💡 Make sure .env file has EMAIL_ADDRESS and EMAIL_PASSWORD');
        // Fall back to console display
        print('=== EMAIL VERIFICATION CODE ===');
        print('To: $email');
        print('Code: $code');
        print('===============================');
        return false;
      }

      print('✅ Email config is configured');
      print('   - Sender: ${EmailConfig.senderEmail}');
      print('   - Password: ${EmailConfig.senderPassword.isEmpty ? '(empty)' : '(${EmailConfig.senderPassword.length} chars)'}');
      print('   - SMTP Host: ${EmailConfig.smtpHost}');
      print('   - SMTP Port: ${EmailConfig.smtpPort}');

      // Try to send real email using mailer package
      try {
        print('🔗 Connecting to SMTP server...');
        final smtp = gmail(EmailConfig.senderEmail, EmailConfig.senderPassword);
        
        print('📝 Creating email message...');
        final message = Message()
          ..from = Address(EmailConfig.senderEmail, EmailConfig.senderName)
          ..recipients.add(email)
          ..subject = EmailConfig.verificationSubject
          ..html = EmailConfig.getVerificationEmailHtml(code);

        print('📤 Sending email to $email...');
        final sendReport = await send(message, smtp);
        print('✅ Email sent successfully!');
        return true;
        
      } catch (emailError) {
        print('❌ SMTP Error: $emailError');
        // Fallback for testing/development
        print('=== TEST FALLBACK: EMAIL VERIFICATION CODE ===');
        print('To: $email');
        print('Code: $code');
        print('=============================================');
        
        // If it's a specific Gmail auth error, provide a clearer message
        if (emailError.toString().contains('Invalid login')) {
          throw 'Email configuration error: Invalid Gmail credentials or App Password.';
        }
        
        throw 'Failed to send email: ${emailError.toString().split('\n').first}';
      }
      
    } catch (e) {
      print('❌ Unexpected error: $e');
      print('   - Error Type: ${e.runtimeType}');
      return false;
    }
  }

  /// Verify email code
  Future<bool> verifyEmailCode(String email, String code) async {
    try {
      final verificationData = _verificationCache[email];
      
      if (verificationData == null) {
        throw Exception('No verification code found for this email.');
      }
      
      if (verificationData.isExpired) {
        throw Exception('Verification code has expired. Please request a new one.');
      }
      
      if (verificationData.code != code) {
        throw Exception('Invalid verification code.');
      }
      
      // Mark as verified
      _verificationCache[email] = VerificationData(
        code: verificationData.code,
        expiresAt: verificationData.expiresAt,
        target: email,
        type: VerificationType.email,
        isVerified: true,
      );
      
      return true;
    } catch (e) {
      print('Email verification error: $e');
      return false;
    }
  }

  /// Check if phone number is verified
  bool isPhoneVerified(String phoneNumber) {
    final data = _verificationCache[phoneNumber];
    return data != null && data.isVerified && data.type == VerificationType.sms;
  }

  /// Check if email is verified
  bool isEmailVerified(String email) {
    final data = _verificationCache[email];
    return data != null && data.isVerified && data.type == VerificationType.email;
  }

  /// Resend verification code
  Future<bool> resendVerification(String target, VerificationType type) async {
    switch (type) {
      case VerificationType.sms:
        return await sendSMSVerification(target);
      case VerificationType.email:
        return await sendEmailVerification(target);
    }
  }

  /// Clear verification data
  void clearVerificationData(String target) {
    _verificationCache.remove(target);
    notifyListeners();
  }

  /// Get remaining time for verification (cooldown)
  Duration? getRemainingTime(String target) {
    final cooldownEnd = _resendCooldowns[target];
    if (cooldownEnd == null) return null;
    
    final remaining = cooldownEnd.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Get verification code expiration time
  Duration? getCodeExpirationTime(String target) {
    final data = _verificationCache[target];
    if (data == null) return null;
    
    final remaining = data.expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void dispose() {
    _verificationCache.clear();
    _resendCooldowns.clear();
    super.dispose();
  }
}
