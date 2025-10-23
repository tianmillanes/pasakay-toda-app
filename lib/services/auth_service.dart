import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
// Notification service imports removed

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  UserModel? _currentUserModel;
  UserModel? get currentUserModel => _currentUserModel;

  AuthService() {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user != null) {
      await _loadUserModel(user.uid);
    } else {
      _currentUserModel = null;
    }
    notifyListeners();
  }

  Future<void> _loadUserModel(String uid) async {
    try {
      // Add timeout to prevent hanging
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));
      
      if (doc.exists) {
        _currentUserModel = UserModel.fromFirestore(doc);
        print('User model loaded: ${_currentUserModel?.role}');
        
        // Initialize WebSocket connection for notifications
        await _initializeNotificationConnection();
      } else {
        print('User document does not exist for uid: $uid');
        _currentUserModel = null;
      }
    } catch (e) {
      print('Error loading user model: $e');
      _currentUserModel = null;
    }
  }

  /// Initialize notification connections
  Future<void> _initializeNotificationConnection() async {
    if (_currentUserModel == null) return;
    
    // Notification services removed - using Firestore listeners for real-time updates
    print('User authenticated: ${_currentUserModel!.role.name}');
  }

  Future<void> refreshUserData() async {
    if (currentUser != null) {
      await _loadUserModel(currentUser!.uid);
      notifyListeners();
    } else {
      print('No current user to refresh data for');
    }
  }

  Future<UserCredential?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result;
    } catch (e) {
      print('Sign in error: $e');
      rethrow;
    }
  }

  Future<UserCredential?> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    required String phone,
    required UserRole role,
  }) async {
    try {
      // SECURITY: Validate inputs
      if (name.trim().isEmpty || name.length < 2 || name.length > 100) {
        throw Exception('Invalid name. Must be between 2-100 characters.');
      }
      
      if (phone.trim().isEmpty) {
        throw Exception('Phone number is required.');
      }
      
      // Sanitize name to prevent injection
      final sanitizedName = name.trim().replaceAll(RegExp(r'[<>{}]'), '');
      
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        UserModel userModel = UserModel(
          id: result.user!.uid,
          name: sanitizedName,
          email: email,
          phone: phone,
          role: role,
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
      print('Registration error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      // Notification services removed - no cleanup needed
      
      await _auth.signOut();
      _currentUserModel = null;
      notifyListeners();
    } catch (e) {
      print('Error signing out: $e');
      rethrow;
    }
  }

  Future<void> updateUserProfile({String? name, String? phone}) async {
    if (_currentUserModel == null) return;

    try {
      UserModel updatedUser = _currentUserModel!.copyWith(
        name: name,
        phone: phone,
      );

      await _firestore.collection('users').doc(_currentUserModel!.id).update({
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
      });

      _currentUserModel = updatedUser;
      notifyListeners();
    } catch (e) {
      print('Update profile error: $e');
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
    }
  }
}
