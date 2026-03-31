import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    print('Starting app initialization...');

    print('🔥 Initializing Firebase...');
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('✅ Firebase initialized for the first time');
      } else {
        print('ℹ️ Firebase already initialized, skipping...');
      }
      
      // Safe initialization of persistence and settings
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (e) {
        print('⚠️ Warning: Failed to set Auth persistence: $e');
      }
      
      try {
        // Disable Firestore persistence caching to ensure fresh data
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: false,
        );
      } catch (e) {
        // This often fails if Firestore was already accessed, which is fine
        print('ℹ️ Note: Firestore settings already applied or could not be changed: $e');
      }
    } catch (e) {
      if (e.toString().contains('duplicate-app') || e.toString().contains('already-exists')) {
        print('✅ Firebase already initialized (caught exception)');
      } else {
        print('❌ Firebase initialization failed: $e');
        rethrow;
      }
    }

    // Load environment variables after Firebase is ready
    print('🔐 Loading environment variables...');
    await CredentialsConfig.initialize();
    print('✅ Environment variables loaded');

    print('🎉 Essential initialization complete, launching app...');
    runApp(const PasakayApp());
    
    // Initialize non-essential services in background after app starts
    _initializeBackgroundServices();
  } catch (e, stackTrace) {
    print('❌ CRITICAL ERROR during app initialization: $e');
    print('Stack trace: $stackTrace');
    
    // Ensure WidgetsFlutterBinding is initialized for the error UI
    WidgetsFlutterBinding.ensureInitialized();
    
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 80, color: Colors.redAccent),
                  const SizedBox(height: 24),
                  const Text(
                    'App Initialization Error', 
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      e.toString(),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        // Restart the app by calling main() again
                        main();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Retry Initialization', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

// Initialize non-essential services in background
Future<void> _initializeBackgroundServices() async {
  try {
    print('🔒 Initializing HTTPS enforcement...');
    HTTPSConfig.logConfiguration();
    print('✅ HTTPS enforcement initialized');

    print('🗺️ Initializing Mapbox...');
    // Skip Mapbox initialization on web due to bool.fromEnvironment issue
    if (kIsWeb) {
      print('⚠️ Mapbox initialization skipped on web platform');
    } else {
      try {
        mapbox.MapboxOptions.setAccessToken(CredentialsConfig.mapboxAccessToken);
        print('✅ Mapbox initialized');
      } catch (e) {
        print('⚠️ Mapbox initialization failed: $e');
        print('📱 App will continue without Mapbox');
      }
    }

    // Initialize FCM for push notifications
    print('🔔 Initializing FCM...');
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FCMNotificationService().initialize();
      print('✅ FCM initialized successfully');
    } catch (e) {
      print('⚠️ Warning: FCM initialization failed: $e');
      print('📱 App will continue without push notifications');
    }

    print('🌐 Initializing Connectivity Service...');
    try {
      await ConnectivityService().initialize();
      print('✅ Connectivity Service initialized successfully');
    } catch (e) {
      print('⚠️ Warning: Connectivity Service initialization failed: $e');
      print('📱 App will continue without connectivity monitoring');
    }

    print('🎉 Background services initialization complete');
  } catch (e) {
    print('⚠️ Background services initialization failed: $e');
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
        title: 'Pasakay - Booking Made Easy',
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
