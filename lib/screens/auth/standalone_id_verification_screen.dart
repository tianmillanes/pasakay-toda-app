import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';
import '../../services/id_verification_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/usability_helpers.dart';

class StandaloneIdVerificationScreen extends StatefulWidget {
  const StandaloneIdVerificationScreen({super.key});

  @override
  State<StandaloneIdVerificationScreen> createState() =>
      _StandaloneIdVerificationScreenState();
}

class _StandaloneIdVerificationScreenState
    extends State<StandaloneIdVerificationScreen> {
  int _currentStep = 0; // 0 = ID, 1 = Selfie, 2 = Complete

  String _selectedIdType = 'National ID (PhilSys)';

  // Store both XFile (for path reference) and bytes (for display & upload)
  // Using Uint8List makes Image.memory() work on Android, iOS, and Web equally
  Uint8List? _idBytes;
  Uint8List? _selfieBytes;
  bool _isUploadingId = false;

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

  final ImagePicker _picker = ImagePicker();

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
    setState(() => _currentStep = 1);
  }

  Future<void> _submitSelfieAndFinish() async {
    if (_selfieBytes == null) {
      SnackbarHelper.showError(context, 'Please take a selfie first.');
      return;
    }

    setState(() => _isUploadingId = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final uid = authService.currentUser?.uid;
      if (uid == null) throw Exception('User ID not found. Please log in again.');

      await IdVerificationService.submitVerification(
        userId: uid,
        idType: _selectedIdType,
        idImageBytes: _idBytes!,
        selfieImageBytes: _selfieBytes!,
      );

      // Refresh user model so dashboard sees 'pending' status immediately
      await authService.refreshUserData();
      setState(() => _currentStep = 2);
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to submit ID. Try again later.');
      }
    } finally {
      if (mounted) setState(() => _isUploadingId = false);
    }
  }

  void _showImageSourceSheet({required bool forId}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              const Text('Choose Photo Source',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _sourceButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      onTap: () {
                        Navigator.pop(context);
                        _pickIdImage(ImageSource.camera);
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
                        _pickIdImage(ImageSource.gallery);
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

  Widget _sourceButton(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
            color: AppTheme.primaryGreenLight,
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primaryGreen, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen)),
          ],
        ),
      ),
    );
  }

  Widget _buildStepHeader(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
              color: AppTheme.primaryGreenLight, shape: BoxShape.circle),
          child: Icon(icon, color: AppTheme.primaryGreen, size: 28),
        ),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyle(
                fontSize: 14, color: Colors.grey.shade600, height: 1.5)),
      ],
    );
  }

  Widget _buildImagePreviewBox({
    required Uint8List? bytes,
    required VoidCallback onTap,
    required double height,
    required IconData emptyIcon,
    required String emptyLabel,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: bytes != null ? AppTheme.primaryGreen : const Color(0xFFE0E0E0),
            width: bytes != null ? 2 : 1.5,
          ),
        ),
        child: bytes != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(18),
                // Image.memory works on Android, iOS, and Web — no platform checks needed
                child: Image.memory(bytes, fit: BoxFit.cover),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(emptyIcon, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(emptyLabel,
                      style: TextStyle(
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }

  Widget _buildIdUploadStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepHeader(
          icon: Icons.badge_rounded,
          title: 'Upload Government ID',
          subtitle:
              'Choose your barangay and upload a clear photo of your valid government-issued ID.',
        ),
        const SizedBox(height: 24),
        const Text('ID Type',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A))),
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
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.primaryGreen),
              items: _idTypes
                  .map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(type,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedIdType = v!),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const SizedBox(height: 24),
        const Text('ID Photo',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A))),
        const SizedBox(height: 8),
        _buildImagePreviewBox(
          bytes: _idBytes,
          onTap: () => _showImageSourceSheet(forId: true),
          height: 200,
          emptyIcon: Icons.add_photo_alternate_rounded,
          emptyLabel: 'Tap to capture or upload ID',
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
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppTheme.primaryGreenLight,
              borderRadius: BorderRadius.circular(14)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.lightbulb_rounded,
                    color: AppTheme.primaryGreen, size: 16),
                SizedBox(width: 6),
                Text('Tips for a good photo',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.primaryGreen))
              ]),
              SizedBox(height: 6),
              Text(
                  '• Ensure all 4 corners of the ID are visible\n• Use good lighting — no glare or shadows\n• Keep the ID flat and steady\n• Make sure all text is readable',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.6)),
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
          ),
          child: const Text('Next: Take Selfie',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSelfieStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStepHeader(
          icon: Icons.face_retouching_natural_rounded,
          title: 'Take a Selfie',
          subtitle:
              'We need a clear photo of your face to match against your ID. Use your front camera in good lighting.',
        ),
        const SizedBox(height: 24),
        _buildImagePreviewBox(
          bytes: _selfieBytes,
          onTap: _takeSelfie,
          height: 260,
          emptyIcon: Icons.camera_front_rounded,
          emptyLabel: 'Tap to open front camera',
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
          decoration: BoxDecoration(
              color: AppTheme.primaryGreenLight,
              borderRadius: BorderRadius.circular(14)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.lightbulb_rounded,
                    color: AppTheme.primaryGreen, size: 16),
                SizedBox(width: 6),
                Text('Selfie tips',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.primaryGreen))
              ]),
              SizedBox(height: 6),
              Text(
                  '• Look directly at the camera\n• Remove sunglasses or hats\n• Ensure your face is fully visible\n• Use good, even lighting',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.6)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed:
              (_selfieBytes == null || _isUploadingId) ? null : _submitSelfieAndFinish,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: const StadiumBorder(),
          ),
          child: _isUploadingId
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Submit Verification',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildCompleteStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 130,
          height: 130,
          decoration:
              const BoxDecoration(color: AppTheme.primaryGreenLight, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded,
              size: 90, color: AppTheme.primaryGreen),
        ),
        const SizedBox(height: 40),
        const Text('Submitted Successfully!',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade200)),
          child: Row(children: [
            Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    'Your ID is now pending review by an admin. You will be notified once approved.',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                        height: 1.4))),
          ]),
        ),
        const SizedBox(height: 48),
        ElevatedButton(
          // Pop back — dashboard listens to AuthService and will auto-swap to the Pending wall
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 64),
            shape: const StadiumBorder(),
          ),
          child: const Text('Go to Dashboard',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Verify Account',
            style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _currentStep == 0
              ? _buildIdUploadStep()
              : _currentStep == 1
                  ? _buildSelfieStep()
                  : _buildCompleteStep(),
        ),
      ),
    );
  }
}
