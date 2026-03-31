import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../services/auth_service.dart';
import '../../services/verification_service.dart';
import '../../services/connectivity_service.dart';
import '../../models/user_model.dart';
import '../../models/driver_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/verification_widgets.dart';
import 'terms_and_conditions_screen.dart';
import '../../widgets/barangay_selector.dart';
import '../../models/barangay_model.dart';
import '../../utils/app_theme.dart';
import '../../models/barangay_model.dart';
import '../../widgets/tricycle_logo.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

enum DriverRegistrationStep {
  userInfo,
  verification,
  vehicleInfo,
  complete,
}

class DriverRegisterScreenWithVerification extends StatefulWidget {
  const DriverRegisterScreenWithVerification({super.key});

  @override
  State<DriverRegisterScreenWithVerification> createState() => _DriverRegisterScreenWithVerificationState();
}

class _DriverRegisterScreenWithVerificationState extends State<DriverRegisterScreenWithVerification> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _tricyclePlateController = TextEditingController();
  final _driverLicenseController = TextEditingController();

  DriverRegistrationStep _currentStep = DriverRegistrationStep.userInfo;
  VerificationType _selectedVerificationType = VerificationType.email;
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isVerificationLoading = false;
  bool _isScanningLicense = false;
  String? _verificationError;
  String _verificationCode = '';
  bool _agreedToTerms = false;
  BarangayModel? _selectedBarangay;

  XFile? _plateNumberImage;
  XFile? _licenseNumberImage;

  late VerificationService _verificationService;

  @override
  void initState() {
    super.initState();
    _verificationService = VerificationService();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _tricyclePlateController.dispose();
    _driverLicenseController.dispose();
    _verificationService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isPlateNumber) async {
    final ImagePicker picker = ImagePicker();
    try {
      // Show source selection dialog
      final ImageSource? source = await SnackbarHelper.showImageSourceDialog(context);
      
      if (source == null) return; // User cancelled
      
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          if (isPlateNumber) {
            _plateNumberImage = image;
          } else {
            _licenseNumberImage = image;
          }
        });
        
        if (!isPlateNumber) {
          _processLicenseImage(image.path);
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Failed to capture image');
    }
  }

  Future<void> _processLicenseImage(String imagePath) async {
    setState(() => _isScanningLicense = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning license details...'), duration: Duration(seconds: 2)),
      );
    }
    
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      String extractedLicense = '';
      
      final RegExp licenseRegExp = RegExp(r'[A-Z0-9]{3}-?[0-9]{2}-?[0-9]{6}');
      
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final text = line.text.trim();
          
          if (licenseRegExp.hasMatch(text)) {
            extractedLicense = licenseRegExp.firstMatch(text)?.group(0) ?? '';
            break;
          }
        }
        if (extractedLicense.isNotEmpty) break;
      }
      
      textRecognizer.close();

      if (extractedLicense.isNotEmpty && mounted) {
        setState(() {
          _driverLicenseController.text = extractedLicense;
        });
        SnackbarHelper.showSuccess(context, 'Auto-filled License Number: $extractedLicense');
      } else if (mounted) {
         SnackbarHelper.showError(context, 'Could not detect License Number. Please enter manually.');
      }
      
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Failed to scan license image.');
    } finally {
      if (mounted) setState(() => _isScanningLicense = false);
    }
  }

  Future<void> _proceedToVerification() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBarangay == null) {
      SnackbarHelper.showError(context, 'Please select your barangay');
      return;
    }

    if (!_agreedToTerms) {
      if (mounted) {
        final agreed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => const TermsAndConditionsScreen(userRole: 'driver'),
          ),
        );
        if (agreed != true) return;
        setState(() => _agreedToTerms = true);
      }
    }

    setState(() => _isLoading = true);

    if (_selectedBarangay == null) {
      SnackbarHelper.showError(context, 'Please select your barangay');
      setState(() => _isLoading = false);
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
      
      // Check connectivity before proceeding
      if (!await connectivityService.checkConnectivity(context)) {
        setState(() => _isLoading = false);
        return;
      }
      
      // Check if email or phone is already registered before proceeding
      await authService.checkIfEmailOrPhoneExists(
        _emailController.text.trim(),
        _phoneController.text.trim(),
      );
      
      setState(() => _currentStep = DriverRegistrationStep.verification);
      await _sendVerification();
    } catch (e) {
      if (mounted) {
        final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
        final errorMessage = connectivityService.getErrorMessage(e);
        SnackbarHelper.showError(context, errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendVerification() async {
    setState(() {
      _isVerificationLoading = true;
      _verificationError = null;
    });

    try {
      bool success = false;
      if (_selectedVerificationType == VerificationType.sms) {
        success = await _verificationService.sendSMSVerification(_phoneController.text.trim());
      } else {
        success = await _verificationService.sendEmailVerification(_emailController.text.trim());
      }

      if (success) {
        SnackbarHelper.showSuccess(context, 'Verification code sent!');
      } else {
        throw Exception('Failed to send verification code.');
      }
    } catch (e) {
      setState(() => _verificationError = e.toString());
    } finally {
      setState(() => _isVerificationLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationCode.length != 6) {
      setState(() => _verificationError = 'Enter 6-digit code');
      return;
    }

    setState(() {
      _isVerificationLoading = true;
      _verificationError = null;
    });

    try {
      bool success = false;
      if (_selectedVerificationType == VerificationType.sms) {
        success = await _verificationService.verifySMSCode(_phoneController.text.trim(), _verificationCode);
      } else {
        success = await _verificationService.verifyEmailCode(_emailController.text.trim(), _verificationCode);
      }

      if (success) {
        setState(() => _currentStep = DriverRegistrationStep.vehicleInfo);
      } else {
        setState(() => _verificationError = 'Invalid code. Try again.');
      }
    } catch (e) {
      setState(() => _verificationError = 'Verification failed.');
    } finally {
      setState(() => _isVerificationLoading = false);
    }
  }

  Future<void> _completeRegistration() async {
    if (_plateNumberImage == null || _licenseNumberImage == null) {
      SnackbarHelper.showError(context, 'Please capture both Plate and License photos');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
      
      // Check connectivity before proceeding
      if (!await connectivityService.checkConnectivity(context)) {
        setState(() => _isLoading = false);
        return;
      }
      
      final firestoreService = FirestoreService();
      
      // Create auth user - skip exists check since it was already done in _proceedToVerification
      await authService.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: UserRole.driver,
        barangayId: _selectedBarangay!.id,
        barangayName: _selectedBarangay!.name,
        skipExistsCheck: true,
      );

      // Upload documents
      final plateUrl = await firestoreService.uploadDriverDocument(
        authService.currentUser!.uid, 'plate', _plateNumberImage!
      );
      final licenseUrl = await firestoreService.uploadDriverDocument(
        authService.currentUser!.uid, 'license', _licenseNumberImage!
      );

      // Create driver profile
      final driverModel = DriverModel(
        id: authService.currentUser!.uid,
        userId: authService.currentUser!.uid,
        name: _nameController.text.trim(),
        vehicleType: 'Tricycle',
        plateNumber: _tricyclePlateController.text.trim(),
        licenseNumber: _driverLicenseController.text.trim(),
        plateNumberImageUrl: plateUrl,
        licenseNumberImageUrl: licenseUrl,
        barangayId: _selectedBarangay!.id,
        barangayName: _selectedBarangay!.name,
        tricyclePlateNumber: _tricyclePlateController.text.trim(),
        driverLicenseNumber: _driverLicenseController.text.trim(),
        isApproved: false,
        isActive: false,
      );

      await firestoreService.createDriverProfile(driverModel);

      setState(() => _currentStep = DriverRegistrationStep.complete);

    } catch (e) {
      if (mounted) {
        final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
        final errorMessage = connectivityService.getErrorMessage(e);
        SnackbarHelper.showError(context, 'Registration failed: $errorMessage');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_currentStep == DriverRegistrationStep.complete ? '' : 'Be a Driver'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_currentStep == DriverRegistrationStep.userInfo) {
              Navigator.pop(context);
            } else if (_currentStep == DriverRegistrationStep.verification) {
              setState(() => _currentStep = DriverRegistrationStep.userInfo);
            } else if (_currentStep == DriverRegistrationStep.vehicleInfo) {
              setState(() => _currentStep = DriverRegistrationStep.verification);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildCurrentStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case DriverRegistrationStep.userInfo:
        return _buildUserInfoStep();
      case DriverRegistrationStep.verification:
        return _buildVerificationStep();
      case DriverRegistrationStep.vehicleInfo:
        return _buildVehicleInfoStep();
      case DriverRegistrationStep.complete:
        return _buildCompleteStep();
    }
  }

  Widget _buildUserInfoStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),

          // Brand hero
          Center(
            child: Column(
              children: [
                const TricycleLogo(size: 140, showText: false, showShadow: false, plain: true),
                const SizedBox(height: 20),
                const Text(
                  'Become a Pasakay Driver',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drive with confidence and earn more every day',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 36),

          _buildInputField(
            label: 'Full Name',
            controller: _nameController,
            hint: 'Juan Dela Cruz',
            icon: Icons.person_outline_rounded,
            validator: (v) => (v == null || v.isEmpty) ? 'Name is required' : null,
          ),
          const SizedBox(height: 20),
          _buildInputField(
            label: 'Email Address',
            controller: _emailController,
            hint: 'juan@driver.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || !v.contains('@')) ? 'Valid email is required' : null,
          ),
          const SizedBox(height: 20),
          _buildInputField(
            label: 'Phone Number',
            controller: _phoneController,
            hint: '09xxxxxxxxx',
            icon: Icons.phone_android_rounded,
            keyboardType: TextInputType.phone,
            validator: (v) => (v == null || v.length < 11) ? 'Enter valid PH number' : null,
          ),
          const SizedBox(height: 20),

          const Text(
            'Barangay',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 8),
          BarangaySelector(
            selectedBarangay: _selectedBarangay,
            onBarangaySelected: (barangay) {
              setState(() {
                _selectedBarangay = barangay;
              });
            },
          ),
          const SizedBox(height: 20),

          _buildInputField(
            label: 'Password',
            controller: _passwordController,
            hint: 'Minimum 8 characters',
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            validator: (v) => (v == null || v.length < 8) ? 'Password too short' : null,
          ),
          const SizedBox(height: 20),
          _buildInputField(
            label: 'Confirm Password',
            controller: _confirmPasswordController,
            hint: 'Repeat your password',
            icon: Icons.lock_reset_rounded,
            isPassword: true,
            validator: (v) => (v != _passwordController.text) ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 32),

          InkWell(
            onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Checkbox(
                  value: _agreedToTerms,
                  onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                  activeColor: AppTheme.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Color(0xFF4A4A4A)),
                      children: [
                        const TextSpan(text: 'I agree to the '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const TermsAndConditionsScreen(userRole: 'driver')),
                            ),
                            child: const Text(
                              'Driver Terms & Conditions',
                              style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: (_isLoading || !_agreedToTerms) ? null : _proceedToVerification,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 64),
              shape: const StadiumBorder(),
              elevation: 8,
              shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
            ),
            child: _isLoading 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildVerificationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Text(
          'Verification Code 🔐',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ve sent a verification code to\n${_emailController.text}',
          style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
        ),
        const SizedBox(height: 48),

        VerificationCodeInput(
          onCodeChanged: (code) {
            setState(() {
              _verificationCode = code;
              _verificationError = null;
            });
            if (code.length == 6) _verifyCode();
          },
          onResend: _sendVerification,
          isLoading: _isVerificationLoading,
          errorMessage: _verificationError,
          remainingTime: _verificationService.getRemainingTime(_emailController.text.trim()),
        ),

        const SizedBox(height: 40),
        
        ElevatedButton(
          onPressed: (_isVerificationLoading || _verificationCode.length != 6) ? null : _verifyCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 64),
            shape: const StadiumBorder(),
            elevation: 8,
            shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
          ),
          child: _isVerificationLoading 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Verify Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
      ],
    );
  }

  Widget _buildVehicleInfoStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Vehicle Documents',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload your documents for validation',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 40),

          _buildImageUploadCard(
            title: 'Tricycle Plate',
            subtitle: 'Capture your plate number',
            icon: Icons.confirmation_number_rounded,
            image: _plateNumberImage,
            onTap: () => _pickImage(true),
          ),
          const SizedBox(height: 20),
          _buildImageUploadCard(
            title: 'Driver\'s License',
            subtitle: 'Capture your valid license',
            icon: Icons.badge_rounded,
            image: _licenseNumberImage,
            onTap: () => _pickImage(false),
          ),

          const SizedBox(height: 32),

          _buildInputField(
            label: 'Plate Number',
            controller: _tricyclePlateController,
            hint: 'ABC-1234',
            icon: Icons.confirmation_number_rounded,
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 20),
          _buildInputField(
            label: 'License Number',
            controller: _driverLicenseController,
            hint: 'D12-34-567890',
            icon: Icons.badge_rounded,
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),

          const SizedBox(height: 40),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreenLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: AppTheme.primaryGreen, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Approval Notice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        'Your documents will be reviewed by our team. Activation usually takes 24-48 hours.',
                        style: TextStyle(fontSize: 13, color: AppTheme.primaryGreen.withOpacity(0.8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: _isLoading ? null : _completeRegistration,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 64),
              shape: const StadiumBorder(),
              elevation: 8,
              shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
            ),
            child: _isLoading 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Submit Application', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    return Column(
      children: [
        const SizedBox(height: 100),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.primaryGreenLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.pending_actions_rounded, size: 80, color: AppTheme.primaryGreen),
        ),
        const SizedBox(height: 40),
        const Text(
          'Processing!',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 16),
        Text(
          'Thank you, ${_nameController.text}!\nYour application is now being reviewed.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600, height: 1.6),
        ),
        const SizedBox(height: 60),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pushReplacementNamed('/driver'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 64),
            shape: const StadiumBorder(),
            elevation: 8,
            shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
          ),
          child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
      ],
    );
  }

  Widget _buildStepProgress(int current) {
    return Row(
      children: List.generate(4, (index) {
        bool isActive = index <= current;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primaryGreen : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword && (label.contains('Confirm') ? _obscureConfirmPassword : _obscurePassword),
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w500),
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
            suffixIcon: isPassword ? IconButton(
              icon: Icon((label.contains('Confirm') ? _obscureConfirmPassword : _obscurePassword) ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.grey, size: 20),
              onPressed: () => setState(() {
                if (label.contains('Confirm')) {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                } else {
                  _obscurePassword = !_obscurePassword;
                }
              }),
            ) : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFF1F1F1), width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.red, width: 2)),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildImageUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required XFile? image,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: image != null ? AppTheme.primaryGreen.withOpacity(0.3) : const Color(0xFFF1F1F1), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: image != null ? AppTheme.primaryGreenLight : const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: image != null 
                  ? FutureBuilder<Uint8List>(
                      future: image.readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen),
                            ),
                          );
                        }
                        return const Center(child: CircularProgressIndicator());
                      },
                    )
                  : Icon(icon, color: Colors.grey.shade400, size: 30),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(image != null ? 'Tap to change photo' : subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              ),
              if (image != null)
                const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 24)
              else
                Icon(Icons.add_a_photo_rounded, color: Colors.grey.shade300, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarangayPicker extends StatefulWidget {
  @override
  State<_BarangayPicker> createState() => _BarangayPickerState();
}

class _BarangayPickerState extends State<_BarangayPicker> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  List<BarangayModel> _barangays = [];
  List<BarangayModel> _filteredBarangays = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBarangays();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBarangays() async {
    try {
      final data = await _firestoreService.getAllBarangays();
      if (mounted) {
        setState(() {
          _barangays = data.where((b) => b.isActive).toList();
          _filteredBarangays = _barangays;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load barangays';
          _isLoading = false;
        });
      }
    }
  }

  void _filterBarangays(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _filteredBarangays = _barangays.where((b) {
        final name = b.name.toLowerCase();
        final municipality = b.municipality.toLowerCase();
        return name.contains(_searchQuery) || municipality.contains(_searchQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        padding: const EdgeInsets.all(24),
        height: 600,
        child: Column(
          children: [
            const Text(
              'Select Barangay',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              onChanged: _filterBarangays,
              decoration: InputDecoration(
                hintText: 'Search barangay...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterBarangays('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.primaryGreen),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredBarangays.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? (_error ?? 'No active barangays found') : 'No results found for "$_searchQuery"',
                            style: TextStyle(color: Colors.grey.shade500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredBarangays.length,
                      itemBuilder: (context, index) {
                        final b = _filteredBarangays[index];
                        return ListTile(
                          title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(b.municipality),
                          onTap: () => Navigator.pop(context, b),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
