import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../widgets/tricycle_logo.dart';
import '../utils/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  String _loadingText = 'Initializing yourapp...';

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeApp();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _animationController.forward();
  }

  Future<void> _initializeApp() async {
    try {
      // Notification services removed - using Firestore listeners

      setState(() {
        _loadingText = 'Setting up location services...';
      });

      // Initialize location service
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      await locationService.loadGeofences();

      setState(() {
        _loadingText = 'Preparing your experience...';
      });

      // Wait for animation and loading to complete
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        final authService = Provider.of<AuthService>(context, listen: false);

        if (authService.currentUser != null) {
          // User is authenticated, ensure user model is loaded
          await authService.refreshUserData();

          if (authService.currentUserModel != null) {
            // User data loaded successfully, redirect to dashboard
            Navigator.of(
              context,
            ).pushReplacementNamed(authService.getRedirectRoute());
          } else {
            // User authenticated but no user model, go to login
            print('User authenticated but no user model found');
            Navigator.of(context).pushReplacementNamed('/login');
          }
        } else {
          // User is not logged in, go to login screen
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      setState(() {
        _loadingText = 'Starting app...';
      });

      // Continue even if some services fail
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryBlue,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primaryBlue, AppTheme.primaryBlueDark],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Enhanced Tricycle Logo
                      const TricycleLogo(
                        size: 140,
                        showText: true,
                        showShadow: true,
                        backgroundColor: Colors.white,
                      ),

                      const SizedBox(height: 40),

                      // Loading indicator with status
                      Column(
                        children: [
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _loadingText,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),

                      const SizedBox(height: 60),

                      // Version and credits
                      const Column(
                        children: [
                          Text(
                            'Version 1.0.0',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tricycle Transportation Made Simple',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
