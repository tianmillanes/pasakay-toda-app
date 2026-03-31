import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../services/firestore_service.dart';
import '../../models/gcash_qr_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import 'payment_proof_screen.dart';

class GcashQrDisplayScreen extends StatefulWidget {
  const GcashQrDisplayScreen({super.key});

  @override
  State<GcashQrDisplayScreen> createState() => _GcashQrDisplayScreenState();
}

class _GcashQrDisplayScreenState extends State<GcashQrDisplayScreen> {
  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('GCash Payment'),
        backgroundColor: AppTheme.backgroundWhite,
        centerTitle: false,
      ),
      body: StreamBuilder<List<GcashQrModel>>(
        stream: firestoreService.getActiveGcashQrCodes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
          final qrCodes = snapshot.data ?? [];
          
          if (qrCodes.isEmpty) return _buildEmptyState();

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  physics: const BouncingScrollPhysics(),
                  itemCount: qrCodes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _QrDisplayCard(qr: qrCodes[index]),
                ),
              ),
              _buildFooter(),
            ],
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
          Icon(Icons.qr_code_2_rounded, size: 80, color: AppTheme.textHint.withOpacity(0.3)),
          const SizedBox(height: 20),
          Text('No QR codes available', style: TextStyle(color: AppTheme.textHint, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(color: AppTheme.backgroundWhite, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Finished paying?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 15),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const PaymentProofScreen())),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Submit Payment Proof', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrDisplayCard extends StatelessWidget {
  final GcashQrModel qr;

  const _QrDisplayCard({required this.qr});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 30),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 25),
            decoration: BoxDecoration(color: AppTheme.primaryGreen.withOpacity(0.05), borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
            child: Row(
              children: [
                Icon(Icons.verified_user_rounded, color: AppTheme.primaryGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(qr.accountName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(30),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.1)),
              ),
              child: _buildQrImage(qr.qrImageUrl),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GCASH NUMBER', style: TextStyle(color: AppTheme.textHint, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                    Text(qr.accountNumber, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  ],
                ),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: qr.accountNumber));
                    SnackbarHelper.showSuccess(context, 'Number copied');
                  },
                  icon: const Icon(Icons.copy_rounded, color: AppTheme.primaryGreen),
                  style: IconButton.styleFrom(backgroundColor: AppTheme.primaryGreen.withOpacity(0.1)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrImage(String data) {
     if (data.startsWith('data:image')) {
      return ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(base64Decode(data.split(',').last), fit: BoxFit.contain));
    }
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(data, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image_outlined)));
  }
}
