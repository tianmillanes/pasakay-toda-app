import 'package:flutter/foundation.dart';

/// Centralized loading state manager for the entire app
/// Provides a consistent way to track loading states across all services
class LoadingStateManager extends ChangeNotifier {
  static final LoadingStateManager _instance = LoadingStateManager._internal();
  factory LoadingStateManager() => _instance;
  LoadingStateManager._internal();

  final Map<String, bool> _loadingStates = {};
  final Map<String, String> _loadingMessages = {};
  final Map<String, double> _loadingProgress = {};

  /// Check if any loading operation is in progress
  bool get isLoading => _loadingStates.values.any((loading) => loading);

  /// Check if a specific operation is loading
  bool isOperationLoading(String operationKey) => _loadingStates[operationKey] ?? false;

  /// Get loading message for an operation
  String getLoadingMessage(String operationKey) => _loadingMessages[operationKey] ?? 'Loading...';

  /// Get loading progress for an operation (0.0 to 1.0)
  double getLoadingProgress(String operationKey) => _loadingProgress[operationKey] ?? 0.0;

  /// Start a loading operation
  void startLoading(String operationKey, {String message = 'Loading...'}) {
    _loadingStates[operationKey] = true;
    _loadingMessages[operationKey] = message;
    _loadingProgress[operationKey] = 0.0;
    notifyListeners();
  }

  /// Update loading progress
  void updateProgress(String operationKey, double progress, {String? message}) {
    _loadingProgress[operationKey] = progress.clamp(0.0, 1.0);
    if (message != null) {
      _loadingMessages[operationKey] = message;
    }
    notifyListeners();
  }

  /// Stop a loading operation
  void stopLoading(String operationKey) {
    _loadingStates[operationKey] = false;
    _loadingProgress[operationKey] = 0.0;
    notifyListeners();
  }

  /// Stop all loading operations
  void stopAllLoading() {
    for (var key in _loadingStates.keys) {
      _loadingStates[key] = false;
      _loadingProgress[key] = 0.0;
    }
    notifyListeners();
  }

  /// Get all active loading operations
  List<String> get activeOperations => _loadingStates.entries
      .where((entry) => entry.value)
      .map((entry) => entry.key)
      .toList();

  /// Batch loading state updates (useful for multiple simultaneous operations)
  void batchUpdate(Map<String, bool> updates) {
    _loadingStates.addAll(updates);
    notifyListeners();
  }
}

/// Mixin for services that need loading state management
mixin LoadingStateMixin on ChangeNotifier {
  final Map<String, bool> _operationLoading = {};
  final Map<String, String> _operationMessages = {};

  bool get isAnyLoading => _operationLoading.values.any((loading) => loading);

  bool isLoading(String operation) => _operationLoading[operation] ?? false;

  String getLoadingMessage(String operation) => _operationMessages[operation] ?? 'Loading...';

  void setLoading(String operation, bool loading, {String? message}) {
    _operationLoading[operation] = loading;
    if (message != null) {
      _operationMessages[operation] = message;
    }
    notifyListeners();
  }

  void startLoading(String operation, {String message = 'Loading...'}) {
    setLoading(operation, true, message: message);
  }

  void stopLoading(String operation) {
    setLoading(operation, false);
  }

  /// Wrap an async operation with loading state
  Future<T> withLoading<T>(
    String operation,
    Future<T> Function() task, {
    String? loadingMessage,
    void Function(T result)? onSuccess,
    void Function(Object error)? onError,
  }) async {
    try {
      startLoading(operation, message: loadingMessage ?? 'Loading...');
      final result = await task();
      onSuccess?.call(result);
      return result;
    } catch (e) {
      onError?.call(e);
      rethrow;
    } finally {
      stopLoading(operation);
    }
  }
}

/// Common operation keys for consistency across the app
class LoadingOperations {
  static const String auth = 'auth';
  static const String login = 'login';
  static const String register = 'register';
  static const String googleSignIn = 'googleSignIn';
  static const String loadProfile = 'loadProfile';
  static const String loadRides = 'loadRides';
  static const String loadDrivers = 'loadDrivers';
  static const String loadGeofences = 'loadGeofences';
  static const String createRide = 'createRide';
  static const String updateLocation = 'updateLocation';
  static const String loadBarangays = 'loadBarangays';
  static const String loadHistory = 'loadHistory';
  static const String loadStats = 'loadStats';
  static const String sendMessage = 'sendMessage';
  static const String uploadImage = 'uploadImage';
  static const String verifyId = 'verifyId';
  static const String scanLicense = 'scanLicense';
  static const String fetchFare = 'fetchFare';
  static const String updateProfile = 'updateProfile';
  static const String deleteAccount = 'deleteAccount';
}
