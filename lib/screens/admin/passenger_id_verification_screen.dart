import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/id_verification_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/usability_helpers.dart';

class PassengerIdVerificationScreen extends StatelessWidget {
  const PassengerIdVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: AppBar(
          title: const Text('ID Verifications', style: TextStyle(fontWeight: FontWeight.w900)),
          backgroundColor: AppTheme.backgroundWhite,
          centerTitle: true,
          elevation: 0,
          bottom: const TabBar(
            labelColor: AppTheme.primaryGreen,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryGreen,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Approved'),
              Tab(text: 'Rejected'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _VerificationList(status: 'pending'),
            _VerificationList(status: 'approved'),
            _VerificationList(status: 'rejected'),
          ],
        ),
      ),
    );
  }
}

class _VerificationList extends StatelessWidget {
  final String status;
  const _VerificationList({required this.status});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'passenger')
          .where('idVerificationStatus', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  status == 'pending' ? Icons.hourglass_empty_rounded :
                  status == 'approved' ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 64,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'No ${status.capitalize()} requests',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final userId = docs[index].id;
            return _VerificationCard(data: data, userId: userId, status: status);
          },
        );
      },
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String userId;
  final String status;

  const _VerificationCard({required this.data, required this.userId, required this.status});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] ?? 'Unknown';
    final email = data['email'] ?? '';
    final phone = data['phone'] ?? '';
    final idType = data['idType'] ?? 'Unknown ID';
    final submittedAt = data['idVerificationSubmittedAt'] as Timestamp?;
    final note = data['idVerificationNote'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info header
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryGreenLight,
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'P',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryGreen, fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      Text(email, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      Text(phone, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),

            const Divider(height: 24, color: AppTheme.borderLight),

            // ID type
            Row(
              children: [
                const Icon(Icons.badge_rounded, size: 16, color: AppTheme.primaryGreen),
                const SizedBox(width: 6),
                Text(idType, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ],
            ),

            if (submittedAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Submitted: ${_formatDate(submittedAt.toDate())}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],

            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: status == 'rejected' ? Colors.red.shade50 : AppTheme.primaryGreenLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14,
                        color: status == 'rejected' ? Colors.red.shade700 : AppTheme.primaryGreen),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(note, style: TextStyle(
                          fontSize: 12,
                          color: status == 'rejected' ? Colors.red.shade700 : AppTheme.textSecondary)),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Photos row (Base64 fetched from user_verifications doc)
            FutureBuilder<Map<String, String>?>(
              future: IdVerificationService.getVerificationPhotos(userId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ));
                }
                
                final photos = snap.data;
                // Support legacy URLs if they still exist for some reason
                final idUrl = data['idImageUrl'] as String?;
                final selfieUrl = data['selfieUrl'] as String?;

                return Row(
                  children: [
                    Expanded(
                      child: _PhotoTile(
                        label: 'Government ID',
                        imageUrl: idUrl,
                        base64String: photos?['idBase64'],
                        icon: Icons.badge_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PhotoTile(
                        label: 'Selfie',
                        imageUrl: selfieUrl,
                        base64String: photos?['selfieBase64'],
                        icon: Icons.face_rounded,
                      ),
                    ),
                  ],
                );
              }
            ),

            // Action buttons (only for pending)
            if (status == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showRejectDialog(context, userId),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approve(context, userId),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approve(BuildContext context, String userId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      await IdVerificationService.approveVerification(
        userId: userId,
        adminId: authService.currentUser!.uid,
      );
      if (context.mounted) SnackbarHelper.showSuccess(context, 'ID verified and approved!');
    } catch (e) {
      if (context.mounted) SnackbarHelper.showError(context, 'Failed to approve: $e');
    }
  }

  void _showRejectDialog(BuildContext context, String userId) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject Verification', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason (the passenger will see this):', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Image is blurry, ID is expired...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(ctx);
              final authService = Provider.of<AuthService>(context, listen: false);
              try {
                await IdVerificationService.rejectVerification(
                  userId: userId,
                  adminId: authService.currentUser!.uid,
                  reason: reason,
                );
                if (context.mounted) SnackbarHelper.showSuccess(context, 'Verification rejected.');
              } catch (e) {
                if (context.mounted) SnackbarHelper.showError(context, 'Failed to reject: $e');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _PhotoTile extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final String? base64String;
  final IconData icon;

  const _PhotoTile({required this.label, this.imageUrl, this.base64String, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: (imageUrl != null && imageUrl!.isNotEmpty) || (base64String != null && base64String!.isNotEmpty)
              ? () => _showFullImage(context, imageUrl, base64String, label)
              : null,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.backgroundLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: (base64String != null && base64String!.isNotEmpty)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.memory(
                      base64Decode(base64String!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(icon, color: Colors.grey.shade300, size: 36),
                      ),
                    ),
                  )
                : (imageUrl != null && imageUrl!.isNotEmpty)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(icon, color: Colors.grey.shade300, size: 36),
                      ),
                    ),
                  )
                : Center(
                    child: Icon(icon, color: Colors.grey.shade300, size: 36),
                  ),
          ),
        ),
        if ((imageUrl != null && imageUrl!.isNotEmpty) || (base64String != null && base64String!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Tap to enlarge', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ),
      ],
    );
  }

  void _showFullImage(BuildContext context, String? url, String? base64Str, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: (base64Str != null && base64Str.isNotEmpty)
                  ? Image.memory(base64Decode(base64Str), fit: BoxFit.contain)
                  : Image.network(url ?? '', fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'approved':
        color = Colors.green;
        icon = Icons.verified_rounded;
        label = 'Approved';
        break;
      case 'rejected':
        color = Colors.red;
        icon = Icons.cancel_rounded;
        label = 'Rejected';
        break;
      default:
        color = Colors.orange;
        icon = Icons.hourglass_top_rounded;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() => isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';
}
