import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Service to monitor and manage connection status
class ConnectionStatusService {
  static final ConnectionStatusService _instance = ConnectionStatusService._internal();

  factory ConnectionStatusService() {
    return _instance;
  }

  ConnectionStatusService._internal();

  final Connectivity _connectivity = Connectivity();
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ConnectionStatus _currentStatus = ConnectionStatus.connected;

  /// Get the current connection status
  ConnectionStatus get currentStatus => _currentStatus;

  /// Get stream of connection status changes
  Stream<ConnectionStatus> get connectionStatusStream => _connectionStatusController.stream;

  /// Initialize the service
  Future<void> initialize() async {
    try {
      // Check initial connectivity
      final result = await _connectivity.checkConnectivity();
      _updateStatus(result);

      // Listen to connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
        _updateStatus(result);
      });
    } catch (e) {
      print('Error initializing connection status service: $e');
    }
  }

  /// Update connection status based on connectivity result
  void _updateStatus(dynamic result) {
    final newStatus = _mapConnectivityToStatus(result);
    if (newStatus != _currentStatus) {
      _currentStatus = newStatus;
      _connectionStatusController.add(_currentStatus);
      print('📡 Connection status changed: $_currentStatus');
    }
  }

  /// Map connectivity result to connection status
  ConnectionStatus _mapConnectivityToStatus(dynamic result) {
    if (result is List<ConnectivityResult>) {
      if (result.contains(ConnectivityResult.none)) {
        return ConnectionStatus.offline;
      }
      if (result.contains(ConnectivityResult.wifi)) {
        return ConnectionStatus.connectedWifi;
      }
      if (result.contains(ConnectivityResult.mobile)) {
        return ConnectionStatus.connectedMobile;
      }
      if (result.contains(ConnectivityResult.ethernet)) {
        return ConnectionStatus.connectedEthernet;
      }
    } else if (result is ConnectivityResult) {
      if (result == ConnectivityResult.none) {
        return ConnectionStatus.offline;
      }
      if (result == ConnectivityResult.wifi) {
        return ConnectionStatus.connectedWifi;
      }
      if (result == ConnectivityResult.mobile) {
        return ConnectionStatus.connectedMobile;
      }
      if (result == ConnectivityResult.ethernet) {
        return ConnectionStatus.connectedEthernet;
      }
    }
    return ConnectionStatus.connected;
  }

  /// Check if device is connected to internet
  bool get isConnected => _currentStatus != ConnectionStatus.offline;

  /// Check if device is connected via WiFi
  bool get isConnectedWifi => _currentStatus == ConnectionStatus.connectedWifi;

  /// Check if device is connected via mobile data
  bool get isConnectedMobile => _currentStatus == ConnectionStatus.connectedMobile;

  /// Dispose the service
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectionStatusController.close();
  }
}

/// Connection status enum
enum ConnectionStatus {
  offline,
  connected,
  connectedWifi,
  connectedMobile,
  connectedEthernet,
}

/// Extension for user-friendly connection status messages
extension ConnectionStatusExtension on ConnectionStatus {
  String get displayName {
    switch (this) {
      case ConnectionStatus.offline:
        return 'Offline';
      case ConnectionStatus.connected:
        return 'Connected';
      case ConnectionStatus.connectedWifi:
        return 'WiFi';
      case ConnectionStatus.connectedMobile:
        return 'Mobile Data';
      case ConnectionStatus.connectedEthernet:
        return 'Ethernet';
    }
  }

  String get displayMessage {
    switch (this) {
      case ConnectionStatus.offline:
        return 'No internet connection';
      case ConnectionStatus.connected:
        return 'Connected to internet';
      case ConnectionStatus.connectedWifi:
        return 'Connected via WiFi';
      case ConnectionStatus.connectedMobile:
        return 'Connected via mobile data';
      case ConnectionStatus.connectedEthernet:
        return 'Connected via ethernet';
    }
  }

  IconData get icon {
    switch (this) {
      case ConnectionStatus.offline:
        return Icons.wifi_off_rounded;
      case ConnectionStatus.connected:
        return Icons.cloud_done_rounded;
      case ConnectionStatus.connectedWifi:
        return Icons.wifi_rounded;
      case ConnectionStatus.connectedMobile:
        return Icons.signal_cellular_alt_rounded;
      case ConnectionStatus.connectedEthernet:
        return Icons.router_rounded;
    }
  }

  Color get color {
    switch (this) {
      case ConnectionStatus.offline:
        return Colors.red;
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connectedWifi:
        return Colors.green;
      case ConnectionStatus.connectedMobile:
        return Colors.green;
      case ConnectionStatus.connectedEthernet:
        return Colors.green;
    }
  }

  bool get isOnline => this != ConnectionStatus.offline;
}
