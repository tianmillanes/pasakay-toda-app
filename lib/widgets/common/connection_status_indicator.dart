import 'package:flutter/material.dart';
import '../../services/connection_status_service.dart';

/// Widget to display connection status indicator
class ConnectionStatusIndicator extends StatelessWidget {
  final bool showLabel;
  final bool showIcon;
  final double iconSize;
  final TextStyle? labelStyle;

  const ConnectionStatusIndicator({
    super.key,
    this.showLabel = true,
    this.showIcon = true,
    this.iconSize = 16,
    this.labelStyle,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatus>(
      stream: ConnectionStatusService().connectionStatusStream,
      initialData: ConnectionStatusService().currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ConnectionStatus.offline;

        if (status.isOnline) {
          // Don't show indicator when online
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: status.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: status.color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon) ...[
                Icon(
                  status.icon,
                  color: status.color,
                  size: iconSize,
                ),
                const SizedBox(width: 8),
              ],
              if (showLabel)
                Text(
                  status.displayMessage,
                  style: labelStyle ??
                      TextStyle(
                        color: status.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Full-screen connection status banner
class ConnectionStatusBanner extends StatelessWidget {
  final bool dismissible;

  const ConnectionStatusBanner({
    super.key,
    this.dismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatus>(
      stream: ConnectionStatusService().connectionStatusStream,
      initialData: ConnectionStatusService().currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ConnectionStatus.offline;

        if (status.isOnline) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: status.color.withOpacity(0.1),
            border: Border(
              bottom: BorderSide(color: status.color.withOpacity(0.3)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                status.icon,
                color: status.color,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Internet Connection',
                      style: TextStyle(
                        color: status.color,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Some features may not work properly',
                      style: TextStyle(
                        color: status.color.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (dismissible)
                IconButton(
                  icon: Icon(Icons.close_rounded, color: status.color, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Overlay connection status indicator
class ConnectionStatusOverlay extends StatelessWidget {
  final Widget child;
  final bool showBanner;

  const ConnectionStatusOverlay({
    super.key,
    required this.child,
    this.showBanner = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ConnectionStatusBanner(),
          ),
      ],
    );
  }
}

/// Dialog for connection errors
class ConnectionErrorDialog extends StatelessWidget {
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const ConnectionErrorDialog({
    super.key,
    this.onRetry,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.red, size: 24),
          const SizedBox(width: 12),
          const Text('No Connection'),
        ],
      ),
      content: const Text(
        'You appear to be offline. Please check your internet connection and try again.',
      ),
      actions: [
        TextButton(
          onPressed: onDismiss ?? () => Navigator.pop(context),
          child: const Text('Dismiss'),
        ),
        if (onRetry != null)
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onRetry?.call();
            },
            child: const Text('Retry'),
          ),
      ],
    );
  }
}

/// Snackbar for connection status changes
void showConnectionStatusSnackbar(BuildContext context, ConnectionStatus status) {
  if (!status.isOnline) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(status.icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status.displayMessage,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: status.color,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
