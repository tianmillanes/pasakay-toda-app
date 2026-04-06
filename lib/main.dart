import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'config/credentials_config.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/location_service.dart';
import 'services/fcm_notification_service.dart';
import 'services/https_enforcer.dart';
import 'services/connectivity_service.dart';
import 'utils/app_theme.dart';
import 'screens/splash_screen.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'screens/auth/login_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/auth/passenger_register_screen_with_verification.dart';
import 'screens/auth/driver_register_screen_with_verification.dart';
import 'screens/passenger/passenger_dashboard.dart';
import 'screens/driver/driver_dashboard.dart';
import 'screens/driver/driver_registration_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'services/route_guard.dart';
import 'models/user_model.dart';

// Global loading state for app initialization
final ValueNotifier<bool> isAppInitializing = ValueNotifier<bool>(true);
final ValueNotifier<String> appInitStatus = ValueNotifier<String>('Starting...');

void main() {
  // Run app immediately with loading state, then initialize in background
  WidgetsFlutterBinding.ensureInitialized();
  
  // Start the app immediately with a loading screen
  runApp(const PasakayAppLoader());
  
  // Initialize services in background after first frame
  SchedulerBinding.instance.addPostFrameCallback((_) {
    _initializeAppInBackground();
  });
}

// Background app initialization
Future<void> _initializeAppInBackground() async {
  try {
    appInitStatus.value = 'Initializing Firebase...';
    
    // Initialize Firebase
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    
    // Enable Firestore persistence for better performance
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      print('ℹ️ Firestore settings already applied: $e');
    }
    
    // Set auth persistence on web
    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (e) {
        print('⚠️ Auth persistence error: $e');
      }
    }
    
    appInitStatus.value = 'Loading configuration...';
    await CredentialsConfig.initialize();
    
    // Mark initialization complete
    isAppInitializing.value = false;
    appInitStatus.value = 'Ready!';
    
    // Start background services
    _initializeBackgroundServices();
  } catch (e, stackTrace) {
    print('❌ Initialization error: $e');
    print(stackTrace);
    appInitStatus.value = 'Error: $e';
    // Even on error, allow the app to continue
    isAppInitializing.value = false;
  }
}

class PasakayApp extends StatelessWidget {
  const PasakayApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => FirestoreService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
        Provider(create: (_) => ConnectivityService()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Pasakay',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RoleSelectionScreen(),
          '/register/passenger': (context) => const PassengerRegisterScreenWithVerification(),
          '/register/driver': (context) => const DriverRegisterScreenWithVerification(),
          '/passenger': (context) => const PassengerDashboard(),
          '/driver': (context) => const DriverDashboard(),
          '/driver-registration': (context) => const DriverRegistrationScreen(),
          '/admin': (context) => ProtectedRoute(
            requiredRole: UserRole.admin,
            child: const AdminDashboard(),
          ),
        },
      ),
    );
  }
}

// App loader widget that shows loading state while initializing
class PasakayAppLoader extends StatelessWidget {
  const PasakayAppLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isAppInitializing,
      builder: (context, isInitializing, child) {
        if (isInitializing) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: const _AppLoadingScreen(),
          );
        }
        return const PasakayApp();
      },
    );
  }
}

// Loading screen shown during initialization
class _AppLoadingScreen extends StatelessWidget {
  const _AppLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryGreen,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.local_taxi,
                size: 60,
                color: AppTheme.primaryGreen,
              ),
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
            const SizedBox(height: 60),
            
            // Loading indicator with status
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 4,
              ),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<String>(
              valueListenable: appInitStatus,
              builder: (context, status, child) {
                return Text(
                  status,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Initialize non-essential services in background
Future<void> _initializeBackgroundServices() async {
  try {
    print('🔒 Initializing HTTPS enforcement...');
    HTTPSConfig.logConfiguration();

    // Initialize Mapbox in background
    if (!kIsWeb) {
      try {
        mapbox.MapboxOptions.setAccessToken(CredentialsConfig.mapboxAccessToken);
        print('✅ Mapbox initialized');
      } catch (e) {
        print('⚠️ Mapbox initialization failed: $e');
      }
    }

    // Initialize FCM for push notifications
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FCMNotificationService().initialize();
      print('✅ FCM initialized');
    } catch (e) {
      print('⚠️ FCM initialization failed: $e');
    }

    // Initialize Connectivity Service
    try {
      await ConnectivityService().initialize();
      print('✅ Connectivity Service initialized');
    } catch (e) {
      print('⚠️ Connectivity Service failed: $e');
    }

    print('🎉 Background services complete');
  } catch (e) {
    print('⚠️ Background services failed: $e');
  }
}
