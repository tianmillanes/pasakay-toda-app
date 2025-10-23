import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/location_service.dart';
import 'services/fcm_notification_service.dart';
import 'utils/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/auth/passenger_register_screen.dart';
import 'screens/auth/driver_register_screen.dart';
import 'screens/passenger/passenger_dashboard.dart';
import 'screens/driver/driver_dashboard.dart';
import 'screens/driver/driver_registration_screen.dart';
import 'screens/admin/admin_dashboard.dart';

void main() async {
  try {
    print('🚀 Starting app initialization...');
    WidgetsFlutterBinding.ensureInitialized();

    print('🔥 Initializing Firebase...');
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      print('✅ Firebase initialized successfully');
    } catch (e) {
      if (e.toString().contains('duplicate-app')) {
        print('✅ Firebase already initialized, continuing...');
      } else {
        print('⚠️ Firebase initialization error: $e');
        rethrow;
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

    // Initialize Firestore settings with robust error handling
    print('📊 Initializing Firestore settings...');
    try {
      await initializeFirestore().timeout(Duration(seconds: 15));
      print('✅ Firestore initialized successfully');
    } catch (e) {
      print('⚠️ Warning: Firestore initialization failed: $e');
      print('📱 App will continue with default settings');
      // Continue app startup - the app can work without initial Firestore setup
    }

    print('🎉 App initialization complete, launching app...');
    runApp(const PasakayApp());
  } catch (e, stackTrace) {
    print('❌ CRITICAL ERROR during app initialization: $e');
    print('Stack trace: $stackTrace');
    
    // Run app anyway with minimal setup
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.blue),
              SizedBox(height: 16),
              Text('App initialization failed', 
                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Error: $e', textAlign: TextAlign.center),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Restart the app
                  main();
                },
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

Future<void> initializeFirestore() async {
  final firestore = FirebaseFirestore.instance;

  // Initialize barangay geofence if it doesn't exist
  try {
    print('🗺️ Checking barangay geofence...');
    final geofenceDoc = await firestore
        .collection('system')
        .doc('geofence')
        .get()
        .timeout(Duration(seconds: 5));
    
    if (!geofenceDoc.exists) {
      final barangayCoordinates = [
        {'lat': 14.6020, 'lng': 120.9850},
        {'lat': 14.6040, 'lng': 120.9870},
        {'lat': 14.6060, 'lng': 120.9890},
        {'lat': 14.6050, 'lng': 120.9910},
        {'lat': 14.6030, 'lng': 120.9890},
        {'lat': 14.6010, 'lng': 120.9870},
      ];
      await firestore.collection('system').doc('geofence').set({
        'coordinates': barangayCoordinates,
        'name': 'Service Area',
        'type': 'barangay',
      });
      print('✅ Barangay geofence initialized');
    } else {
      print('✅ Barangay geofence already exists');
    }
  } catch (e) {
    print('⚠️ Failed to initialize barangay geofence: $e');
  }

  // Initialize terminal geofence
  try {
    print('🏢 Checking terminal geofence...');
    final terminalDoc = await firestore
        .collection('system')
        .doc('terminal_geofence')
        .get()
        .timeout(Duration(seconds: 5));
    
    if (!terminalDoc.exists) {
      final terminalCoordinates = [
        {'lat': 14.6020, 'lng': 120.9850},
        {'lat': 14.6025, 'lng': 120.9845},
        {'lat': 14.6030, 'lng': 120.9855},
        {'lat': 14.6025, 'lng': 120.9860},
        {'lat': 14.6015, 'lng': 120.9855},
      ];
      await firestore.collection('system').doc('terminal_geofence').set({
        'coordinates': terminalCoordinates,
        'name': 'TODA Terminal',
        'type': 'terminal',
      });
      print('✅ Terminal geofence initialized');
    } else {
      print('✅ Terminal geofence already exists');
    }
  } catch (e) {
    print('⚠️ Failed to initialize terminal geofence: $e');
  }

  // Initialize maintenance mode setting
  try {
    print('🔧 Checking maintenance mode...');
    final maintenanceDoc = await firestore
        .collection('system')
        .doc('maintenance')
        .get()
        .timeout(Duration(seconds: 5));
    
    if (!maintenanceDoc.exists) {
      await firestore.collection('system').doc('maintenance').set({
        'enabled': false,
        'message': 'System is under maintenance. Please try again later.',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Maintenance mode initialized');
    } else {
      print('✅ Maintenance mode already exists');
    }
  } catch (e) {
    print('⚠️ Failed to initialize maintenance mode: $e');
  }

  // Initialize queue
  try {
    print('🚗 Checking driver queue...');
    final queueDoc = await firestore
        .collection('system')
        .doc('queue')
        .get()
        .timeout(Duration(seconds: 5));
    
    if (!queueDoc.exists) {
      await firestore.collection('system').doc('queue').set({
        'drivers': [],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Driver queue initialized');
    } else {
      print('✅ Driver queue already exists');
    }
  } catch (e) {
    print('⚠️ Failed to initialize driver queue: $e');
  }

  // Initialize system settings
  try {
    print('⚙️ Checking system settings...');
    final settingsDoc = await firestore
        .collection('system')
        .doc('settings')
        .get()
        .timeout(Duration(seconds: 5));
    
    if (!settingsDoc.exists) {
      await firestore.collection('system').doc('settings').set({
        'baseFare': 15.0,
        'farePerKm': 8.0,
        'minimumFare': 15.0,
        'maxWaitTime': 300, // 5 minutes
        'driverTrackingInterval': 10, // seconds
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ System settings initialized');
    } else {
      print('✅ System settings already exist');
    }
  } catch (e) {
    print('⚠️ Failed to initialize system settings: $e');
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
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'yourapp - Booking Made Easy',
        debugShowCheckedModeBanner: false, // Remove debug banner
        theme: AppTheme.lightTheme, // Enhanced accessibility theme
        home: const SplashScreen(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RoleSelectionScreen(),
          '/register/passenger': (context) => const PassengerRegisterScreen(),
          '/register/driver': (context) => const DriverRegisterScreen(),
          '/passenger': (context) => const PassengerDashboard(),
          '/driver': (context) => const DriverDashboard(),
          '/driver-registration': (context) => const DriverRegistrationScreen(),
          '/admin': (context) => const AdminDashboard(),
        },
      ),
    );
  }
}
