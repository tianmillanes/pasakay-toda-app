import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';
import '../../services/verification_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/id_verification_service.dart';
import '../../models/user_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/verification_widgets.dart';
import 'terms_and_conditions_screen.dart';
import '../../utils/app_theme.dart';
import '../../widgets/tricycle_logo.dart';

enum RegistrationStep {
  userInfo,
  verification,
  idUpload,
  selfie,
  complete,
}

class PassengerRegisterScreenWithVerification extends StatefulWidget {
  const PassengerRegisterScreenWithVerification({super.key});

  @override
  State<PassengerRegisterScreenWithVerification> createState() =>
      _PassengerRegisterScreenWithVerificationState();
}

class _PassengerRegisterScreenWithVerificationState
    extends State<PassengerRegisterScreenWithVerification> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  RegistrationStep _currentStep = RegistrationStep.userInfo;
  VerificationType _selectedVerificationType = VerificationType.email;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isVerificationLoading = false;
  String? _verificationError = '';
  String _verificationCode = '';
  bool _agreedToTerms = false;

  // ID Verification — store raw bytes so Image.memory() works on Android, iOS, and Web
  String _selectedIdType = 'National ID (PhilSys)';
  Uint8List? _idBytes;
  Uint8List? _selfieBytes;
  bool _isUploadingId = false;
  String? _registeredUserId;

  static const List<String> _idTypes = [
    'National ID (PhilSys)',
    'PhilHealth ID',
    'SSS ID',
    'GSIS ID',
    'Voter\'s ID',
    "Driver's License",
    'Passport',
    'Postal ID',
    'PRC ID',
    'TIN ID',
  ];

  late VerificationService _verificationService;
  final ImagePicker _picker = ImagePicker();

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
    _verificationService.dispose();
    super.dispose();
  }

  Future<void> _proceedToVerification() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      if (mounted) {
        final agreed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) =>
                const TermsAndConditionsScreen(userRole: 'passenger'),
          ),
        );
        if (agreed != true) return;
        setState(() => _agreedToTerms = true);
      }
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      await authService.checkIfEmailOrPhoneExists(
        _emailController.text.trim(),
        _phoneController.text.trim(),
      );

      setState(() => _currentStep = RegistrationStep.verification);
      await _sendVerification();
    } catch (e) {
      if (mounted) {
        final connectivityService =
            Provider.of<ConnectivityService>(context, listen: false);
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
        success = await _verificationService
            .sendSMSVerification(_phoneController.text.trim());
      } else {
        success = await _verificationService
            .sendEmailVerification(_emailController.text.trim());
      }

      if (success) {
        if (mounted) SnackbarHelper.showSuccess(context, 'Verification code sent!');
      } else {
        throw 'Failed to send verification code. Please check your internet or try again later.';
      }
    } catch (e) {
      String errorMessage = e.toString();
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring(11);
      }
      setState(() => _verificationError = errorMessage);
      if (mounted) SnackbarHelper.showError(context, errorMessage);
    } finally {
      setState(() => _isVerificationLoading = false);
    }
  }

  Future<void> _resendVerification() async {
    setState(() {
      _isVerificationLoading = true;
      _verificationError = null;
    });

    try {
      final target = _selectedVerificationType == VerificationType.sms
          ? _phoneController.text.trim()
          : _emailController.text.trim();

      final success = await _verificationService.resendVerification(
          target, _selectedVerificationType);

      if (success) {
        if (mounted) SnackbarHelper.showSuccess(context, 'Verification code resent!');
      } else {
        throw Exception('Failed to resend verification code.');
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
        success = await _verificationService.verifySMSCode(
            _phoneController.text.trim(), _verificationCode);
      } else {
        success = await _verificationService.verifyEmailCode(
            _emailController.text.trim(), _verificationCode);
      }

      if (success) {
        await _completeRegistration();
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
    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final connectivityService =
          Provider.of<ConnectivityService>(context, listen: false);

      if (!await connectivityService.checkConnectivity(context)) {
        setState(() => _isLoading = false);
        return;
      }

      await authService.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: UserRole.passenger,
        barangayId: '',
        barangayName: '',
        skipExistsCheck: true,
      );

      // Get the registered UID
      _registeredUserId = authService.currentUser?.uid;

      // Proceed to ID upload step
      setState(() => _currentStep = RegistrationStep.idUpload);
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        errorMessage =
            errorMessage.replaceAll(RegExp(r'\[firebase_auth/[^\]]+\]'), '').trim();
        SnackbarHelper.showError(context, 'Registration failed: $errorMessage');
        setState(() => _currentStep = RegistrationStep.userInfo);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickIdImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() => _idBytes = bytes);
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Could not open camera/gallery: $e');
    }
  }

  Future<void> _takeSelfie() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1280,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() => _selfieBytes = bytes);
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Could not open front camera: $e');
    }
  }

  Future<void> _submitIdVerification() async {
    if (_idBytes == null) {
      SnackbarHelper.showError(context, 'Please take a photo of your ID first.');
      return;
    }
    setState(() => _currentStep = RegistrationStep.selfie);
  }

  Future<void> _submitSelfieAndFinish() async {
    if (_selfieBytes == null) {
      SnackbarHelper.showError(context, 'Please take a selfie first.');
      return;
    }

    setState(() => _isUploadingId = true);

    try {
      final uid = _registeredUserId;
      if (uid == null) throw Exception('User ID not found.');

      await IdVerificationService.submitVerification(
        userId: uid,
        idType: _selectedIdType,
        idImageBytes: _idBytes!,
        selfieImageBytes: _selfieBytes!,
      );

      setState(() => _currentStep = RegistrationStep.complete);
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(
            context, 'Failed to submit ID. You can submit it later in your profile.');
        setState(() => _currentStep = RegistrationStep.complete);
      }
    } finally {
      if (mounted) setState(() => _isUploadingId = false);
    }
  }

  void _skipIdVerification() {
    setState(() => _currentStep = RegistrationStep.complete);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        leading: _buildBackButton(),
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

  String _getAppBarTitle() {
    switch (_currentStep) {
      case RegistrationStep.userInfo:
        return 'Fill Personal Info';
      case RegistrationStep.verification:
        return 'Verify Email';
      case RegistrationStep.idUpload:
        return 'ID Verification';
      case RegistrationStep.selfie:
        return 'Face Verification';
      case RegistrationStep.complete:
        return '';
    }
  }

  Widget _buildBackButton() {
    switch (_currentStep) {
      case RegistrationStep.verification:
        return IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => setState(() => _currentStep = RegistrationStep.userInfo),
        );
      case RegistrationStep.idUpload:
        // Can't go back after registration is done
        return const SizedBox.shrink();
      case RegistrationStep.selfie:
        return IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => setState(() => _currentStep = RegistrationStep.idUpload),
        );
      default:
        return IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        );
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case RegistrationStep.userInfo:
        return _buildUserInfoStep();
      case RegistrationStep.verification:
        return _buildVerificationStep();
      case RegistrationStep.idUpload:
        return _buildIdUploadStep();
      case RegistrationStep.selfie:
        return _buildSelfieStep();
      case RegistrationStep.complete:
        return _buildCompleteStep();
    }
  }

  // ─── STEP 1: User Info ────────────────────────────────────────────────────

  Widget _buildUserInfoStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                const TricycleLogo(size: 130, showText: false, showShadow: false, plain: true),
                const SizedBox(height: 20),
                const Text(
                  'Create Passenger Profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Experience seamless rides with Pasakay',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          _buildInputField(label: 'Full Name', controller: _nameController, hint: 'Juan Dela Cruz', icon: Icons.person_outline_rounded, validator: (v) {
            if (v == null || v.isEmpty) return 'Please enter your name';
            if (v.length < 2) return 'Name is too short';
            return null;
          }),
          const SizedBox(height: 20),
          _buildInputField(label: 'Email Address', controller: _emailController, hint: 'juan@example.com', icon: Icons.alternate_email_rounded, keyboardType: TextInputType.emailAddress, validator: (v) {
            if (v == null || v.isEmpty) return 'Please enter your email';
            if (!v.contains('@') || !v.contains('.')) return 'Invalid email address';
            return null;
          }),
          const SizedBox(height: 20),
          _buildInputField(label: 'Phone Number', controller: _phoneController, hint: '09xxxxxxxxx', icon: Icons.phone_android_rounded, keyboardType: TextInputType.phone, validator: (v) {
            if (v == null || v.isEmpty) return 'Please enter phone number';
            if (v.length < 11) return 'Enter valid 11-digit number';
            return null;
          }),
          const SizedBox(height: 20),
          _buildInputField(label: 'Password', controller: _passwordController, hint: 'Minimum 8 characters', icon: Icons.lock_outline_rounded, isPassword: true, validator: (v) {
            if (v == null || v.isEmpty) return 'Please enter password';
            if (v.length < 8) return 'Password must be at least 8 characters';
            return null;
          }),
          const SizedBox(height: 20),
          _buildInputField(label: 'Confirm Password', controller: _confirmPasswordController, hint: 'Repeat your password', icon: Icons.lock_reset_rounded, isPassword: true, validator: (v) {
            if (v != _passwordController.text) return 'Passwords do not match';
            return null;
          }),
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
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TermsAndConditionsScreen(userRole: 'passenger'))),
                            child: const Text('Terms & Conditions', style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13)),
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

  // ─── STEP 2: Email Verification ───────────────────────────────────────────

  Widget _buildVerificationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Text('Enter OTP Code 🔐', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 12),
        Text("Check your email! We've sent a one-time\ncode to verify your account.", style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5)),
        const SizedBox(height: 48),
        VerificationCodeInput(
          onCodeChanged: (code) {
            setState(() {
              _verificationCode = code;
              _verificationError = null;
            });
            if (code.length == 6) _verifyCode();
          },
          onResend: _resendVerification,
          isLoading: _isVerificationLoading,
          errorMessage: _verificationError,
          remainingTime: _verificationService.getRemainingTime(_emailController.text.trim()),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: (_isVerificationLoading || _verificationCode.length != 6) ? null : _verifyCode,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen, minimumSize: const Size(double.infinity, 60), shape: const StadiumBorder()),
          child: _isVerificationLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('Verify Account', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // ─── STEP 3: Government ID Upload ─────────────────────────────────────────

  Widget _buildIdUploadStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        _buildStepHeader(
          icon: Icons.badge_rounded,
          title: 'Upload Government ID',
          subtitle: 'Take a clear photo of your valid government-issued ID. Keep all corners visible.',
        ),
        const SizedBox(height: 8),
        // Skip link
        Center(
          child: TextButton(
            onPressed: _skipIdVerification,
            child: Text('Skip for now (verify later)', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 20),

        // ID Type Dropdown
        const Text('ID Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFF1F1F1), width: 1.5),
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedIdType,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryGreen),
              items: _idTypes.map((type) => DropdownMenuItem(value: type, child: Text(type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)))).toList(),
              onChanged: (v) => setState(() => _selectedIdType = v!),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ID Image preview area
        const Text('ID Photo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showImageSourceSheet(forId: true),
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _idBytes != null ? AppTheme.primaryGreen : const Color(0xFFE0E0E0),
                width: _idBytes != null ? 2 : 1.5,
              ),
            ),
            child: _idBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(19),
                    child: Image.memory(_idBytes!, fit: BoxFit.cover),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_rounded, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('Tap to capture or upload ID', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Camera or Gallery', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
          ),
        ),

        if (_idBytes != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _showImageSourceSheet(forId: true),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retake / Change'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryGreen),
          ),
        ],

        const SizedBox(height: 16),
        // Tips
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppTheme.primaryGreenLight, borderRadius: BorderRadius.circular(14)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(Icons.lightbulb_rounded, color: AppTheme.primaryGreen, size: 16), SizedBox(width: 6), Text('Tips for a good photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryGreen))]),
              SizedBox(height: 6),
              Text('• Ensure all 4 corners of the ID are visible\n• Use good lighting — no glare or shadows\n• Keep the ID flat and steady\n• Make sure all text is readable', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.6)),
            ],
          ),
        ),

        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _idBytes == null ? null : _submitIdVerification,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: const StadiumBorder(),
            elevation: 4,
          ),
          child: const Text('Next: Take Selfie', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ─── STEP 4: Selfie / Face Verification ───────────────────────────────────

  Widget _buildSelfieStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        _buildStepHeader(
          icon: Icons.face_retouching_natural_rounded,
          title: 'Take a Selfie',
          subtitle: 'We need a clear photo of your face to match against your ID. Use your front camera in good lighting.',
        ),
        const SizedBox(height: 24),

        // Selfie preview
        GestureDetector(
          onTap: _takeSelfie,
          child: Container(
            height: 260,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _selfieBytes != null ? AppTheme.primaryGreen : const Color(0xFFE0E0E0),
                width: _selfieBytes != null ? 2 : 1.5,
              ),
            ),
            child: _selfieBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(19),
                    child: Image.memory(_selfieBytes!, fit: BoxFit.cover),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(color: AppTheme.primaryGreenLight, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_front_rounded, size: 50, color: AppTheme.primaryGreen),
                      ),
                      const SizedBox(height: 16),
                      Text('Tap to open front camera', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Face the camera directly', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
          ),
        ),

        if (_selfieBytes != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _takeSelfie,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retake Selfie'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primaryGreen),
          ),
        ],

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppTheme.primaryGreenLight, borderRadius: BorderRadius.circular(14)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(Icons.lightbulb_rounded, color: AppTheme.primaryGreen, size: 16), SizedBox(width: 6), Text('Selfie tips', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryGreen))]),
              SizedBox(height: 6),
              Text('• Look directly at the camera\n• Remove sunglasses or hats\n• Ensure your face is fully visible\n• Use good, even lighting', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.6)),
            ],
          ),
        ),

        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: (_selfieBytes == null || _isUploadingId) ? null : _submitSelfieAndFinish,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: const StadiumBorder(),
            elevation: 4,
          ),
          child: _isUploadingId
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Uploading...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  ],
                )
              : const Text('Submit for Verification', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ─── STEP 5: Complete ─────────────────────────────────────────────────────

  Widget _buildCompleteStep() {
    final submitted = _idBytes != null && _selfieBytes != null;
    return Column(
      children: [
        const SizedBox(height: 80),
        Container(
          width: 130,
          height: 130,
          decoration: BoxDecoration(color: AppTheme.primaryGreenLight, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, size: 90, color: AppTheme.primaryGreen),
        ),
        const SizedBox(height: 40),
        const Text('Account Created!', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 16),
        Text(
          submitted
              ? 'Welcome, ${_nameController.text}!\nYour ID is under review. You can use the app while waiting for admin approval.'
              : 'Welcome, ${_nameController.text}!\nYou can verify your ID anytime from your profile.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600, height: 1.6),
        ),
        if (submitted) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ID verification is pending admin review. You\'ll be notified once approved.',
                    style: TextStyle(fontSize: 13, color: Colors.orange.shade800, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 60),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 64),
            shape: const StadiumBorder(),
            elevation: 8,
            shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
          ),
          child: const Text('Go to Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _showImageSourceSheet({required bool forId}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text('Choose Photo Source', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _sourceButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      onTap: () {
                        Navigator.pop(context);
                        if (forId) _pickIdImage(ImageSource.camera);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _sourceButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      onTap: () {
                        Navigator.pop(context);
                        if (forId) _pickIdImage(ImageSource.gallery);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.primaryGreenLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primaryGreen, size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
          ],
        ),
      ),
    );
  }

  Widget _buildStepHeader({required IconData icon, required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.primaryGreenLight, shape: BoxShape.circle),
          child: Icon(icon, color: AppTheme.primaryGreen, size: 28),
        ),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        Text(subtitle, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
      ],
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
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
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
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                        (label.contains('Confirm') ? _obscureConfirmPassword : _obscurePassword) ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        color: Colors.grey,
                        size: 20),
                    onPressed: () => setState(() {
                      if (label.contains('Confirm')) {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      } else {
                        _obscurePassword = !_obscurePassword;
                      }
                    }),
                  )
                : null,
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
}
