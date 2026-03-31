import 'package:flutter/material.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  final String userRole; // 'passenger' or 'driver'

  const TermsAndConditionsScreen({
    super.key,
    required this.userRole,
  });

  @override
  State<TermsAndConditionsScreen> createState() => _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  bool _agreedToTerms = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Terms and Conditions'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Terms and Conditions for ${widget.userRole == 'passenger' ? 'Passengers' : 'Drivers'}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSection(
                          'Effective Date',
                          'These Terms and Conditions are effective as of the date of your registration with Pasakay.',
                        ),
                        _buildSection(
                          '1. Acceptance of Terms',
                          'By registering and using Pasakay, you agree to comply with these Terms and Conditions. If you do not agree, please do not use our service.',
                        ),
                        _buildSection(
                          '2. User Responsibilities',
                          widget.userRole == 'passenger'
                              ? '• Provide accurate and complete information during registration\n'
                                '• Maintain the confidentiality of your account credentials\n'
                                '• Use the service only for lawful purposes\n'
                                '• Treat drivers and other users with respect\n'
                                '• Pay the agreed fare promptly\n'
                            
                              : '• Provide accurate and complete information during registration\n'
                                '• Maintain a valid driver\'s license and vehicle registration\n'
                                '• Ensure your vehicle is safe and well-maintained\n'
                                '• Treat passengers with respect and professionalism\n'
                                '• Follow traffic laws and safety regulations\n'
                                '• Not engage in discriminatory behavior\n'
                                '• Maintain vehicle cleanliness and comfort',
                        ),
                        _buildSection(
                          '3. Safety and Security',
                          '• Pasakay prioritizes the safety of all users\n'
                          '• Users must not engage in harassment, violence, or illegal activities\n'
                          '• Any safety violations may result in account suspension or termination\n'
                          '• Report suspicious activity to our support team immediately',
                        ),
                        _buildSection(
                          '4. Payment and Charges',
                          widget.userRole == 'passenger'
                              ? '• Fares are calculated based on distance\n'
                                '• Payment must be made before or after the ride\n'
                                
                                '• Pasakay is not responsible for lost items in vehicles'
                              : '• Drivers receive payment based on completed rides\n'          
                                '• Drivers are responsible for vehicle maintenance costs',
                        ),
                        _buildSection(
                          '5. Liability and Disclaimers',
                          '• Pasakay is not liable for accidents, injuries, or damages during rides\n'
                          '• Users assume all risks associated with using the service\n'
                          '• Pasakay does not guarantee service availability\n'
                          '• We are not responsible for third-party actions',
                        ),
                        _buildSection(
                          '6. Prohibited Activities',
                          '• Harassment, discrimination, or abuse\n'
                          '• Illegal activities or substance use\n'
                          '• Fraudulent transactions or false information\n'
                          '• Sharing account credentials with others\n'
                          '• Attempting to manipulate ratings or reviews',
                        ),
                        _buildSection(
                          '7. Account Suspension and Termination',
                          '• Pasakay reserves the right to suspend or terminate accounts for violations\n'
                          '• Users will be notified of suspension reasons\n'                    
                          '• Termination is final in cases of serious violations',
                        ),
                        _buildSection(
                          '8. Privacy and Data Protection',
                          '• Your personal data is protected according to our Privacy Policy\n'
                          '• We collect data necessary for service operation\n'
                          '• Data is not shared with third parties without consent\n'
                          '• Users have the right to access and delete their data',
                        ),
                        _buildSection(
                          '9. Modifications to Terms',
                          'Pasakay reserves the right to modify these Terms and Conditions at any time. Users will be notified of significant changes. Continued use of the service constitutes acceptance of modified terms.',
                        ),
                        _buildSection(
                          '10. Governing Law',
                          'These Terms and Conditions are governed by the laws of the Philippines and subject to the jurisdiction of Philippine courts.',
                        ),
                        _buildSection(
                          '11. Contact Information',
                          'For questions or concerns about these Terms and Conditions, please contact our team at pasakaytoda@gmail.com',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
         
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D2D2D),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
