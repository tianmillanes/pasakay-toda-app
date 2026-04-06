import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
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
  String _loadingText = 'Initializing...';

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
      print('[SplashScreen] Starting initialization...');
      
      // Don't block on geofence loading - it's done in background
      // Just start location services setup
      _performBackgroundInitialization();
      
      // Minimal splash display - just enough for branding
      await Future.delayed(const Duration(milliseconds: 800));
      
      if (!mounted) return;
      
      print('[SplashScreen] Checking authentication...');
      setState(() {
        _loadingText = 'Checking authentication...';
      });
      
      final authService = Provider.of<AuthService>(context, listen: false);
      
      if (authService.currentUser != null) {
        print('[SplashScreen] User is authenticated');
        
        // Quick check if user data is available
        if (authService.currentUserModel == null) {
          print('[SplashScreen] User data not loaded yet, refreshing...');
          setState(() {
            _loadingText = 'Loading profile...';
          });
          await authService.refreshUserData().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('[SplashScreen] Warning: User data refresh timed out');
            },
          );
        }
        
        final route = authService.getRedirectRoute();
        print('[SplashScreen] Navigating to: $route');
        
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            route,
            (route) => false,
          );
        }
      } else {
        print('[SplashScreen] No user authenticated, navigating to login');
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('[SplashScreen] Initialization error: $e');
      // Continue to login on error
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
      }
    }
  }

  void _performBackgroundInitialization() {
    // Skip geofence loading on web platform
    if (kIsWeb) return;
    
    // Start geofence loading in background without blocking
    Future.microtask(() async {
      try {
        final locationService = Provider.of<LocationService>(
          context,
          listen: false,
        );
        await locationService.loadGeofences().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print('[SplashScreen] Background geofence loading timed out');
          },
        );
        print('[SplashScreen] Background geofences loaded');
      } catch (e) {
        print('[SplashScreen] Background geofence loading failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryGreen,
      body: Center(
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
                    const TricycleLogo(
                      size: 100,
                      showText: false,
                      showShadow: false,
                      plain: true,
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'PASAKAY',
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Loading indicator with status
                    Column(
                      children: [
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loadingText,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
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
    );
  }
}
