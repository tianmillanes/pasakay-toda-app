import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import 'biometric_service.dart';
import '../firebase_options.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Notification service imports removed

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  User? get currentUser => _auth.currentUser;
  UserModel? _currentUserModel;
  UserModel? get currentUserModel => _currentUserModel;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  static const String _kStoredUserId = 'user_id';
  static const String _kRememberMe = 'remember_me';

  /// Secure logging - logs in debug mode, limited logs in production
  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint('[AuthService] $message');
    } else {
      // In production, log only critical authentication events
      if (message.contains('Sign in successful') || 
          message.contains('Sign in error') ||
          message.contains('User authenticated successfully')) {
        debugPrint('[AuthService] $message');
      }
    }
  }

  /// Secure error logging - logs in debug mode, critical errors in production
  void _logError(String message, dynamic error) {
    if (kDebugMode) {
      debugPrint('[AuthService] ERROR: $message - $error');
    } else {
      // In production, log only critical errors
      debugPrint('[AuthService] ERROR: $message');
    }
  }

  AuthService() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
    _initializePersistentSession();
  }

  /// Initialize persistent session from secure storage
  Future<void> _initializePersistentSession() async {
    try {
      // Check Remember Me preference
      final rememberMeStr = await _secureStorage.read(key: _kRememberMe);
      final rememberMe = rememberMeStr != 'false'; // Default to true if not set
      _logDebug('Remember Me preference: $rememberMe');

      // If Remember Me is false, we should sign out the user if they were automatically logged in
      if (!rememberMe && currentUser != null) {
        _logDebug('Remember Me is false, signing out restored session...');
        await signOut();
        return;
      }

      // Check for session expiration (security policy: force re-login after 30 days)
      if (currentUser != null) {
        final metadata = currentUser!.metadata;
        if (metadata.lastSignInTime != null) {
          final lastSignIn = metadata.lastSignInTime!;
          final difference = DateTime.now().difference(lastSignIn);
          const sessionTimeoutDays = 30;
          
          if (difference.inDays > sessionTimeoutDays) {
            _logDebug('Session expired (> $sessionTimeoutDays days), signing out...');
            await signOut();
            return;
          }
        }
      }

      final storedUserId = await _secureStorage.read(key: _kStoredUserId);
      
      if (storedUserId != null) {
        _logDebug('Found stored user ID: $storedUserId');
        // The user was previously logged in, but we'll let Firebase handle
        // the authentication state restoration automatically
      }
    } catch (e) {
      _logError('Error initializing persistent session', e);
      // If there's an error, clear any potentially corrupted stored data
      await _clearStoredSession();
    }
  }

  /// Set Remember Me preference
  Future<void> setRememberMe(bool value) async {
    try {
      await _secureStorage.write(key: _kRememberMe, value: value.toString());
    } catch (e) {
      _logError('Error setting remember me preference', e);
    }
  }

  /// Get Remember Me preference
  Future<bool> isRememberMeEnabled() async {
    try {
      final value = await _secureStorage.read(key: _kRememberMe);
      return value != 'false'; // Default to true
    } catch (e) {
      return true;
    }
  }

  /// Check if there's a stored session available
  Future<bool> hasStoredSession() async {
    try {
      final storedUserId = await _secureStorage.read(key: _kStoredUserId);
      return storedUserId != null && storedUserId.isNotEmpty;
    } catch (e) {
      _logError('Error checking for stored session', e);
      return false;
    }
  }

  /// Store user session in secure storage
  Future<void> _storeSession(String userId) async {
    try {
      await _secureStorage.write(key: _kStoredUserId, value: userId);
    } catch (e) {
      _logError('Error storing session', e);
    }
  }

  /// Clear stored session data
  Future<void> _clearStoredSession() async {
    try {
      await _secureStorage.delete(key: _kStoredUserId);
    } catch (e) {
      _logError('Error clearing stored session', e);
    }
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user != null) {
      // Optimization: If user model is already loaded for this user, skip reloading
      if (_currentUserModel?.id != user.uid) {
        await _loadUserModel(user.uid);
      }
      // Store session when user is authenticated
      await _storeSession(user.uid);
    } else {
      _currentUserModel = null;
      // Clear stored session when user signs out
      await _clearStoredSession();
    }
    notifyListeners();
  }

  Future<void> _loadUserModel(String uid) async {
    int retries = 0;
    const maxRetries = 3;
    
    // Input validation
    if (uid.trim().isEmpty) {
      _logError('Invalid UID provided to _loadUserModel', 'Empty UID');
      _currentUserModel = null;
      return;
    }
    
    _logDebug('Loading user model for UID: $uid');
    
    while (retries < maxRetries) {
      try {
        // Add timeout to prevent hanging (increased for mobile networks)
        _logDebug('Attempt ${retries + 1}/$maxRetries to fetch user document');
        DocumentSnapshot doc = await _firestore
            .collection('users')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 20));
        
        if (doc.exists && doc.data() != null) {
          try {
            final model = UserModel.fromFirestore(doc);
            
            // Security check: If account is deactivated, sign out immediately
            if (!model.isActive) {
              _logDebug('Account is deactivated for: ${model.name}. Signing out...');
              _currentUserModel = null;
              await signOut();
              return;
            }

            _currentUserModel = model;
            _logDebug('User model loaded successfully for: ${_currentUserModel?.name} (${_currentUserModel?.role})');
            
            // Initialize WebSocket connection for notifications
            await _initializeNotificationConnection();
            return; // Success, exit the retry loop
          } catch (modelError) {
            _logError('Error parsing user model', modelError);
            _currentUserModel = null;
            return;
          }
        } else {
          _logDebug('User document does not exist for UID: $uid');
          _currentUserModel = null;
          return; // Document doesn't exist, no point retrying
        }
      } on FirebaseException catch (e) {
        retries++;
        _logError('Firebase error loading user model (attempt $retries/$maxRetries)', e);
        _logError('Firebase code: ${e.code}, message: ${e.message}', e);
        
        if (retries >= maxRetries) {
          _logError('Max Firebase retries exceeded for user: $uid', e);
          _currentUserModel = null;
        } else {
          // Wait before retrying
          await Future.delayed(Duration(milliseconds: 500 * retries));
        }
      } catch (e) {
        retries++;
        _logError('General error loading user model (attempt $retries/$maxRetries)', e);
        
        if (retries >= maxRetries) {
          _logError('Max general retries exceeded for user: $uid', e);
          _currentUserModel = null;
        } else {
          // Wait before retrying
          await Future.delayed(Duration(milliseconds: 500 * retries));
        }
      }
    }
  }

  /// Initialize notification connections
  Future<void> _initializeNotificationConnection() async {
    try {
      if (_currentUserModel == null) {
        _logDebug('No user model available for notification initialization');
        return;
      }
      
      // Notification services removed - using Firestore listeners for real-time updates
      _logDebug('User authenticated successfully: ${_currentUserModel?.name} (${_currentUserModel?.role})');
    } catch (e) {
      _logError('Error initializing notification connection', e);
      // Don't rethrow - notification initialization failure shouldn't block login
    }
  }

  Future<void> refreshUserData() async {
    try {
      if (currentUser != null) {
        _logDebug('Refreshing user data for: ${currentUser?.uid}');
        await _loadUserModel(currentUser!.uid);
        notifyListeners();
        _logDebug('User data refreshed successfully');
      } else {
        _logDebug('No current user to refresh data for');
      }
    } catch (e) {
      _logError('Failed to refresh user data', e);
      // Don't rethrow - this prevents app crashes
      // User will still be logged in, just data might be stale
      _logDebug('User data refresh failed, but continuing with existing data');
    }
  }

  /// Check if a phone number already exists in the database
  Future<bool> _isPhoneNumberTaken(String phone) async {
    try {
      final cleanPhone = phone.trim();
      
      // Check Firestore users collection
      final querySnapshot = await _firestore
          .collection('users')
          .where('phone', isEqualTo: cleanPhone)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));
      
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      _logError('Error checking phone number', e);
      // If there's a permission denied error, the user is likely unauthenticated (new registration).
      // We must return false to let the registration proceed. 
      if (e.toString().contains('permission-denied')) {
        return false; 
      }
      // For other errors, allow registration to proceed
      // This prevents blocking legitimate users due to temporary network issues
      return false;
    }
  }

  /// Check if an email already exists in the database
  Future<bool> _isEmailTaken(String email) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      
      // Check Firestore users collection
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: cleanEmail)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 10));
      
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      _logError('Error checking email', e);
      // If there's a permission denied error, the user is likely unauthenticated (new registration).
      // We must return false to let the registration proceed. 
      if (e.toString().contains('permission-denied')) {
        return false; 
      }
      // For other errors, allow registration to proceed
      // This prevents blocking legitimate users due to temporary network issues
      return false;
    }
  }

  /// Check if email or phone number is already registered
  Future<void> checkIfEmailOrPhoneExists(String email, String phone) async {
    // Check if phone number is already registered
    final phoneExists = await _isPhoneNumberTaken(phone);
    if (phoneExists) {
      throw 'This phone number is already registered. Please use a different number.';
    }

    // Check if email is already registered
    final emailExists = await _isEmailTaken(email);
    if (emailExists) {
      throw 'This email address is already registered. Please use a different email.';
    }
  }

  /// Public method to check if phone number is taken (for verification flow)
  Future<bool> isPhoneNumberTaken(String phone) async {
    return await _isPhoneNumberTaken(phone);
  }

  /// Public method to check if email is taken (for verification flow)
  Future<bool> isEmailTaken(String email) async {
    return await _isEmailTaken(email);
  }

  Future<UserCredential?> signInWithEmailAndPassword(
    String email,
    String password, {
    bool rememberMe = true,
  }) async {
    try {
      final cleanEmail = email.trim().toLowerCase();
      
      // Input validation
      if (cleanEmail.isEmpty) {
        throw FirebaseAuthException(
          code: 'invalid-email',
          message: 'Email address is required.',
        );
      }
      
      if (password.trim().isEmpty) {
        throw FirebaseAuthException(
          code: 'weak-password',
          message: 'Password is required.',
        );
      }
      
      // Basic email format validation
      if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
        throw FirebaseAuthException(
          code: 'invalid-email',
          message: 'Invalid email address format.',
        );
      }
      
      _logDebug('Attempting sign in with email: $cleanEmail');
      try {
        _logDebug('Firebase project ID: ${DefaultFirebaseOptions.currentPlatform.projectId}');
      } catch (_) {
        _logDebug('Could not log project ID - platform might not be fully configured');
      }
      
      // Set persistence based on the rememberMe flag - only on Web
      if (kIsWeb) {
        await _auth.setPersistence(rememberMe ? Persistence.LOCAL : Persistence.SESSION);
      }

      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      
      // OPTIMIZATION: Load user model immediately and validate account status
      // This replaces the redundant Firestore fetch and ensures model is ready
      await _loadUserModel(result.user!.uid);
      
      // Check if loading succeeded and account is active
      if (_currentUserModel == null) {
        // If user is null, it means account was deactivated and signed out by _loadUserModel
        if (_auth.currentUser == null) {
          throw FirebaseAuthException(
            code: 'user-disabled',
            message: 'This account has been deactivated. Please contact support.',
          );
        } else {
          // Loading failed (network error, etc.) but still signed in
          // Sign out to prevent inconsistent state
          await signOut();
          throw FirebaseAuthException(
            code: 'network-error',
            message: 'Failed to load user profile. Please check your connection.',
          );
        }
      }
      
      await setRememberMe(rememberMe);
      
      _logDebug('Sign in successful for user: ${result.user?.uid}');
      return result;
    } on FirebaseAuthException catch (e) {
      _logError('Sign in error', e);
      _logError('FirebaseAuth code: ${e.code}, message: ${e.message}', e);
      try {
        _logDebug('Firebase project ID: ${DefaultFirebaseOptions.currentPlatform.projectId}');
      } catch (_) {}
      rethrow; // Preserve the FirebaseAuthException for the UI to handle
    } catch (e) {
      _logError('Unexpected sign in error', e);
      _logError('Error type: ${e.runtimeType}', e);
      throw FirebaseAuthException(
        code: 'unknown-error',
        message: 'An unexpected error occurred. Please try again.',
      );
    }
  }

  Future<UserCredential?> signInWithGoogle({UserRole role = UserRole.passenger}) async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null; // User canceled

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential result = await _auth.signInWithCredential(credential);
      await _handleSocialLogin(result.user, role);
      
      return result;
    } catch (e) {
      _logError('Google Sign-In Error', e);
      rethrow;
    }
  }

  Future<void> _handleSocialLogin(User? user, UserRole role) async {
    if (user == null) return;
    
    // Check if user document already exists
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) {
      // First time login - create user model
      UserModel userModel = UserModel(
        id: user.uid,
        name: user.displayName ?? 'Social User',
        email: user.email ?? '',
        phone: user.phoneNumber ?? '',
        role: role,
        barangayId: '', // Can be updated by user later
        barangayName: '',
        createdAt: DateTime.now(),
      );

      await _firestore.collection('users').doc(user.uid).set(userModel.toFirestore());
      _currentUserModel = userModel;
    } else {
      await _loadUserModel(user.uid);
    }
  }

  Future<UserCredential?> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required String phone,
    required UserRole role,
    required String barangayId,
    required String barangayName,
    bool skipExistsCheck = false,
  }) async {
    try {
      // SECURITY: Validate inputs
      if (name.trim().isEmpty || name.length < 2 || name.length > 100) {
        throw 'Invalid name. Must be between 2-100 characters.';
      }

      if (role == UserRole.driver && (barangayId.trim().isEmpty || barangayName.trim().isEmpty)) {
        throw 'Barangay selection is mandatory for drivers.';
      }
      
      if (phone.trim().isEmpty) {
        throw 'Phone number is required.';
      }

      // Check if phone number is already registered (skip if requested)
      if (!skipExistsCheck) {
        final phoneExists = await _isPhoneNumberTaken(phone);
        if (phoneExists) {
          throw 'This phone number is already registered. Please use a different number.';
        }

        // Check if email is already registered (skip if requested)
        final emailExists = await _isEmailTaken(email);
        if (emailExists) {
          throw 'This email address is already registered. Please use a different email.';
        }
      }
      
      // Sanitize name to prevent injection
      final sanitizedName = name.trim().replaceAll(RegExp(r'[<>{}]'), '');
      
      final cleanEmail = email.trim().toLowerCase();
      
      UserCredential result;
      try {
        result = await _auth.createUserWithEmailAndPassword(
          email: cleanEmail,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          throw 'This email address is already registered. Please use a different email.';
        }
        rethrow;
      }

      if (result.user != null) {
        UserModel userModel = UserModel(
          id: result.user!.uid,
          name: sanitizedName,
          email: cleanEmail,
          phone: phone,
          role: role,
          barangayId: barangayId,
          barangayName: barangayName,
          createdAt: DateTime.now(),
        );

        await _firestore
            .collection('users')
            .doc(result.user!.uid)
            .set(userModel.toFirestore());

        _currentUserModel = userModel;
      }

      return result;
    } catch (e) {
      _logError('Registration error', e);
      rethrow;
    }
  }

  Future<void> reauthenticate(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw 'No user logged in';
    
    try {
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      _logDebug('User re-authenticated successfully');
    } catch (e) {
      _logError('Re-authentication error', e);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _currentUserModel = null;
    // Clear stored session data when explicitly signing out
    await _clearStoredSession();
    _logDebug('User signed out');
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    if (_auth.currentUser == null) return;
    try {
      final uid = _auth.currentUser!.uid;
      // Delete user document from Firestore
      await _firestore.collection('users').doc(uid).delete();
      // Delete user from Firebase Auth
      await _auth.currentUser!.delete();
      _currentUserModel = null;
      await _clearStoredSession();
      _logDebug('User account deleted');
      notifyListeners();
    } catch (e) {
      _logError('Delete account error', e);
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      _logError('Send Password Reset Error', e);
      if (e.code == 'user-not-found') {
        throw 'No user found for that email.';
      } else if (e.code == 'invalid-email') {
        throw 'The email address is not valid.';
      }
      throw 'An unexpected error occurred. Please try again.';
    } catch (e) {
      _logError('Send Password Reset Error', e);
      rethrow;
    }
  }

  Future<void> updateProfile({String? name, String? phone}) async {
    if (_currentUserModel == null) return;

    try {
      Map<String, dynamic> updates = {};
      if (name != null && name.isNotEmpty) {
        updates['name'] = name.trim();
      }
      if (phone != null && phone.isNotEmpty) {
        // Optional: Add validation for the new phone number
        updates['phone'] = phone.trim();
      }

      if (updates.isNotEmpty) {
        await _firestore
            .collection('users')
            .doc(_currentUserModel!.id)
            .update(updates);

        // Refresh user data after update
        await refreshUserData();
      }
    } catch (e) {
      _logError('Update profile error', e);
      rethrow;
    }
  }

  String getRedirectRoute() {
    if (_currentUserModel == null) return '/login';

    switch (_currentUserModel!.role) {
      case UserRole.passenger:
        return '/passenger';
      case UserRole.driver:
        return '/driver';
      case UserRole.admin:
        return '/admin';
      default:
        return '/login';
    }
  }
}
