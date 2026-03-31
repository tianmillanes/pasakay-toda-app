import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/fare_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/usability_helpers.dart';

class GlobalFareManagementScreen extends StatelessWidget {
  const GlobalFareManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Fare Management', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: AppTheme.backgroundWhite,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Global Fare Settings', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)
            ),
            const SizedBox(height: 8),
            const Text(
              'Changes made here will instantly affect all active passengers and drivers.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FareService.fareRulesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ));
                }
                
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading fare rules: ${snapshot.error}'));
                }
                
                // We map data even if it doesn't exist locally yet
                final data = snapshot.data?.data() ?? {};
                final baseFare = (data['baseFare'] ?? 20.0).toDouble();
                final firstTwoKmFare = (data['firstTwoKmFare'] ?? 20.0).toDouble();
                final farePer500m = (data['farePer500m'] ?? 10.0).toDouble();
                final minimumFare = (data['minimumFare'] ?? 20.0).toDouble();
                final surgeMultiplier = (data['surgeMultiplier'] ?? 1.0).toDouble();
                
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.borderLight),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02), 
                        blurRadius: 10, 
                        offset: const Offset(0, 4)
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildFareRow('Base Fare', '₱$baseFare'),
                      const Divider(height: 24, color: AppTheme.borderLight),
                      _buildFareRow('First 2km Rate', '₱$firstTwoKmFare'),
                      const Divider(height: 24, color: AppTheme.borderLight),
                      _buildFareRow('Per 500m (After 2km)', '₱$farePer500m'),
                      const Divider(height: 24, color: AppTheme.borderLight),
                      _buildFareRow('Minimum Fare', '₱$minimumFare'),
                      const Divider(height: 24, color: AppTheme.borderLight),
                      _buildFareRow('Surge Multiplier', '${surgeMultiplier}x'),
                      
                      const SizedBox(height: 32),
                      
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Edit Fare Rules', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                          ),
                          onPressed: () => _showEditDialog(
                            context, 
                            baseFare, 
                            firstTwoKmFare, 
                            farePer500m, 
                            minimumFare, 
                            surgeMultiplier
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFareRow(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title, 
          style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary, fontSize: 15)
        ),
        Text(
          value, 
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppTheme.textPrimary)
        ),
      ],
    );
  }

  void _showEditDialog(BuildContext context, double bF, double fTKF, double fP5, double mF, double sM) {
    final bFCtrl = TextEditingController(text: bF.toString());
    final fTKFCtrl = TextEditingController(text: fTKF.toString());
    final fP5Ctrl = TextEditingController(text: fP5.toString());
    final mFCtrl = TextEditingController(text: mF.toString());
    final sMCtrl = TextEditingController(text: sM.toString());
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Update Fare Rules', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInput('Base Fare (₱)', bFCtrl),
              const SizedBox(height: 12),
              _buildInput('First 2km Fare (₱)', fTKFCtrl),
              const SizedBox(height: 12),
              _buildInput('Fare Per 500m (₱)', fP5Ctrl),
              const SizedBox(height: 12),
              _buildInput('Minimum Fare (₱)', mFCtrl),
              const SizedBox(height: 12),
              _buildInput('Surge Multiplier (x)', sMCtrl),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final authService = Provider.of<AuthService>(context, listen: false);
                await FareService.updateFareRates(
                  adminId: authService.currentUser!.uid,
                  baseFare: double.parse(bFCtrl.text),
                  firstTwoKmFare: double.parse(fTKFCtrl.text),
                  farePer500m: double.parse(fP5Ctrl.text),
                  minimumFare: double.parse(mFCtrl.text),
                  surgeMultiplier: double.parse(sMCtrl.text),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  SnackbarHelper.showSuccess(context, 'Fare rules updated successfully!');
                }
              } catch (e) {
                if (ctx.mounted) SnackbarHelper.showError(ctx, 'Invalid values entered.');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen, 
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
            child: const Text('Save Rules', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );
  }

  Widget _buildInput(String label, TextEditingController controller) {
    return TextField(
      controller: controller, 
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primaryGreen, width: 2)),
      ), 
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
    );
  }
}
