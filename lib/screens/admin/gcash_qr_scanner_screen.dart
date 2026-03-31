import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../services/firestore_service.dart';
import '../../models/gcash_qr_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';

class GcashQrScannerScreen extends StatefulWidget {
  const GcashQrScannerScreen({super.key});

  @override
  State<GcashQrScannerScreen> createState() => _GcashQrScannerScreenState();
}

class _GcashQrScannerScreenState extends State<GcashQrScannerScreen> {
  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Scan Payment QR'),
        backgroundColor: AppTheme.backgroundWhite,
        centerTitle: false,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<List<GcashQrModel>>(
        stream: firestoreService.getActiveGcashQrCodes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
          final qrCodes = snapshot.data ?? [];
          
          if (qrCodes.isEmpty) return _buildEmptyState();

          return PageView.builder(
            itemCount: qrCodes.length,
            controller: PageController(viewportFraction: 0.9),
            itemBuilder: (context, index) => _QrScanCard(qr: qrCodes[index]),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_scanner_rounded, size: 80, color: AppTheme.textHint.withOpacity(0.3)),
          const SizedBox(height: 20),
          Text('No QR codes available yet', style: TextStyle(color: AppTheme.textHint, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _QrScanCard extends StatelessWidget {
  final GcashQrModel qr;

  const _QrScanCard({required this.qr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 40),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          const SizedBox(height: 30),
          const Text('Scan to Pay via GCash', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 30),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 30),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.1), width: 2),
              ),
              child: _buildQrImage(qr.qrImageUrl),
            ),
          ),
          const SizedBox(height: 30),
          _buildInfoRow(Icons.person_outline, 'Merchant', qr.accountName),
          _buildInfoRow(Icons.phone_android_outlined, 'Account #', qr.accountNumber),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(30),
            child: ElevatedButton.icon(
              onPressed: () => SnackbarHelper.showSuccess(context, 'Number copied to clipboard'),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Account Number', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text('$label:', style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildQrImage(String data) {
    if (data.startsWith('data:image')) {
      return ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.memory(base64Decode(data.split(',').last), fit: BoxFit.contain));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(data, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined, size: 50)));
  }
}
