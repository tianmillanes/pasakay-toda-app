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
      print('🏁 [SplashScreen] Starting initialization...');
      
      // Perform initialization without an artificial global timeout
      // Individual services within _performInitialization have their own timeouts
      await _performInitialization();
      
      print('✅ [SplashScreen] Initialization complete');
    } catch (e) {
      print('⚠️ [SplashScreen] Initialization error: $e');
      setState(() {
        _loadingText = 'Starting app...';
      });

      // Continue even if some services fail
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        print('📱 [SplashScreen] Navigating to login screen');
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  Future<void> _performInitialization() async {
    print('📍 [SplashScreen] Setting up location services...');
    setState(() {
      _loadingText = 'Setting up location services...';
    });

    // Skip geofence loading on web platform - load in background instead
    if (!kIsWeb) {
      // Initialize location service but load geofences in background
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      
      // Start geofence loading in background without blocking
      Future.microtask(() async {
        try {
          await locationService.loadGeofences().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              print('⚠️ Warning: Background geofence loading timed out');
            },
          );
          print('✅ Background geofences loaded successfully');
        } catch (e) {
          print('⚠️ Warning: Background geofence loading failed: $e');
        }
      });
      print('🔄 Geofence loading started in background');
    } else {
      print('🌐 Web platform detected, skipping geofence loading');
    }

    print('🎨 [SplashScreen] Preparing experience...');
    setState(() {
      _loadingText = 'GINHAWANG SAKAY MULA SA BAHAY';
    });

    // Short, non-blocking splash display to keep app feeling fast
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      print('🔐 [SplashScreen] Checking authentication...');
      final authService = Provider.of<AuthService>(context, listen: false);

      if (authService.currentUser != null) {
        print('👤 User is authenticated, ensuring user data is loaded...');
        
        // Ensure user data is loaded before redirecting
        if (authService.currentUserModel == null) {
          print('🔄 User data not loaded yet, refreshing...');
          await authService.refreshUserData().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⚠️ Warning: User data refresh timed out in SplashScreen');
            },
          );
        }

        // Trigger cleanup after user is authenticated
        print('🧹 [SplashScreen] User authenticated, triggering cleanup...');
        final firestoreService = Provider.of<FirestoreService>(
          context,
          listen: false,
        );

        final route = authService.getRedirectRoute();
        print('✅ Navigating to: $route');
        // Clear entire stack and push new route to prevent going back to splash
        Navigator.of(context).pushNamedAndRemoveUntil(
          route,
          (route) => false,
        );
      } else {
        // User is not logged in, go to login screen
        print('🔓 No user authenticated, navigating to login');
        // Clear entire stack and push new route to prevent going back to splash
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
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
                    const SizedBox(height: 80),

                    // Loading indicator with status
                    Column(
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _loadingText,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 100),
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
