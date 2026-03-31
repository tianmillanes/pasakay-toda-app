import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/gcash_qr_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';

import '../../widgets/full_screen_image_viewer.dart';

class GcashQrManagementScreen extends StatefulWidget {
  const GcashQrManagementScreen({super.key});

  @override
  State<GcashQrManagementScreen> createState() => _GcashQrManagementScreenState();
}

class _GcashQrManagementScreenState extends State<GcashQrManagementScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _selectedImageBytes;
  final TextEditingController _accountNameController = TextEditingController();
  final TextEditingController _accountNumberController = TextEditingController();
  bool _isUploading = false;

  @override
  void dispose() {
    _accountNameController.dispose();
    _accountNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() => _selectedImageBytes = bytes);
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Error picking image: $e');
    }
  }

  Future<void> _uploadQrCode() async {
    if (_selectedImageBytes == null || _accountNameController.text.isEmpty || _accountNumberController.text.isEmpty) {
      SnackbarHelper.showError(context, 'Please complete all fields');
      return;
    }

    setState(() => _isUploading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final currentUser = authService.currentUserModel!;

      final imageUrl = await firestoreService.uploadGcashQrImageBytes(_selectedImageBytes!, currentUser.id);
      await firestoreService.saveGcashQrCode(
        qrImageUrl: imageUrl,
        accountName: _accountNameController.text.trim(),
        accountNumber: _accountNumberController.text.trim(),
        uploadedBy: currentUser.id,
        uploadedByName: currentUser.name,
      );

      if (mounted) {
        SnackbarHelper.showSuccess(context, 'QR code updated successfully');
        setState(() {
          _selectedImageBytes = null;
          _accountNameController.clear();
          _accountNumberController.clear();
        });
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('GCash QR Management'),
        backgroundColor: AppTheme.backgroundWhite,
        centerTitle: false,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUploadCard(),
            const SizedBox(height: 30),
            const Text('Active QR Codes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textPrimary)),
            const SizedBox(height: 15),
            StreamBuilder<List<GcashQrModel>>(
              stream: firestoreService.getActiveGcashQrCodes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
                final qrCodes = snapshot.data ?? [];
                if (qrCodes.isEmpty) return _buildEmptyState();
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: qrCodes.length,
                  itemBuilder: (context, index) => _ActiveQrCard(qr: qrCodes[index], onDelete: () => _handleDelete(qrCodes[index])),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.backgroundWhite, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Column(
        children: [
          GestureDetector(
            onTap: _isUploading ? null : _pickImage,
            child: Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2), width: 2, style: BorderStyle.solid),
              ),
              child: _selectedImageBytes != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.memory(_selectedImageBytes!, fit: BoxFit.cover))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code_scanner_rounded, size: 40, color: AppTheme.primaryGreen),
                        const SizedBox(height: 10),
                        const Text('Upload New QR Code', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                        Text('PNG or JPG files accepted', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),
          _buildTextField(_accountNameController, 'Merchant/Account Name', Icons.person_outline),
          const SizedBox(height: 15),
          _buildTextField(_accountNumberController, 'GCash Number', Icons.phone_android_outlined),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isUploading ? null : _uploadQrCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('Save & Publish QR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primaryGreen),
        filled: true,
        fillColor: AppTheme.backgroundLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: AppTheme.backgroundLight, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(Icons.qr_code_2_rounded, size: 60, color: AppTheme.textHint.withOpacity(0.3)),
          const SizedBox(height: 15),
          Text('No active QR codes', style: TextStyle(color: AppTheme.textHint, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _handleDelete(GcashQrModel qr) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deactivation'),
        content: Text('Are you sure you want to disable QR for ${qr.accountName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate', style: TextStyle(color: AppTheme.errorRed))),
        ],
      ),
    );
    if (confirm == true) {
      await Provider.of<FirestoreService>(context, listen: false).deactivateGcashQrCode(qr.id);
      SnackbarHelper.showSuccess(context, 'QR code deactivated');
    }
  }
}

class _ActiveQrCard extends StatelessWidget {
  final GcashQrModel qr;
  final VoidCallback onDelete;

  const _ActiveQrCard({required this.qr, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.backgroundWhite, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(color: AppTheme.backgroundLight, borderRadius: BorderRadius.circular(12)),
            child: _buildQrImage(context, qr.qrImageUrl),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(qr.accountName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(qr.accountNumber, style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text('By: ${qr.uploadedByName}', style: TextStyle(color: AppTheme.textHint, fontSize: 10)),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed), onPressed: onDelete),
        ],
      ),
    );
  }

  Widget _buildQrImage(BuildContext context, String data) {
    final heroTag = 'qr_${data.hashCode}';
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenImageViewer(imageUrl: data, tag: heroTag),
        ),
      ),
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: data.startsWith('data:image')
              ? Image.memory(base64Decode(data.split(',').last), fit: BoxFit.cover)
              : Image.network(data, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}
