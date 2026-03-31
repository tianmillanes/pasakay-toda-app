import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/barangay_service.dart';
import '../../models/driver_model.dart';
import '../../models/barangay_model.dart';
import '../../models/user_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/barangay_selector.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({super.key});

  @override
  State<DriverRegistrationScreen> createState() =>
      _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _imagePicker = ImagePicker();

  XFile? _plateNumberImage;
  XFile? _licenseNumberImage;
  bool _isLoading = false;
  // Hardcoded to Tricycle since this app is tricycle-only
  final String _vehicleType = 'Tricycle';
  BarangayModel? _selectedBarangay;
  
  // Text controllers for plate and license numbers
  final TextEditingController _tricyclePlateController = TextEditingController();
  final TextEditingController _driverLicenseController = TextEditingController();

  late BarangayService _barangayService;

  @override
  void initState() {
    super.initState();
    _barangayService = BarangayService();
    _barangayService.initializeBarangays();
  }

  @override
  void dispose() {
    _tricyclePlateController.dispose();
    _driverLicenseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isPlateNumber) async {
    try {
      // Show source selection dialog
      final ImageSource? source = await SnackbarHelper.showImageSourceDialog(context);
      
      if (source == null) return; // User cancelled
      
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          if (isPlateNumber) {
            _plateNumberImage = pickedFile;
          } else {
            _licenseNumberImage = pickedFile;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error picking image: $e');
      }
    }
  }

  Future<void> _submitRegistration() async {
    // Validate image uploads
    if (_plateNumberImage == null) {
      SnackbarHelper.showError(context, 'Please upload a photo of your plate number');
      return;
    }

    if (_licenseNumberImage == null) {
      SnackbarHelper.showError(context, 'Please upload a photo of your driver\'s license');
      return;
    }

    // Validate barangay selection
    if (_selectedBarangay == null) {
      SnackbarHelper.showError(context, 'Please select a barangay');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(
        context,
        listen: false,
      );

      if (authService.currentUser == null) {
        throw Exception('User not authenticated. Please log in again.');
      }

      // Step 1: Process and upload plate number image
      if (mounted) {
        SnackbarHelper.showInfo(context, 'Processing plate number image...', seconds: 2);
      }
      
      String? plateImageUrl;
      try {
        plateImageUrl = await firestoreService.uploadDriverDocument(
          authService.currentUser!.uid,
          'plate_number',
          _plateNumberImage!,
        );
        
        if (plateImageUrl.isEmpty) {
          throw Exception('Plate number image processing failed. Please try again.');
        }
      } catch (e) {
        throw Exception('Plate number image error: ${e.toString().replaceFirst('Exception: ', '')}');
      }

      // Step 2: Process and upload license image
      if (mounted) {
        SnackbarHelper.showInfo(context, 'Processing license image...', seconds: 2);
      }
      
      String? licenseImageUrl;
      try {
        licenseImageUrl = await firestoreService.uploadDriverDocument(
          authService.currentUser!.uid,
          'license_number',
          _licenseNumberImage!,
        );
        
        if (licenseImageUrl.isEmpty) {
          throw Exception('License image processing failed. Please try again.');
        }
      } catch (e) {
        throw Exception('License image error: ${e.toString().replaceFirst('Exception: ', '')}');
      }

      // Step 3: Validate plate and license numbers
      final plateTrimmed = _tricyclePlateController.text.trim();
      final licenseTrimmed = _driverLicenseController.text.trim();
      
      if (plateTrimmed.isEmpty) {
        throw Exception('Please enter your tricycle plate number');
      }
      
      if (licenseTrimmed.isEmpty) {
        throw Exception('Please enter your driver license number');
      }

      // Step 4: Create driver model with validated data
      final driverModel = DriverModel(
        id: authService.currentUser!.uid,
        userId: authService.currentUser!.uid,
        name: authService.currentUserModel?.name ?? 'Driver',
        vehicleType: _vehicleType,
        plateNumber: '', // Empty - will be verified from image
        licenseNumber: '', // Empty - will be verified from image
        plateNumberImageUrl: plateImageUrl,
        licenseNumberImageUrl: licenseImageUrl,
        tricyclePlateNumber: plateTrimmed,
        driverLicenseNumber: licenseTrimmed,
        barangayId: _selectedBarangay!.id,
        barangayName: _selectedBarangay!.name,
      );

      // Step 5: Submit registration
      if (mounted) {
        SnackbarHelper.showInfo(context, 'Submitting registration...', seconds: 2);
      }
      
      await firestoreService.createDriverProfile(driverModel);

      // Step 6: Refresh user data
      await authService.refreshUserData();

      if (mounted) {
        SnackbarHelper.showSuccess(
          context,
          'Registration submitted successfully! Awaiting admin verification.',
          seconds: 4,
        );
        
        // Small delay to ensure UI updates
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/driver');
        }
      }
    } on Exception catch (e) {
      if (mounted) {
        // Extract readable error message
        String errorMessage = e.toString().replaceFirst('Exception: ', '');
        
        // Map specific error patterns to user-friendly messages
        if (errorMessage.contains('Image is too large')) {
          errorMessage = 'Image file is too large. Please use a smaller or lower resolution image.';
        } else if (errorMessage.contains('Plate number image error')) {
          errorMessage = 'Failed to process plate number image. Please try a different photo.';
        } else if (errorMessage.contains('License image error')) {
          errorMessage = 'Failed to process license image. Please try a different photo.';
        } else if (errorMessage.contains('permission-denied')) {
          errorMessage = 'Permission denied. Please ensure you\'re logged in as a driver.';
        } else if (errorMessage.contains('network')) {
          errorMessage = 'Network error. Please check your internet connection and try again.';
        } else if (errorMessage.contains('not authenticated')) {
          errorMessage = 'Session expired. Please log in again.';
        } else if (errorMessage.contains('invalid-argument')) {
          errorMessage = 'Invalid data format. Please check your inputs and try again.';
        }
        
        SnackbarHelper.showError(
          context, 
          'Registration failed: $errorMessage',
          seconds: 5,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(
          context, 
          'An unexpected error occurred. Please try again.',
          seconds: 5,
        );
      }
      print('Unexpected error during driver registration: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUserModel;
    
    print('🔄 Driver Registration Screen Built - Image Upload Version');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Complete Driver Profile'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome message
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.motorcycle,
                          size: 48,
                          color: Colors.green[600],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome, ${user?.name ?? 'Driver'}!',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Complete your tricycle information to start receiving ride requests.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Registration form
                const Text(
                  'Tricycle Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Tricycle info display
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.motorcycle,
                        color: Colors.green[600],
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vehicle Type: Tricycle',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'This app is exclusively for tricycle drivers',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Select Your Barangay',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                BarangaySelector(
                  selectedBarangay: _selectedBarangay,
                  onBarangaySelected: (barangay) {
                    setState(() {
                      _selectedBarangay = barangay;
                    });
                  },
                ),

                const SizedBox(height: 20),

                // Plate number image upload
                _buildImageUploadCard(
                  title: 'Tricycle Plate Number',
                  subtitle: 'Take a clear photo of your plate number',
                  icon: Icons.confirmation_number,
                  image: _plateNumberImage,
                  onTap: () => _pickImage(true),
                  isUploaded: _plateNumberImage != null,
                ),
                const SizedBox(height: 16),

                // License number image upload
                _buildImageUploadCard(
                  title: 'Driver\'s License',
                  subtitle: 'Take a clear photo of your driver\'s license',
                  icon: Icons.credit_card,
                  image: _licenseNumberImage,
                  onTap: () => _pickImage(false),
                  isUploaded: _licenseNumberImage != null,
                ),

                const SizedBox(height: 24),

                // Tricycle Plate Number Input
                TextFormField(
                  controller: _tricyclePlateController,
                  decoration: InputDecoration(
                    labelText: 'Tricycle Plate Number',
                    hintText: 'e.g., ABC-1234',
                    prefixIcon: const Icon(Icons.confirmation_number),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your tricycle plate number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Driver License Number Input
                TextFormField(
                  controller: _driverLicenseController,
                  decoration: InputDecoration(
                    labelText: 'Driver License Number',
                    hintText: 'e.g., D12-34-567890',
                    prefixIcon: const Icon(Icons.credit_card),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your driver license number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Terms and conditions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue[600], size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Important Information',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• Your application will be reviewed by our admin team\n'
                        '• Barangay admin will verify your documents\n'
                        '• Ensure photos are clear and readable\n'
                        '• You will be notified once approved\n'
                        '• You can only start accepting rides after approval',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Submit Registration',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Back to login button
                TextButton(
                  onPressed: () async {
                    await authService.signOut();
                    if (mounted) {
                      Navigator.of(context).pushReplacementNamed('/login');
                    }
                  },
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required XFile? image,
    required VoidCallback onTap,
    required bool isUploaded,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isUploaded ? Colors.green : Colors.grey.shade300,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isUploaded ? Colors.green[50] : Colors.grey[50],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (image != null)
                // Show uploaded image
                FutureBuilder<Uint8List>(
                  future: image.readAsBytes(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          snapshot.data!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      );
                    }
                    return Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  },
                )
              else
                // Show upload placeholder
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: 40,
                        color: Colors.blue[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[600],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Take Photo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              if (image != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '✓ Photo uploaded',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        color: Colors.green[600],
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
