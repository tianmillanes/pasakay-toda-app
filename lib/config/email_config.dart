/// Email configuration for verification service
/// 
/// IMPORTANT: Credentials are now loaded from environment variables (.env file)
/// 
/// Setup Instructions:
/// 1. Copy .env.example to .env in project root
/// 2. Fill in your Gmail credentials
/// 3. Enable 2-factor authentication on your Gmail account
/// 4. Generate an App Password for this application
/// 5. Use the generated password in .env (not your regular Gmail password)
/// 
/// For Gmail setup:
/// 1. Go to Google Account settings
/// 2. Security > 2-Step Verification (enable if not already)
/// 3. App passwords > Generate new app password
/// 4. Use the generated password in .env file

import 'credentials_config.dart';

class EmailConfig {
  // SMTP Configuration for Gmail (from environment variables)
  static String get smtpHost => CredentialsConfig.smtpHost;
  static int get smtpPort => CredentialsConfig.smtpPort;
  
  // Email credentials (from environment variables - NEVER hardcoded!)
  static String get senderEmail => CredentialsConfig.emailAddress;
  static String get senderPassword => CredentialsConfig.emailPassword;
  static String get senderName => CredentialsConfig.emailSenderName;
  
  // Email templates
  static const String verificationSubject = 'Pasakay Toda - Email Verification Code';
  
  static String getVerificationEmailHtml(String code) {
    return '''
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background-color: #2D2D2D; color: white; padding: 20px; text-align: center;">
          <h1>Pasakay Toda</h1>
        </div>
        <div style="padding: 20px; background-color: #f5f5f5;">
          <h2>Email Verification</h2>
          <p>Thank you for registering with Pasakay Toda!</p>
          <p>Your verification code is:</p>
          <div style="background-color: white; padding: 20px; text-align: center; border-radius: 8px; margin: 20px 0;">
            <h1 style="color: #2D2D2D; font-size: 32px; letter-spacing: 8px; margin: 0;">$code</h1>
          </div>
          <p>This code will expire in 5 minutes.</p>
          <p>If you didn't request this code, please ignore this email.</p>
          <br>
          <p>Best regards,<br>The Pasakay Toda Team</p>
        </div>
        <div style="background-color: #2D2D2D; color: white; padding: 10px; text-align: center; font-size: 12px;">
          © 2024 Pasakay Toda. All rights reserved.
        </div>
      </div>
    ''';
  }
  
  // Validation
  static bool get isConfigured {
    return senderEmail != 'your-pasakay-app@gmail.com' && 
           senderPassword != 'your-app-password-here' &&
           senderEmail.isNotEmpty && 
           senderPassword.isNotEmpty;
  }
}
