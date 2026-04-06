import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firestore_service.dart';
import '../widgets/usability_helpers.dart';
import '../utils/app_theme.dart';

class DriverRatingDialog extends StatefulWidget {
  final String rideId;
  final String driverId;
  final String passengerId;
  final String passengerName;
  final bool isPasabuy;

  const DriverRatingDialog({
    super.key,
    required this.rideId,
    required this.driverId,
    required this.passengerId,
    required this.passengerName,
    this.isPasabuy = false,
  });

  @override
  State<DriverRatingDialog> createState() => _DriverRatingDialogState();
}

class _DriverRatingDialogState extends State<DriverRatingDialog> {
  double _rating = 5.0;
  final _feedbackController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    setState(() => _isSubmitting = true);
    
    try {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      
      await firestoreService.submitDriverRating(
        rideId: widget.rideId,
        driverId: widget.driverId,
        passengerId: widget.passengerId,
        passengerName: widget.passengerName,
        rating: _rating,
        feedback: _feedbackController.text.trim(),
        isPasabuy: widget.isPasabuy,
      );
      
      if (mounted) {
        Navigator.of(context).pop(true);
        SnackbarHelper.showSuccess(context, 'Thank you for your feedback!');
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to submit rating: $e');
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreenLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_rounded, size: 48, color: Colors.amber),
            ),
            const SizedBox(height: 24),
            const Text(
              'Rate Your Driver',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'How was your experience?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  onPressed: () {
                    setState(() {
                      _rating = index + 1.0;
                    });
                  },
                  icon: Icon(
                    index < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 40,
                    color: index < _rating ? Colors.amber : Colors.grey.shade300,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  splashRadius: 24,
                );
              }),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _feedbackController,
              maxLines: 3,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Leave a comment (optional)',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRating,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Submit Feedback',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Not now', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
