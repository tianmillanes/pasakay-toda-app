import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/driver_model.dart';
import '../models/ride_model.dart';
import 'fcm_notification_service.dart';

class FirestoreService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Notification methods removed

  // Driver operations
  Future<void> createDriverProfile(DriverModel driver) async {
    try {
      // Update existing user document with driver-specific fields
      await _firestore
          .collection('users')
          .doc(driver.id)
          .update(driver.toFirestore());
    } catch (e) {
      print('Error creating driver profile: $e');
      rethrow;
    }
  }

  Future<DriverModel?> getDriverProfile(String driverId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(driverId)
          .get();

      if (doc.exists) {
        return DriverModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  Future<void> updateDriverStatus(String driverId, DriverStatus status) async {
    try {
      await _firestore.collection('users').doc(driverId).update({
        'status': status.toString().split('.').last,
        'lastLocationUpdate': Timestamp.now(),
      });
    } catch (e) {
      print('Error updating driver status: $e');
      rethrow;
    }
  }

  // Update driver online status
  Future<void> updateDriverOnlineStatus(String driverId, bool isOnline) async {
    try {
      await _firestore.collection('users').doc(driverId).update({
        'isOnline': isOnline,
        'lastSeen': Timestamp.now(),
        'status': isOnline ? 'available' : 'offline',
      });

      // If driver goes offline, handle their current rides
      if (!isOnline) {
        await _handleOfflineDriverRides(driverId);
      }
    } catch (e) {
      print('Error updating driver online status: $e');
      rethrow;
    }
  }

  // Handle rides when driver goes offline
  Future<void> _handleOfflineDriverRides(String driverId) async {
    try {
      // Get rides assigned to this driver that are not completed
      final QuerySnapshot rideSnapshot = await _firestore
          .collection('rides')
          .where('driverId', isEqualTo: driverId)
          .where('status', whereIn: ['pending', 'accepted', 'inProgress'])
          .get();

      for (var rideDoc in rideSnapshot.docs) {
        final rideId = rideDoc.id;
        final rideData = rideDoc.data() as Map<String, dynamic>;
        final status = rideData['status'] as String;

        if (status == 'pending' || status == 'accepted') {
          // Reassign to another online driver
          await _reassignRideToOnlineDriver(rideId);
        } else if (status == 'inProgress') {
          // Mark as interrupted - needs admin intervention
          await _firestore.collection('rides').doc(rideId).update({
            'status': 'interrupted',
            'interruptedAt': Timestamp.now(),
            'reason': 'Driver went offline during trip',
          });
        }
      }
    } catch (e) {
      print('Error handling offline driver rides: $e');
    }
  }

  // Reassign ride to another online driver
  Future<void> _reassignRideToOnlineDriver(String rideId) async {
    try {
      // Remove current driver assignment
      await _firestore.collection('rides').doc(rideId).update({
        'driverId': FieldValue.delete(),
        'status': 'pending',
        'reassignedAt': Timestamp.now(),
      });

      // Try to assign to a new online driver
      await _assignRideToAvailableDriver(rideId);
    } catch (e) {
      print('Error reassigning ride: $e');
    }
  }

  // Get pending rides that need driver assignment
  Stream<List<Map<String, dynamic>>> getPendingRidesStream() {
    return _firestore
        .collection('rides')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList();
        });
  }

  Future<void> updateDriverLocation(String driverId, GeoPoint location) async {
    try {
      await _firestore.collection('users').doc(driverId).update({
        'currentLocation': location,
        'lastLocationUpdate': Timestamp.now(),
      });
    } catch (e) {
      print('Error updating driver location: $e');
      rethrow;
    }
  }

  // Ride operations
  Future<String> createRide(RideModel ride) async {
    try {
      DocumentReference docRef = await _firestore
          .collection('rides')
          .add(ride.toFirestore());

      // Auto-assign to an available online driver
      await _assignRideToOnlineDriver(docRef.id);

      return docRef.id;
    } catch (e) {
      print('Error creating ride: $e');
      rethrow;
    }
  }

  // Find and assign ride to an online driver
  Future<void> _assignRideToOnlineDriver(String rideId) async {
    try {
      // Get online drivers only
      final QuerySnapshot onlineDriversSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .where('isOnline', isEqualTo: true)
          .where('status', isEqualTo: 'available')
          .limit(1)
          .get();

      if (onlineDriversSnapshot.docs.isNotEmpty) {
        final driverId = onlineDriversSnapshot.docs.first.id;

        // Assign ride to the first available online driver
        await updateRideStatus(rideId, RideStatus.accepted, driverId: driverId);

        // Update driver status to busy
        await _firestore.collection('users').doc(driverId).update({
          'status': 'busy',
          'currentRide': rideId,
          'lastAssigned': Timestamp.now(),
        });

        print('Ride $rideId assigned to online driver $driverId');
      } else {
        print('No online drivers available for ride $rideId');
        // Keep ride in pending status for future assignment
      }
    } catch (e) {
      print('Error assigning ride to online driver: $e');
      // Don't rethrow - ride creation should still succeed
    }
  }

  // Check for online drivers before booking
  Future<List<Map<String, dynamic>>> getOnlineDrivers() async {
    try {
      print('=== DEBUG: Getting drivers in queue ===');

      // Get the queue
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queue')
          .get();

      List<String> queueDriverIds = [];
      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        queueDriverIds = List<String>.from(data?['drivers'] ?? []);
      }

      print('Drivers in queue: ${queueDriverIds.length}');
      print('Queue: $queueDriverIds');

      if (queueDriverIds.isEmpty) {
        print('No drivers in queue');
        return [];
      }

      // PERFORMANCE: Batch query using whereIn instead of loop (max 10 at a time)
      List<Map<String, dynamic>> onlineDrivers = [];

      // Firestore whereIn supports max 10 items, so batch if needed
      for (int i = 0; i < queueDriverIds.length; i += 10) {
        final batch = queueDriverIds.skip(i).take(10).toList();

        try {
          final QuerySnapshot driverSnapshot = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: batch)
              .get();

          for (var doc in driverSnapshot.docs) {
            final driverData = doc.data() as Map<String, dynamic>;
            onlineDrivers.add({...driverData, 'id': doc.id});
            print('Queue Driver ${doc.id}: status=${driverData['status']}');
          }
        } catch (e) {
          print('Error getting driver batch: $e');
        }
      }

      print('=== 📊 ONLINE DRIVERS SUMMARY ===');
      print('Total drivers in queue: ${onlineDrivers.length}');
      
      if (onlineDrivers.isEmpty) {
        print('❌ NO DRIVERS AVAILABLE - Passengers will see "No drivers online"');
      } else {
        print('✅ Available drivers:');
        for (final driver in onlineDrivers) {
          final approved = driver['isApproved'] ?? false;
          final inQueue = driver['isInQueue'] ?? false;
          final status = approved && inQueue ? '✅ READY' : '❌ NOT READY';
          print('   ${driver['name']} (${driver['id']}) - $status');
        }
      }
      return onlineDrivers;
    } catch (e) {
      print('Error getting online drivers: $e');
      return [];
    }
  }

  // Stream of online drivers for real-time updates
  Stream<List<Map<String, dynamic>>> getOnlineDriversStream() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList();
        });
  }

  // Enhanced ride creation with real-time driver checking
  Future<Map<String, dynamic>> createRideWithDriverCheck(RideModel ride) async {
    try {
      print('=== CREATING RIDE WITH DRIVER CHECK ===');

      // SECURITY: Validate ride data
      if (!_isValidFare(ride.fare)) {
        return {
          'success': false,
          'error': 'Invalid fare amount. Please check and try again.',
          'rideId': null,
        };
      }

      if (!_isValidCoordinate(
        ride.pickupLocation.latitude,
        ride.pickupLocation.longitude,
      )) {
        return {
          'success': false,
          'error': 'Invalid pickup location coordinates.',
          'rideId': null,
        };
      }

      if (!_isValidCoordinate(
        ride.dropoffLocation.latitude,
        ride.dropoffLocation.longitude,
      )) {
        return {
          'success': false,
          'error': 'Invalid dropoff location coordinates.',
          'rideId': null,
        };
      }

      // First, check if there are any online drivers
      final onlineDrivers = await getOnlineDrivers();
      print('Online drivers found: ${onlineDrivers.length}');

      if (onlineDrivers.isEmpty) {
        print('No online drivers available');
        return {
          'success': false,
          'error': 'No drivers are currently online. Please try again later.',
          'rideId': null,
        };
      }

      // Create the ride with cancellation allowed initially
      Map<String, dynamic> rideData = ride.toFirestore();
      rideData['canBeCancelled'] = true; // Allow cancellation until driver accepts
      
      // Debug: Log the addresses being stored
      print('📍 Creating ride with addresses:');
      print('   Pickup: "${rideData['pickupAddress']}"');
      print('   Dropoff: "${rideData['dropoffAddress']}"');
      
      DocumentReference docRef = await _firestore
          .collection('rides')
          .add(rideData);

      print('Ride created with ID: ${docRef.id}');

      // Try to assign to an available online driver
      print('Attempting to assign ride to driver...');
      final assigned = await _assignRideToAvailableDriver(docRef.id);
      print('Assignment result: $assigned');
      
      // If no driver was assigned via queue, try direct assignment to any online driver
      if (!assigned && onlineDrivers.isNotEmpty) {
        print('Queue assignment failed, trying direct assignment...');
        final directAssigned = await _directAssignToFirstOnlineDriver(docRef.id, onlineDrivers);
        print('Direct assignment result: $directAssigned');
        
        return {
          'success': true,
          'rideId': docRef.id,
          'driverAssigned': directAssigned,
          'onlineDriverCount': onlineDrivers.length,
          'assignmentMethod': directAssigned ? 'direct' : 'failed',
        };
      }

      return {
        'success': true,
        'rideId': docRef.id,
        'driverAssigned': assigned,
        'onlineDriverCount': onlineDrivers.length,
      };
    } catch (e) {
      print('Error creating ride with driver check: $e');
      return {
        'success': false,
        'error': 'Failed to book ride: $e',
        'rideId': null,
      };
    }
  }

  // Updated driver assignment method with return value - includes queue system
  Future<bool> _assignRideToAvailableDriver(String rideId) async {
    try {
      print('=== RIDE ASSIGNMENT DEBUG for ride $rideId ===');

      // Step 1: Get the current queue
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queue')
          .get();

      List<String> queue = [];
      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        queue = List<String>.from(data?['drivers'] ?? []);
      }

      print('Queue document exists: ${queueDoc.exists}');
      print('Drivers in queue: ${queue.length}');
      print('Queue: $queue');

      if (queue.isEmpty) {
        print('No drivers in queue for ride $rideId');
        return false;
      }

      // Step 2: PERFORMANCE: Batch fetch all drivers in queue, then find first available
      String? availableDriverId;

      // Batch query drivers (max 10 at a time due to Firestore whereIn limit)
      for (int i = 0; i < queue.length && availableDriverId == null; i += 10) {
        final batch = queue.skip(i).take(10).toList();

        try {
          final QuerySnapshot driverSnapshot = await _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: batch)
              .get();

          // Build map for quick lookup
          final driverMap = {
            for (var doc in driverSnapshot.docs)
              doc.id: doc.data() as Map<String, dynamic>,
          };

          // Check drivers in queue order (not query order)
          for (String driverId in batch) {
            final driverData = driverMap[driverId];

            if (driverData != null) {
              final status = driverData['status'] ?? 'offline';
              final role = driverData['role'] ?? 'unknown';
              final isApproved = driverData['isApproved'] ?? false;
              final isInQueue = driverData['isInQueue'] ?? false;

              print('Driver $driverId: role=$role, status=$status');

              if (isApproved && isInQueue) {
                availableDriverId = driverId;
                print(
                  '✅ Found available driver: $driverId (approved: $isApproved, inQueue: $isInQueue)',
                );
                break; // Found first available driver in queue
              } else {
                print(
                  '❌ Driver $driverId not available: approved=$isApproved, inQueue=$isInQueue',
                );
              }
            } else {
              print('❌ Driver document does not exist: $driverId');
            }
          }
        } catch (e) {
          print('Error checking driver batch: $e');
        }
      }

      if (availableDriverId != null) {
        // Step 3: Send ride request to the available driver (don't auto-accept)
        await _firestore.collection('rides').doc(rideId).update({
          'assignedDriverId': availableDriverId,
          'assignedAt': Timestamp.now(),
          'status': 'pending', // Keep as pending until driver accepts
        });

        // Step 4: Get ride details to include passenger information
        final rideDoc = await _firestore.collection('rides').doc(rideId).get();
        final rideData = rideDoc.data() as Map<String, dynamic>;

        // Get passenger details
        final passengerId = rideData['passengerId'];
        final passengerDoc = await _firestore
            .collection('users')
            .doc(passengerId)
            .get();
        final passengerData = passengerDoc.data() as Map<String, dynamic>;

        // Step 5: Create ride request notification for driver
        print('📱 Creating notification for driver $availableDriverId');
        print('   Passenger: ${passengerData['name']}');
        print('   From: ${rideData['pickupAddress']}');
        print('   To: ${rideData['destinationAddress']}');
        print('   Fare: ₱${rideData['fare']}');
        
        // Send FCM push notification to driver
        final fcmService = FCMNotificationService();
        await fcmService.sendNotificationToUser(
          targetUserId: availableDriverId,
          title: '🚗 New Ride Request!',
          body: 'From: ${rideData['pickupAddress']} to ${rideData['destinationAddress']}',
          data: {
            'type': 'ride_request',
            'rideId': rideId,
            'passengerId': passengerId,
            'passengerName': passengerData['name'],
            'passengerPhone': passengerData['phone'] ?? '',
            'pickupAddress': rideData['pickupAddress'],
            'destinationAddress': rideData['destinationAddress'],
            'fare': rideData['fare'].toString(),
          },
        );
        
        print('📋 Ride request created and notification sent to driver $availableDriverId');

        // Real-time updates also handled via Firestore listeners in driver dashboard

        // Don't remove from queue or change status until driver accepts

        print(
          'Ride $rideId assigned to queued online driver $availableDriverId',
        );
        return true;
      } else {
        print('No online drivers available in queue for ride $rideId');
        return false;
      }
    } catch (e) {
      print('Error assigning ride to queued driver: $e');
      return false;
    }
  }

  // Driver accepts a ride request
  Future<void> acceptRideRequest(String rideId, String driverId) async {
    try {
      // SECURITY: Verify ride exists and is assigned to this driver
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        throw Exception('Ride not found');
      }

      final rideData = rideDoc.data() as Map<String, dynamic>;
      final assignedDriverId = rideData['assignedDriverId'];
      final currentStatus = rideData['status'];

      // SECURITY: Verify this driver is assigned to this ride
      if (assignedDriverId != driverId) {
        throw Exception('Unauthorized: Ride not assigned to this driver');
      }

      // SECURITY: Prevent race condition - verify ride is still pending
      if (currentStatus != 'pending') {
        throw Exception('Ride is no longer available (status: $currentStatus)');
      }

      // SECURITY: Use transaction to prevent race conditions
      await _firestore.runTransaction((transaction) async {
        // Re-check status inside transaction
        final freshRideDoc = await transaction.get(
          _firestore.collection('rides').doc(rideId),
        );
        if (!freshRideDoc.exists) {
          throw Exception('Ride not found');
        }

        final freshData = freshRideDoc.data() as Map<String, dynamic>;
        if (freshData['status'] != 'pending') {
          throw Exception('Ride already accepted by another driver');
        }

        // Update ride status - prevent passenger cancellation once accepted
        transaction.update(_firestore.collection('rides').doc(rideId), {
          'status': 'accepted',
          'driverId': driverId,
          'acceptedAt': Timestamp.now(),
          'canBeCancelled': false, // Prevent passenger cancellation
        });
      });

      // Update driver status to busy
      await _firestore.collection('users').doc(driverId).update({
        'status': 'busy',
        'currentRide': rideId,
        'lastAssigned': Timestamp.now(),
      });

      // Remove driver from queue (they're now busy)
      await removeDriverFromQueue(driverId);

      // Send push notification to passenger about driver acceptance
      // Reuse rideData from validation above
      final passengerId = rideData['passengerId'];
      if (passengerId != null) {
        // FCM notifications removed - using Firestore real-time listeners
        print('✅ Ride accepted - passenger will be notified via UI updates');
      }

      print('Ride $rideId accepted by driver $driverId');
    } catch (e) {
      print('Error accepting ride request: $e');
      rethrow;
    }
  }

  // Driver declines a ride request
  Future<void> declineRideRequest(String rideId, String driverId) async {
    try {
      print('🚫 === DECLINE RIDE REQUEST DEBUG ===');
      print('   Ride ID: $rideId');
      print('   Driver ID: $driverId');
      
      // SECURITY: Verify ride exists and is assigned to this driver
      print('📄 Checking if ride exists...');
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        print('❌ Ride not found in database');
        throw Exception('Ride not found');
      }
      print('✅ Ride document found');

      final rideData = rideDoc.data() as Map<String, dynamic>;
      final assignedDriverId = rideData['assignedDriverId'];
      final rideStatus = rideData['status'];
      
      print('📋 Ride details:');
      print('   Assigned Driver: $assignedDriverId');
      print('   Current Status: $rideStatus');
      print('   Requesting Driver: $driverId');

      // SECURITY: Verify this driver is assigned to this ride
      if (assignedDriverId != driverId) {
        print('❌ Authorization failed: Driver not assigned to this ride');
        throw Exception('Unauthorized: Ride not assigned to this driver');
      }
      print('✅ Authorization passed');

      // STEP 1: Unassign the ride from the declining driver
      print('📝 Unassigning ride from declining driver...');
      await _firestore.collection('rides').doc(rideId).update({
        'assignedDriverId': FieldValue.delete(),
        'status': 'pending', // Reset to pending for reassignment
        'declinedBy': FieldValue.arrayUnion([driverId]), // Track who declined
        'declinedAt': Timestamp.now(),
      });
      print('✅ Ride unassigned from driver $driverId');

      // STEP 2: Move driver to end of queue (instead of removing completely)
      print('🔄 Moving driver to end of queue...');
      await _moveDriverToEndOfQueue(driverId);
      print('✅ Driver moved to end of queue');

      // STEP 3: Track that this driver declined this ride
      await _firestore.collection('users').doc(driverId).update({
        'lastDeclinedAt': Timestamp.now(),
        'declineCount': FieldValue.increment(1),
      });

      // STEP 4: Get ride details to notify passenger (reuse validated rideData)
      final passengerId = rideData['passengerId'];
      
      // First, notify passenger about decline
      if (passengerId != null) {
        await _createPassengerDeclineNotification(
          rideId,
          passengerId,
          driverId,
          rideData, // Pass ride data for pickup/dropoff info
        );
      }

      // STEP 5: Try to assign to next driver in queue
      print('🔄 Looking for next available driver after decline...');
      final reassigned = await _assignRideToAvailableDriver(rideId);

      if (reassigned) {
        print('✅ Successfully reassigned ride $rideId to next driver');
        // Notify passenger that we found another driver
        if (passengerId != null) {
          await _createFoundAnotherDriverNotification(rideId, passengerId);
        }
      } else {
        print('❌ No more drivers available for ride $rideId');
        // No more drivers available, mark ride as failed
        await _firestore.collection('rides').doc(rideId).update({
          'status': 'failed',
          'failedReason': 'No available drivers',
          'failedAt': Timestamp.now(),
        });

        // Notify passenger about no drivers available with option to return home
        if (passengerId != null) {
          await _createNoDriversAvailableNotification(rideId, passengerId, rideData);
        }
      }

      print(
        'Ride $rideId declined by driver $driverId, driver removed from queue',
      );
    } catch (e) {
      print('Error declining ride request: $e');
      rethrow;
    }
  }

  // Create notification for passenger when driver declines
  Future<void> _createPassengerDeclineNotification(
    String rideId,
    String passengerId,
    String driverId,
    Map<String, dynamic> rideData,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'type': 'ride_declined',
        'userId': passengerId,
        'rideId': rideId,
        'driverId': driverId,
        'title': 'Driver Declined Your Request',
        'body':
            'The assigned driver declined your ride request from ${rideData['pickupAddress'] ?? 'pickup location'} to ${rideData['dropoffAddress'] ?? 'destination'}. Looking for another driver...',
        'createdAt': Timestamp.now(),
        'read': false,
        'action': 'find_another_driver',
        'pickupAddress': rideData['pickupAddress'] ?? '',
        'dropoffAddress': rideData['dropoffAddress'] ?? '',
      });
    } catch (e) {
      print('Error creating passenger decline notification: $e');
    }
  }

  // Create notification for passenger when no drivers are available
  Future<void> _createNoDriversAvailableNotification(
    String rideId,
    String passengerId,
    Map<String, dynamic> rideData,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'type': 'no_drivers_available',
        'userId': passengerId,
        'rideId': rideId,
        'title': 'No Drivers Available',
        'body':
            'Sorry, there are no drivers available for your trip from ${rideData['pickupAddress'] ?? 'pickup location'} to ${rideData['dropoffAddress'] ?? 'destination'}. Please try again later.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'action': 'return_home',
        'pickupAddress': rideData['pickupAddress'] ?? '',
        'dropoffAddress': rideData['dropoffAddress'] ?? '',
      });
    } catch (e) {
      print('Error creating no drivers available notification: $e');
    }
  }

  // Create notification for passenger when another driver is found
  Future<void> _createFoundAnotherDriverNotification(
    String rideId,
    String passengerId,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'type': 'found_another_driver',
        'userId': passengerId,
        'rideId': rideId,
        'title': 'Found Another Driver!',
        'body': 'Great! We found another driver for your ride request. Please wait for confirmation.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'action': 'wait_for_driver',
      });
    } catch (e) {
      print('Error creating found another driver notification: $e');
    }
  }

  // Notification methods removed - using Firestore listeners for real-time updates

  // Notification cleanup methods removed - no longer needed

  // Notification cleanup methods removed - no longer needed

  /// Create admin notification for new driver registration
  Future<void> createDriverRegistrationNotification(
    String driverId,
    String driverName,
  ) async {
    try {
      // Get all admin users
      final adminQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      // Create notification for each admin
      for (final adminDoc in adminQuery.docs) {
        await _firestore.collection('notifications').add({
          'type': 'new_driver_registration',
          'userId': adminDoc.id,
          'title': 'New Driver Registration',
          'body':
              '$driverName has applied to become a driver and needs approval',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'driverId': driverId,
          'driverName': driverName,
        });
      }
      print('Driver registration notifications created for admins');
    } catch (e) {
      print('Error creating driver registration notifications: $e');
    }
  }

  /// Create system alert notification for admins
  Future<void> createSystemAlertNotification(
    String message,
    String alertType,
  ) async {
    try {
      // Get all admin users
      final adminQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      // Create notification for each admin
      for (final adminDoc in adminQuery.docs) {
        await _firestore.collection('notifications').add({
          'type': 'system_alert',
          'userId': adminDoc.id,
          'title': 'System Alert',
          'body': message,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'alertType': alertType,
        });
      }
      print('System alert notifications created for admins');
    } catch (e) {
      print('Error creating system alert notifications: $e');
    }
  }

  /// Create ride status update notification
  Future<void> createRideStatusNotification(
    String userId,
    String rideId,
    String status,
    String message,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'type': 'ride_status_update',
        'userId': userId,
        'rideId': rideId,
        'title': 'Ride Update',
        'body': message,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'status': status,
      });
      print('Ride status notification created for user: $userId');
    } catch (e) {
      print('Error creating ride status notification: $e');
    }
  }

  // Get available ride requests for a driver (shows all pending rides that need drivers)
  Stream<List<Map<String, dynamic>>> getDriverNotifications(String driverId) {
    return _firestore
        .collection('rides')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snapshot) async {
          final rideRequests = <Map<String, dynamic>>[];
          
          print('🔍 Processing ${snapshot.docs.length} pending rides available for drivers');
          
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final assignedDriverId = data['assignedDriverId'] as String?;
            final passengerId = data['passengerId'] as String?;
            final declinedBy = data['declinedBy'] as List<dynamic>? ?? [];
            
            // Skip rides that this driver has already declined
            if (declinedBy.contains(driverId)) {
              print('  ⏭️ Skipping ride ${doc.id} - already declined by this driver');
              continue;
            }
            
            // Show rides that are either:
            // 1. Not assigned to any driver yet (available for any driver)
            // 2. Specifically assigned to this driver (waiting for acceptance)
            if (assignedDriverId == null || assignedDriverId.isEmpty || assignedDriverId == driverId) {
              print('  🚗 Available ride ${doc.id}: ${data['pickupAddress']} → ${data['dropoffAddress']}');
              print('    📍 Raw pickup: "${data['pickupAddress']}"');
              print('    📍 Raw dropoff: "${data['dropoffAddress']}"');
              
              // Fetch passenger details
              String passengerName = 'Passenger';
              String passengerPhone = '';
              
              if (passengerId != null && passengerId.isNotEmpty) {
                try {
                  final passengerDoc = await _firestore.collection('users').doc(passengerId).get();
                  if (passengerDoc.exists) {
                    final passengerData = passengerDoc.data() as Map<String, dynamic>;
                    passengerName = passengerData['name'] ?? 'Passenger';
                    passengerPhone = passengerData['phone'] ?? '';
                    print('    👤 Passenger: $passengerName');
                  }
                } catch (e) {
                  print('    ⚠️ Error fetching passenger details: $e');
                }
              }
              
              // Add ride request with formatted data for UI
              rideRequests.add({
                'id': doc.id,
                'rideId': doc.id,
                'type': 'ride_request',
                'title': 'New Ride Request',
                'body': 'From ${data['pickupAddress'] ?? 'pickup'} to ${data['dropoffAddress'] ?? 'destination'}',
                'pickupAddress': data['pickupAddress'] ?? 'Pickup location',
                'destinationAddress': data['dropoffAddress'] ?? 'Destination',
                'passengerName': passengerName,
                'passengerPhone': passengerPhone,
                'fare': data['fare'] ?? 0.0,
                'createdAt': data['createdAt'] ?? Timestamp.now(),
                'read': false, // Always show as unread since it's a pending ride
                'assignedToMe': assignedDriverId == driverId,
              });
            }
          }
          
          print('📋 Returning ${rideRequests.length} available ride requests');
          
          // Sort by creation time (newest first)
          rideRequests.sort((a, b) {
            final aTime = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final bTime = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            return bTime.compareTo(aTime);
          });
          
          return rideRequests;
        });
  }

  /// Check if a ride can be cancelled by passenger
  Future<bool> canCancelRide(String rideId) async {
    try {
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        return false;
      }
      
      final rideData = rideDoc.data() as Map<String, dynamic>;
      final status = rideData['status'] as String?;
      final canBeCancelled = rideData['canBeCancelled'] as bool? ?? true;
      
      // Can only cancel if:
      // 1. Status is still 'pending' (not accepted by driver yet)
      // 2. canBeCancelled flag is true
      // Once driver accepts (status becomes 'accepted'), passenger cannot cancel
      return status == 'pending' && canBeCancelled;
    } catch (e) {
      print('Error checking if ride can be cancelled: $e');
      return false;
    }
  }

  /// Cancel ride by passenger (only if allowed)
  Future<Map<String, dynamic>> cancelRideByPassenger(String rideId, String passengerId) async {
    try {
      // Check if ride can be cancelled
      final canCancel = await canCancelRide(rideId);
      if (!canCancel) {
        return {
          'success': false,
          'error': 'This ride cannot be cancelled. The driver may have already accepted it.',
        };
      }

      // Get ride details before cancelling
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        return {
          'success': false,
          'error': 'Ride not found.',
        };
      }

      final rideData = rideDoc.data() as Map<String, dynamic>;
      final assignedDriverId = rideData['assignedDriverId'] as String?;

      // Cancel the ride
      await _firestore.collection('rides').doc(rideId).update({
        'status': 'cancelled',
        'cancelledBy': 'passenger',
        'cancelledAt': Timestamp.now(),
        'canBeCancelled': false,
      });

      // If there was an assigned driver, notify them and put them back in queue
      if (assignedDriverId != null) {
        // Notify driver about cancellation
        await _firestore.collection('notifications').add({
          'type': 'ride_cancelled_by_passenger',
          'userId': assignedDriverId,
          'rideId': rideId,
          'title': 'Ride Cancelled',
          'body': 'The passenger has cancelled the ride request.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Mark driver as available and remove current ride
        await _firestore.collection('users').doc(assignedDriverId).update({
          'status': 'available',
          'currentRide': null,
        });
      }

      return {
        'success': true,
        'message': 'Ride cancelled successfully.',
      };
    } catch (e) {
      print('Error cancelling ride: $e');
      return {
        'success': false,
        'error': 'Failed to cancel ride. Please try again.',
      };
    }
  }

  /// SECURITY: Input validation helpers
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  bool _isValidPhoneNumber(String phone) {
    // Remove common formatting characters
    final cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    // Check if it's a valid Philippine mobile number (10-11 digits)
    return cleanPhone.length >= 10 &&
        cleanPhone.length <= 13 &&
        RegExp(r'^\+?[0-9]+$').hasMatch(cleanPhone);
  }

  bool _isValidFare(double fare) {
    return fare >= 0 && fare <= 100000; // Max fare 100k PHP
  }

  bool _isValidCoordinate(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  String _sanitizeString(String input, {int maxLength = 500}) {
    // Remove potential script injections and limit length
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(RegExp(r'[^\w\s\-\.,@]'), '') // Allow only safe characters
        .substring(0, input.length > maxLength ? maxLength : input.length)
        .trim();
  }

  /// SECURITY: Validate ride status transitions
  bool _isValidStatusTransition(String? currentStatus, String newStatus) {
    // Allow any transition from null/pending to any status (initial creation)
    if (currentStatus == null || currentStatus == 'pending') {
      return true;
    }

    // Define valid transitions
    final validTransitions = {
      'accepted': ['driverOnWay', 'cancelled'],
      'driverOnWay': ['driverArrived', 'cancelled'],
      'driverArrived': ['inProgress', 'cancelled'],
      'inProgress': ['completed', 'cancelled'],
      'completed': [], // Terminal state
      'cancelled': [], // Terminal state
      'failed': ['cancelled'], // Allow cancelling failed rides
    };

    final allowedNext = validTransitions[currentStatus] ?? [];
    return allowedNext.contains(newStatus);
  }

  // Check if driver is in queue
  Future<bool> isDriverInQueue(String driverId) async {
    try {
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queue')
          .get();

      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        final queue = List<String>.from(data?['drivers'] ?? []);
        return queue.contains(driverId);
      }
      return false;
    } catch (e) {
      print('Error checking if driver is in queue: $e');
      return false;
    }
  }

  Future<void> updateRideStatus(
    String rideId,
    RideStatus status, {
    String? driverId,
  }) async {
    try {
      // SECURITY: Verify ride exists and get current data
      final rideDoc = await _firestore.collection('rides').doc(rideId).get()
          .timeout(const Duration(seconds: 5));
      if (!rideDoc.exists) {
        throw Exception('Ride not found');
      }

      final currentData = rideDoc.data() as Map<String, dynamic>;
      final currentDriverId = currentData['driverId'];

      // SECURITY: For driver-initiated status updates, verify authorization
      if (driverId != null &&
          currentDriverId != null &&
          currentDriverId != driverId) {
        throw Exception(
          'Unauthorized: Only assigned driver can update this ride',
        );
      }

      // SECURITY: Validate status transitions
      final currentStatus = currentData['status'];
      if (!_isValidStatusTransition(
        currentStatus,
        status.toString().split('.').last,
      )) {
        throw Exception(
          'Invalid status transition from $currentStatus to ${status.toString().split('.').last}',
        );
      }

      Map<String, dynamic> updates = {
        'status': status.toString().split('.').last,
      };

      switch (status) {
        case RideStatus.accepted:
          updates['acceptedAt'] = Timestamp.now();
          if (driverId != null) updates['driverId'] = driverId;
          break;
        case RideStatus.inProgress:
          updates['startedAt'] = Timestamp.now();
          break;
        case RideStatus.completed:
          updates['completedAt'] = Timestamp.now();
          break;
        case RideStatus.cancelled:
          updates['cancelledAt'] = Timestamp.now();
          break;
        default:
          break;
      }

      await _firestore.collection('rides').doc(rideId).update(updates)
          .timeout(const Duration(seconds: 5));

      // Send push notification for status updates (except accepted, which is handled separately)
      // Use timeout and catch errors to prevent blocking
      if (status != RideStatus.accepted) {
        _sendRideStatusNotification(rideId, status, driverId)
            .timeout(const Duration(seconds: 3))
            .catchError((e) {
          print('Warning: Failed to send notification: $e');
          // Don't rethrow - notification failure shouldn't block status update
        });
      }
    } catch (e) {
      print('Error updating ride status: $e');
      rethrow;
    }
  }

  /// Send push notification for ride status updates
  Future<void> _sendRideStatusNotification(
    String rideId,
    RideStatus status,
    String? driverId,
  ) async {
    try {
      // Get ride details
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) return;

      final rideData = rideDoc.data() as Map<String, dynamic>;
      final passengerId = rideData['passengerId'];

      // Get driver details if available
      String driverName = 'Driver';
      if (driverId != null) {
        final driverDoc = await _firestore
            .collection('users')
            .doc(driverId)
            .get();
        if (driverDoc.exists) {
          final driverData = driverDoc.data() as Map<String, dynamic>;
          driverName = driverData['name'] ?? 'Driver';
        }
      }

      // Send notification to notifications collection
      String notificationType = 'ride_${status.name}';
      String title = 'Ride ${status.name}';
      String body = 'Your ride has been ${status.name} by $driverName';

      // Customize messages for specific statuses
      switch (status) {
        case RideStatus.driverOnWay:
          title = '🚗 Driver On The Way!';
          body = 'Your ride with $driverName is on the way!';
          break;
        case RideStatus.driverArrived:
          title = '📍 Driver Arrived!';
          body = 'Your driver $driverName has arrived at your pickup location!';
          break;
        case RideStatus.inProgress:
          title = '🚗 Ride In Progress!';
          body = 'Your ride with $driverName is currently in progress!';
          break;
        case RideStatus.completed:
          title = '✅ Ride Completed!';
          body =
              'Your ride with $driverName is completed. Thank you for using Pasakay Toda!';
          break;
        case RideStatus.cancelled:
          title = '❌ Ride Cancelled';
          body = 'Your ride has been cancelled by $driverName';
          break;
        default:
          break;
      }

      await _firestore.collection('notifications').add({
        'userId': passengerId,
        'type': notificationType,
        'title': title,
        'body': body,
        'data': rideData,
        'read': false,
        'createdAt': Timestamp.now(),
      });

      if (kDebugMode) {
        print('✅ Ride status notification sent to passenger: $passengerId');
      }
    } catch (e) {
      print('Error sending ride status notification: $e');
    }
  }

  Stream<List<RideModel>> getUserRides(String userId, {bool isDriver = false}) {
    String field = isDriver ? 'driverId' : 'passengerId';
    // PERFORMANCE: Use database-side sorting (requires composite index)
    // Index needed: rides collection on (passengerId, requestedAt) and (driverId, requestedAt)
    return _firestore
        .collection('rides')
        .where(field, isEqualTo: userId)
        .orderBy('requestedAt', descending: true)
        .limit(50) // PERFORMANCE: Limit to recent 50 rides to improve load time
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => RideModel.fromFirestore(doc))
              .toList();
        });
  }

  Stream<RideModel?> getRideStream(String rideId) {
    return _firestore.collection('rides').doc(rideId).snapshots().map((doc) {
      if (doc.exists) {
        return RideModel.fromFirestore(doc);
      }
      return null;
    });
  }

  // Queue operations
  Future<void> addDriverToQueue(String driverId) async {
    try {
      // Get current queue
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queue')
          .get();

      List<String> queue = [];
      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        queue = List<String>.from(data?['drivers'] ?? []);
      }

      if (!queue.contains(driverId)) {
        // Check if driver has recently declined a ride (within last hour)
        final driverDoc = await _firestore
            .collection('users')
            .doc(driverId)
            .get();
        bool hasRecentDecline = false;

        if (driverDoc.exists) {
          final driverData = driverDoc.data() as Map<String, dynamic>;
          final lastDeclinedAt = driverData['lastDeclinedAt'] as Timestamp?;

          if (lastDeclinedAt != null) {
            final declineTime = lastDeclinedAt.toDate();
            final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
            hasRecentDecline = declineTime.isAfter(hourAgo);
          }
        }

        // If driver has recent decline, add to end of queue (penalty)
        // Otherwise, add normally to end of queue
        queue.add(driverId);

        await _firestore.collection('system').doc('queue').set({
          'drivers': queue,
        });

        // Update driver queue status in users collection
        await _firestore.collection('users').doc(driverId).update({
          'isInQueue': true,
          'queuePosition': queue.length,
          'status': 'available', // Set status to available when joining queue
          'queueJoinedAt': Timestamp.now(),
          'penaltyApplied': hasRecentDecline,
        });

        if (hasRecentDecline) {
          print(
            'Driver $driverId added to queue with penalty (recent decline)',
          );
        } else {
          print('Driver $driverId added to queue normally');
        }
      }
    } catch (e) {
      print('Error adding driver to queue: $e');
      rethrow;
    }
  }

  Future<void> removeDriverFromQueue(String driverId) async {
    try {
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queue')
          .get();

      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        List<String> queue = List<String>.from(data?['drivers'] ?? []);
        queue.remove(driverId);

        // PERFORMANCE: Use batch writes instead of individual updates
        final batch = _firestore.batch();

        // Update queue document
        batch.set(_firestore.collection('system').doc('queue'), {
          'drivers': queue,
        });

        // Update queue positions for remaining drivers
        for (int i = 0; i < queue.length; i++) {
          batch.update(_firestore.collection('users').doc(queue[i]), {
            'queuePosition': i + 1,
          });
        }

        // Update removed driver's queue status
        batch.update(_firestore.collection('users').doc(driverId), {
          'isInQueue': false,
          'queuePosition': 0,
          'status': 'offline',
        });

        // Commit all changes in single batch
        await batch.commit();
      } else {
        // Just update the driver's status if queue doesn't exist
        await _firestore.collection('users').doc(driverId).update({
          'isInQueue': false,
          'queuePosition': 0,
          'status': 'offline',
        });
      }
    } catch (e) {
      print('Error removing driver from queue: $e');
      rethrow;
    }
  }

  /// Direct assignment to first online driver (fallback when queue fails)
  Future<bool> _directAssignToFirstOnlineDriver(
    String rideId,
    List<Map<String, dynamic>> onlineDrivers,
  ) async {
    try {
      print('🔄 Direct assignment: Trying ${onlineDrivers.length} online drivers');
      
      for (final driverData in onlineDrivers) {
        final driverId = driverData['id'] as String;
        final isApproved = driverData['isApproved'] ?? false;
        final role = driverData['role'] ?? '';
        
        print('Checking driver $driverId: approved=$isApproved, role=$role');
        
        if (role == 'driver' && isApproved) {
          print('✅ Assigning ride $rideId to driver $driverId (direct)');
          
          // Update ride with assigned driver
          await _firestore.collection('rides').doc(rideId).update({
            'assignedDriverId': driverId,
            'assignedAt': Timestamp.now(),
            'status': 'pending',
          });
          
          // Notification removed - driver will see ride via Firestore listeners
          print('📋 Ride assigned to driver $driverId - they will see it in their dashboard');
          
          print('✅ Direct assignment successful: ride $rideId → driver $driverId');
          return true;
        }
      }
      
      print('❌ No suitable driver found for direct assignment');
      return false;
    } catch (e) {
      print('❌ Error in direct assignment: $e');
      return false;
    }
  }

  /// Move driver to end of queue (used when driver declines a ride)
  Future<void> _moveDriverToEndOfQueue(String driverId) async {
    try {
      print('🔄 Moving driver $driverId to end of queue...');
      
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queue')
          .get();

      if (!queueDoc.exists) {
        print('⚠️ Queue document does not exist');
        return;
      }

      final data = queueDoc.data() as Map<String, dynamic>?;
      List<String> queue = List<String>.from(data?['drivers'] ?? []);

      // Remove driver from current position
      if (!queue.contains(driverId)) {
        print('⚠️ Driver $driverId not in queue');
        return;
      }

      queue.remove(driverId);
      // Add driver to end of queue
      queue.add(driverId);

      print('📋 New queue order: $queue');

      // PERFORMANCE: Use batch writes
      final batch = _firestore.batch();

      // Update queue document
      batch.set(_firestore.collection('system').doc('queue'), {
        'drivers': queue,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update queue positions for all drivers
      for (int i = 0; i < queue.length; i++) {
        batch.update(_firestore.collection('users').doc(queue[i]), {
          'queuePosition': i + 1,
        });
      }

      // Commit all changes
      await batch.commit();

      print('✅ Driver $driverId moved to position ${queue.length} (end of queue)');
    } catch (e) {
      print('❌ Error moving driver to end of queue: $e');
      rethrow;
    }
  }

  Future<String?> getNextDriverInQueue() async {
    try {
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queue')
          .get();

      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        List<String> queue = List<String>.from(data?['drivers'] ?? []);
        return queue.isNotEmpty ? queue.first : null;
      }
      return null;
    } catch (e) {
      print('Error getting next driver in queue: $e');
      return null;
    }
  }

  Stream<List<String>> getQueueStream() {
    return _firestore.collection('system').doc('queue').snapshots().map((doc) {
      if (doc.exists) {
        final data = doc.data();
        return List<String>.from(data?['drivers'] ?? []);
      }
      return <String>[];
    });
  }

  // System settings
  Future<bool> getMaintenanceMode() async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('system')
          .doc('settings')
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        return data?['maintenance'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error getting maintenance mode: $e');
      return false;
    }
  }

  Future<void> setMaintenanceMode(bool maintenance) async {
    try {
      await _firestore.collection('system').doc('settings').set({
        'maintenance': maintenance,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error setting maintenance mode: $e');
      rethrow;
    }
  }

  Stream<bool> getMaintenanceModeStream() {
    return _firestore.collection('system').doc('settings').snapshots().map((
      doc,
    ) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        return data?['maintenance'] ?? false;
      }
      return false;
    });
  }

  // Admin operations
  Future<void> approveDriver(String driverId, String adminId) async {
    try {
      // SECURITY: Verify the user performing this action is an admin
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin user not found');
      }

      final adminData = adminDoc.data() as Map<String, dynamic>;
      if (adminData['role'] != 'admin') {
        throw Exception('Unauthorized: Only admins can approve drivers');
      }

      // SECURITY: Verify driver exists and is actually a driver
      final driverDoc = await _firestore
          .collection('users')
          .doc(driverId)
          .get();
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      if (driverData['role'] != 'driver') {
        throw Exception('User is not a driver');
      }

      // Update in users collection where driver profile is loaded from
      await _firestore.collection('users').doc(driverId).update({
        'isApproved': true,
        'approvedAt': Timestamp.now(),
        'approvedBy': adminId,
      });

      // Notification removed - driver will see approval status via Firestore listeners
      print('✅ Driver approved - they will see the update in their dashboard');
    } catch (e) {
      print('Error approving driver: $e');
      rethrow;
    }
  }

  Future<void> deactivateDriver(String driverId, String adminId) async {
    try {
      // SECURITY: Verify the user performing this action is an admin
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin user not found');
      }

      final adminData = adminDoc.data() as Map<String, dynamic>;
      if (adminData['role'] != 'admin') {
        throw Exception('Unauthorized: Only admins can deactivate drivers');
      }

      // SECURITY: Verify driver exists
      final driverDoc = await _firestore
          .collection('users')
          .doc(driverId)
          .get();
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }

      // Update in users collection where driver profile is loaded from
      await _firestore.collection('users').doc(driverId).update({
        'isApproved': false,
      });

      // Remove from queue if in queue
      await removeDriverFromQueue(driverId);
    } catch (e) {
      print('Error deactivating driver: $e');
      rethrow;
    }
  }

  Stream<List<DriverModel>> getAllDrivers() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => DriverModel.fromFirestore(doc))
              .toList(),
        );
  }

  /// PERFORMANCE: Stream single driver's data instead of all drivers
  Stream<DriverModel?> getDriverStream(String driverId) {
    return _firestore.collection('users').doc(driverId).snapshots().map((doc) {
      if (doc.exists) {
        return DriverModel.fromFirestore(doc);
      }
      return null;
    });
  }

  Stream<List<RideModel>> getAllActiveRides() {
    return _firestore
        .collection('rides')
        .where(
          'status',
          whereIn: ['accepted', 'driverOnWay', 'driverArrived', 'inProgress'],
        )
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => RideModel.fromFirestore(doc)).toList(),
        );
  }

  // FCM Token Management
  Future<void> updateUserFCMToken(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
      print('FCM token updated for user: $userId');
    } catch (e) {
      print('Error updating FCM token: $e');
      rethrow;
    }
  }

  /// Register FCM token and subscribe to topics
  Future<void> registerUserForNotifications(
    String userId,
    String role,
    String token,
  ) async {
    try {
      // Update user's FCM token
      await updateUserFCMToken(userId, token);

      // Create notification preferences if they don't exist
      await _firestore.collection('user_preferences').doc(userId).set({
        'notifications': {
          'enabled': true,
          'rideUpdates': true,
          'systemAlerts': true,
          'promotions': false,
        },
        'role': role,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('User registered for notifications: $userId, role: $role');
    } catch (e) {
      print('Error registering user for notifications: $e');
      rethrow;
    }
  }

  Future<void> updateDriverFCMToken(String driverId, String token) async {
    try {
      await _firestore.collection('users').doc(driverId).update({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating driver FCM token: $e');
      rethrow;
    }
  }

  Future<String?> getUserFCMToken(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return doc.data()?['fcmToken'];
      }
      return null;
    } catch (e) {
      print('Error getting user FCM token: $e');
      return null;
    }
  }

  Future<String?> getDriverFCMToken(String driverId) async {
    try {
      final doc = await _firestore.collection('users').doc(driverId).get();
      if (doc.exists) {
        return doc.data()?['fcmToken'];
      }
      return null;
    } catch (e) {
      print('Error getting driver FCM token: $e');
      return null;
    }
  }

  // User Profile Management
  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _firestore.collection('users').doc(userId).update(data);
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('Error getting user profile: $e');
      return null;
    }
  }

  // Notification management removed - using Firestore listeners

  // All notification methods removed - using Firestore listeners for real-time updates

  // All FCM and notification methods removed - app now uses Firestore real-time listeners
}
