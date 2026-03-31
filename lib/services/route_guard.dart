import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import '../models/user_model.dart';

/// Route guard to protect admin routes
class RouteGuard {
  /// Check if user has admin role
  static bool isAdmin(UserModel? user) {
    if (user == null) return false;
    return user.role == UserRole.admin;
  }

  /// Check if user is passenger
  static bool isPassenger(UserModel? user) {
    if (user == null) return false;
    return user.role == UserRole.passenger;
  }

  /// Check if user is driver
  static bool isDriver(UserModel? user) {
    if (user == null) return false;
    return user.role == UserRole.driver;
  }
}

/// Widget that protects routes by checking user role
class ProtectedRoute extends StatelessWidget {
  final Widget child;
  final UserRole requiredRole;
  final String? redirectRoute;

  const ProtectedRoute({
    Key? key,
    required this.child,
    required this.requiredRole,
    this.redirectRoute = '/login',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        final user = authService.currentUserModel;

        // User not authenticated
        if (user == null) {
          print('🔐 [ProtectedRoute] Access denied: User not authenticated');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              redirectRoute ?? '/login',
              (route) => false,
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Check role permission
        bool hasPermission = false;
        switch (requiredRole) {
          case UserRole.admin:
            hasPermission = user.role == UserRole.admin;
            break;
          case UserRole.driver:
            hasPermission = user.role == UserRole.driver;
            break;
          case UserRole.passenger:
            hasPermission = user.role == UserRole.passenger;
            break;
        }

        if (!hasPermission) {
          print('🔐 [ProtectedRoute] Access denied: User role ${user.role} does not match required role $requiredRole');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(context).pushNamedAndRemoveUntil(
              authService.getRedirectRoute(),
              (route) => false,
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unauthorized access. Redirecting to your dashboard.'),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // User has permission, show the protected widget
        return child;
      },
    );
  }
}
