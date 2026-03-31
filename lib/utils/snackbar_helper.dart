import 'package:flutter/material.dart';

class SnackbarHelper {
  static void showSuccess(BuildContext context, String message, {int seconds = 3}) {
    _showSnackbar(context, message, Colors.green, seconds: seconds);
  }

  static void showError(BuildContext context, String message, {int seconds = 4}) {
    _showSnackbar(context, message, Colors.red, seconds: seconds);
  }

  static void showInfo(BuildContext context, String message, {int seconds = 3}) {
    _showSnackbar(context, message, Colors.blue, seconds: seconds);
  }

  static void _showSnackbar(BuildContext context, String message, Color color, {required int seconds}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: seconds),
      ),
    );
  }
}
