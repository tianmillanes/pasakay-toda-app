import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/driver_model.dart';
import '../models/ride_model.dart';

class BarangayStatsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get barangay statistics
  Future<Map<String, dynamic>> getBarangayStats(String barangayId) async {
    try {
      // Get total drivers in barangay
      final driversSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .where('barangayId', isEqualTo: barangayId)
          .get();

      // Get approved drivers
      final approvedDrivers = driversSnapshot.docs
          .where((doc) => doc['isApproved'] == true)
          .length;

      // Get online drivers
      final onlineDrivers = driversSnapshot.docs
          .where((doc) => doc['status'] == 'available')
          .length;

      // Get total passengers in barangay
      final passengersSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'passenger')
          .where('barangayId', isEqualTo: barangayId)
          .get();

      // Get active rides in barangay
      final activeRidesSnapshot = await _firestore
          .collection('rides')
          .where('barangayId', isEqualTo: barangayId)
          .where('status',
              whereIn: ['accepted', 'driverOnWay', 'driverArrived', 'inProgress'])
          .get();

      // Get completed rides for revenue calculation
      final completedRidesSnapshot = await _firestore
          .collection('rides')
          .where('barangayId', isEqualTo: barangayId)
          .where('status', isEqualTo: 'completed')
          .get();

      double totalRevenue = 0;
      for (var doc in completedRidesSnapshot.docs) {
        totalRevenue += (doc['fare'] as num?)?.toDouble() ?? 0;
      }

      return {
        'barangayId': barangayId,
        'totalDrivers': driversSnapshot.docs.length,
        'approvedDrivers': approvedDrivers,
        'onlineDrivers': onlineDrivers,
        'totalPassengers': passengersSnapshot.docs.length,
        'activeRides': activeRidesSnapshot.docs.length,
        'completedRides': completedRidesSnapshot.docs.length,
        'totalRevenue': totalRevenue,
        'timestamp': DateTime.now(),
      };
    } catch (e) {
      print('Error getting barangay stats: $e');
      return {};
    }
  }

  /// Get barangay stats as stream (real-time updates)
  Stream<Map<String, dynamic>> getBarangayStatsStream(String barangayId) {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .where('barangayId', isEqualTo: barangayId)
        .snapshots()
        .asyncMap((driverSnapshot) async {
      final approvedDrivers =
          driverSnapshot.docs.where((doc) => doc['isApproved'] == true).length;
      final onlineDrivers =
          driverSnapshot.docs.where((doc) => doc['status'] == 'available').length;

      final passengersSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'passenger')
          .where('barangayId', isEqualTo: barangayId)
          .get();

      final activeRidesSnapshot = await _firestore
          .collection('rides')
          .where('barangayId', isEqualTo: barangayId)
          .where('status',
              whereIn: ['accepted', 'driverOnWay', 'driverArrived', 'inProgress'])
          .get();

      return {
        'barangayId': barangayId,
        'totalDrivers': driverSnapshot.docs.length,
        'approvedDrivers': approvedDrivers,
        'onlineDrivers': onlineDrivers,
        'totalPassengers': passengersSnapshot.docs.length,
        'activeRides': activeRidesSnapshot.docs.length,
        'timestamp': DateTime.now(),
      };
    });
  }

  /// Get all barangays statistics
  Future<List<Map<String, dynamic>>> getAllBarangaysStats(
      List<String> barangayIds) async {
    try {
      List<Map<String, dynamic>> allStats = [];
      for (String barangayId in barangayIds) {
        final stats = await getBarangayStats(barangayId);
        allStats.add(stats);
      }
      return allStats;
    } catch (e) {
      print('Error getting all barangays stats: $e');
      return [];
    }
  }
}
