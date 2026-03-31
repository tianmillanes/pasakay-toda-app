import 'package:flutter/material.dart';
import '../../services/error_handling_service.dart';
import '../../utils/app_theme.dart';

/// Enhanced error display widget with retry functionality
class ErrorDisplayWidget extends StatelessWidget {
  final dynamic error;
  final VoidCallback? onRetry;
  final String? context;
  final bool showDetails;
  final EdgeInsets padding;
  final bool isFullScreen;

  const ErrorDisplayWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.context,
    this.showDetails = false,
    this.padding = const EdgeInsets.all(24),
    this.isFullScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final message = ErrorHandlingService.getUserFriendlyMessage(error, context: this.context);
    final category = ErrorHandlingService.getErrorCategory(error);
    final isNetworkError = ErrorHandlingService.isNetworkError(error);
    final shouldRetry = ErrorHandlingService.shouldRetry(error);

    if (isFullScreen) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: _buildErrorContent(message, category, isNetworkError, shouldRetry, context),
      );
    }

    return _buildErrorContent(message, category, isNetworkError, shouldRetry, context);
  }

  Widget _buildErrorContent(
    String message,
    String category,
    bool isNetworkError,
    bool shouldRetry,
    BuildContext context,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error icon
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _getErrorColor(category).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getErrorIcon(category),
                size: 64,
                color: _getErrorColor(category),
              ),
            ),
            const SizedBox(height: 24),

            // Error title
            Text(
              _getErrorTitle(category),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A),
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Error message
            Text(
              message,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            // Error details (if enabled)
            if (showDetails) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Error Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Type: $category\nError: ${error.toString().substring(0, error.toString().length > 100 ? 100 : error.toString().length)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Action buttons
            if (onRetry != null && shouldRetry) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else if (onRetry != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],

            // Help text
            if (isNetworkError) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_rounded, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Check your internet connection and try again',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getErrorIcon(String category) {
    switch (category) {
      case ErrorHandlingService.categoryNetwork:
        return Icons.wifi_off_rounded;
      case ErrorHandlingService.categoryTimeout:
        return Icons.schedule_rounded;
      case ErrorHandlingService.categoryPermission:
        return Icons.lock_rounded;
      case ErrorHandlingService.categoryLocation:
        return Icons.location_off_rounded;
      case ErrorHandlingService.categoryFirebase:
        return Icons.cloud_off_rounded;
      case ErrorHandlingService.categoryValidation:
        return Icons.error_outline_rounded;
      default:
        return Icons.error_outline_rounded;
    }
  }

  Color _getErrorColor(String category) {
    switch (category) {
      case ErrorHandlingService.categoryNetwork:
        return Colors.orange;
      case ErrorHandlingService.categoryTimeout:
        return Colors.amber;
      case ErrorHandlingService.categoryPermission:
        return Colors.red;
      case ErrorHandlingService.categoryLocation:
        return Colors.purple;
      case ErrorHandlingService.categoryFirebase:
        return Colors.blue;
      case ErrorHandlingService.categoryValidation:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getErrorTitle(String category) {
    switch (category) {
      case ErrorHandlingService.categoryNetwork:
        return 'Connection Error';
      case ErrorHandlingService.categoryTimeout:
        return 'Request Timeout';
      case ErrorHandlingService.categoryPermission:
        return 'Permission Denied';
      case ErrorHandlingService.categoryLocation:
        return 'Location Error';
      case ErrorHandlingService.categoryFirebase:
        return 'Server Error';
      case ErrorHandlingService.categoryValidation:
        return 'Invalid Data';
      default:
        return 'Oops!';
    }
  }
}

/// Compact error display for inline errors
class CompactErrorWidget extends StatelessWidget {
  final dynamic error;
  final VoidCallback? onRetry;
  final String? context;

  const CompactErrorWidget({
    super.key,
    required this.error,
    this.onRetry,
    this.context,
  });

  @override
  Widget build(BuildContext context) {
    final message = ErrorHandlingService.getUserFriendlyMessage(error, context: this.context);
    final category = ErrorHandlingService.getErrorCategory(error);
    final shouldRetry = ErrorHandlingService.shouldRetry(error);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getErrorColor(category).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getErrorColor(category).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _getErrorIcon(category),
            color: _getErrorColor(category),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getErrorTitle(category),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: _getErrorColor(category),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onRetry != null && shouldRetry) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getErrorColor(category),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getErrorIcon(String category) {
    switch (category) {
      case ErrorHandlingService.categoryNetwork:
        return Icons.wifi_off_rounded;
      case ErrorHandlingService.categoryTimeout:
        return Icons.schedule_rounded;
      case ErrorHandlingService.categoryPermission:
        return Icons.lock_rounded;
      case ErrorHandlingService.categoryLocation:
        return Icons.location_off_rounded;
      case ErrorHandlingService.categoryFirebase:
        return Icons.cloud_off_rounded;
      default:
        return Icons.error_outline_rounded;
    }
  }

  Color _getErrorColor(String category) {
    switch (category) {
      case ErrorHandlingService.categoryNetwork:
        return Colors.orange;
      case ErrorHandlingService.categoryTimeout:
        return Colors.amber;
      case ErrorHandlingService.categoryPermission:
        return Colors.red;
      case ErrorHandlingService.categoryLocation:
        return Colors.purple;
      case ErrorHandlingService.categoryFirebase:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getErrorTitle(String category) {
    switch (category) {
      case ErrorHandlingService.categoryNetwork:
        return 'Connection Error';
      case ErrorHandlingService.categoryTimeout:
        return 'Timeout';
      case ErrorHandlingService.categoryPermission:
        return 'Permission Denied';
      case ErrorHandlingService.categoryLocation:
        return 'Location Error';
      case ErrorHandlingService.categoryFirebase:
        return 'Server Error';
      default:
        return 'Error';
    }
  }
}
