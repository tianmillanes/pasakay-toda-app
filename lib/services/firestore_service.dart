import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import '../models/driver_model.dart';
import '../models/ride_model.dart';
import '../models/barangay_model.dart';
import '../models/pasabuy_model.dart';
import '../models/gcash_qr_model.dart';
import 'fcm_notification_service.dart';
import 'barangay_service.dart';

class FirestoreService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const Set<String> _excludedBarangayNames = {
    'dungan',
    'san martin',
    'talimunduc marimla',
    'telabanca',
  };

  // Public getter for Firestore instance
  FirebaseFirestore get firestore => _firestore;

  // Notification methods removed

  // Driver operations
  Future<void> createDriverProfile(DriverModel driver) async {
    try {
      // Use set with merge to add driver-specific fields to existing user document
      // This allows adding new fields without triggering security rule violations
      await _firestore
          .collection('users')
          .doc(driver.id)
          .set(driver.toFirestore(), SetOptions(merge: true));
      
      // Create notification for admins about new driver registration
      await createDriverRegistrationNotification(
        driver.id,
        driver.name,
      );
      
      print('Driver profile created successfully for ${driver.name}');
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

      // Auto-assign to an available driver from the queue (barangay-filtered)
      await _assignRideToAvailableDriver(docRef.id);

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

  // Check for online drivers before booking (filtered by passenger's barangay)
  Future<List<Map<String, dynamic>>> getOnlineDrivers({String? passengerBarangayId}) async {
    try {
      print('=== DEBUG: Getting drivers in queue ===');
      print('Filtering by barangayId: $passengerBarangayId');

      List<String> queueDriverIds = [];

      if (passengerBarangayId != null && passengerBarangayId.isNotEmpty) {
        // Get the specific barangay queue
        DocumentSnapshot queueDoc = await _firestore
            .collection('system')
            .doc('queues')
            .collection('barangays')
            .doc(passengerBarangayId)
            .get();

        if (queueDoc.exists) {
          final data = queueDoc.data() as Map<String, dynamic>?;
          queueDriverIds = List<String>.from(data?['drivers'] ?? []);
        }
      } else {
        // Fallback to global queue (legacy) or return empty
        print('No barangay ID provided, checking legacy global queue');
        DocumentSnapshot queueDoc = await _firestore
            .collection('system')
            .doc('queue')
            .get();
            
        if (queueDoc.exists) {
          final data = queueDoc.data() as Map<String, dynamic>?;
          queueDriverIds = List<String>.from(data?['drivers'] ?? []);
        }
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
            final driverBarangayId = driverData['barangayId'] as String?;
            
            // Filter by barangay if provided
            if (passengerBarangayId != null && driverBarangayId != passengerBarangayId) {
              print('Skipping driver ${doc.id}: barangayId=$driverBarangayId (passenger barangayId=$passengerBarangayId)');
              continue;
            }
            
            // CRITICAL: Check driver status and approval (missing in original code)
            final status = driverData['status'] ?? 'offline';
            final role = driverData['role'] ?? 'unknown';
            final isApproved = driverData['isApproved'] ?? false;
            final isInQueue = driverData['isInQueue'] ?? false;
            
            print('Queue Driver ${doc.id}: role=$role, status=$status, barangayId=$driverBarangayId');
            print('   Checks: approved=$isApproved, inQueue=$isInQueue');
            
            // Only add drivers who are approved, in queue, and have correct role
            // NOTE: Queue membership takes priority over status - if in queue, they're available
            if (role == 'driver' && isApproved && isInQueue && 
                (status == 'available' || status == 'offline')) { // Allow both available and offline for queue drivers
              onlineDrivers.add({...driverData, 'id': doc.id});
              print('Driver ${doc.id} added to available drivers list');
            } else {
              print('Driver ${doc.id} not available: role=$role, approved=$isApproved, inQueue=$isInQueue, status=$status');
            }
          }
        } catch (e) {
          print('Error getting driver batch: $e');
        }
      }

      print('=== ONLINE DRIVERS SUMMARY ===');
      print('Total drivers in queue (filtered): ${onlineDrivers.length}');
      
      if (onlineDrivers.isEmpty) {
        print('NO DRIVERS AVAILABLE - Passengers will see "No drivers online"');
        print('   This means no drivers in queue are: approved=true + isInQueue=true + role=driver + same barangay');
        print('   Note: Queue drivers can be either "available" or "offline" status');
      } else {
        print('Available drivers:');
        for (final driver in onlineDrivers) {
          final approved = driver['isApproved'] ?? false;
          final inQueue = driver['isInQueue'] ?? false;
          final status = driver['status'] ?? 'unknown';
          final statusText = (approved && inQueue && status == 'available') ? '✅ READY' : '❌ NOT READY';
          print('   ${driver['name']} (${driver['id']}) - $statusText');
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

  // Get total number of users
  Stream<int> getTotalUsers() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs.length;
    });
  }

  // Get recent system events for admin dashboard
  Stream<QuerySnapshot> getRecentSystemEvents() {
    return _firestore
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots();
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

      // Determine which barangay the pickup location belongs to
      final pickupBarangayId = await getBarangayForLocation(
        ride.pickupLocation.latitude,
        ride.pickupLocation.longitude,
      );
      
      print('📍 Pickup location barangay: $pickupBarangayId');
      
      if (pickupBarangayId == null) {
        return {
          'success': false,
          'error': 'Pickup location is outside all service areas. Please select a location within any covered barangay.',
          'rideId': null,
        };
      }

      // Get barangay name for the pickup location
      final pickupBarangayDoc = await _firestore
          .collection('barangays')
          .doc(pickupBarangayId)
          .get();
      
      final pickupBarangayName = pickupBarangayDoc.exists 
          ? (pickupBarangayDoc.data()?['name'] as String? ?? 'Unknown Barangay')
          : 'Unknown Barangay';

      print('📍 Pickup location barangay name: $pickupBarangayName');

      // Use per-barangay queue as source of truth for available drivers
      final queueDriverIds = await getQueueForBarangay(pickupBarangayId);
      print('📊 Queue drivers in barangay $pickupBarangayId: $queueDriverIds');

      if (queueDriverIds.isEmpty) {
        print('No drivers in barangay queue for pickup barangay');
        return {
          'success': false,
          'error': 'No drivers are currently available in that area. Please try again later.',
          'rideId': null,
        };
      }

      // Always assign to first driver in barangay queue (FIFO)
      final selectedDriverId = queueDriverIds.first;
      print('🎯 Selected driver from barangay queue for initial assignment: $selectedDriverId');

      Map<String, dynamic> rideData = ride.toFirestore();
      rideData['canBeCancelled'] = true; // Allow cancellation until driver accepts
      
      // Update ride with pickup location's barangay information
      rideData['barangayId'] = pickupBarangayId;
      rideData['barangayName'] = pickupBarangayName;
      
      // Debug: Log the addresses being stored
      print('📍 Creating ride with addresses:');
      print('   Pickup: "${rideData['pickupAddress']}"');
      print('   Dropoff: "${rideData['dropoffAddress']}"');
      print('   Pickup Barangay: $pickupBarangayId ($pickupBarangayName)');
      
      DocumentReference docRef = await _firestore
          .collection('rides')
          .add(rideData);

      print('Ride created with ID: ${docRef.id}');

      // Now assign driver via update, to comply with Firestore rules
      await _firestore.collection('rides').doc(docRef.id).update({
        'assignedDriverId': selectedDriverId,
        'assignedAt': Timestamp.now(),
      });
      print('✅ Initial driver assignment saved for ride ${docRef.id}');

      return {
        'success': true,
        'rideId': docRef.id,
        'driverAssigned': true,
        'assignedDriverId': selectedDriverId,
        'onlineDriverCount': queueDriverIds.length,
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

  /// Aggressively resolve 'busy' status if driver is in queue
  Future<bool> _resolveBusyStatusIfInQueue(String driverId) async {
    try {
      print('🧹 Checking/Resolving busy status for queued driver $driverId...');
      
      // Check for active rides that might be "ghosts"
      final activeRides = await _firestore
          .collection('rides')
          .where('assignedDriverId', isEqualTo: driverId)
          .where('status', whereIn: ['accepted', 'inProgress', 'driverOnWay', 'driverArrived'])
          .get();

      if (activeRides.docs.isNotEmpty) {
        for (final ride in activeRides.docs) {
           print('   ⚠️ Found conflicting active ride ${ride.id} (${ride.data()['status']})');
           // Since driver is in queue, this MUST be a ghost/stale ride. Auto-cancel it.
           await _firestore.collection('rides').doc(ride.id).update({
             'status': 'cancelled',
             'cancelledBy': 'system_auto_resolve',
             'cancelReason': 'Driver in queue but had active ride (ghost ride)',
             'cancelledAt': Timestamp.now(),
           });
           print('   ✅ Auto-cancelled ghost ride ${ride.id}');
        }
      }

      // Check for active PasaBuys
      final activePasaBuys = await _firestore
          .collection('pasabuy_requests')
          .where('assignedDriverId', isEqualTo: driverId)
          .where('status', whereIn: ['accepted', 'driver_on_way', 'arrived_pickup', 'delivery_in_progress'])
          .get();

      if (activePasaBuys.docs.isNotEmpty) {
        for (final pb in activePasaBuys.docs) {
           print('   ⚠️ Found conflicting active PasaBuy ${pb.id} (${pb.data()['status']})');
           await _firestore.collection('pasabuy_requests').doc(pb.id).update({
             'status': 'cancelled',
             'cancelledBy': 'system_auto_resolve',
             'cancelReason': 'Driver in queue but had active pasabuy (ghost)',
             'cancelledAt': Timestamp.now(),
           });
           print('   ✅ Auto-cancelled ghost PasaBuy ${pb.id}');
        }
      }
      
      // Force update user status
      await _firestore.collection('users').doc(driverId).update({
        'status': 'available',
        'currentRide': null,
        'currentPasaBuy': null,
      });
      print('   ✅ Driver status reset to available');

      return true;
    } catch (e) {
      print('❌ Error resolving busy status: $e');
      return false;
    }
  }

  // Updated driver assignment method with return value - includes queue system
  Future<bool> _assignRideToAvailableDriver(String rideId) async {
    try {
      print('=== RIDE ASSIGNMENT DEBUG for ride $rideId ===');
      print('Timestamp: ${DateTime.now().toIso8601String()}');

      // Step 1: Get ride data to find passenger and their barangay
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        print('❌ Ride not found: $rideId');
        return false;
      }
      final rideData = rideDoc.data() as Map<String, dynamic>;
      
      final passengerId = rideData['passengerId'] as String?;
      if (passengerId == null) {
        print('❌ No passenger ID in ride data');
        return false;
      }
      
      // Use the ride's barangay (pickup area) for queue selection
      final rideBarangayId = rideData['barangayId'] as String?;
      print('🏘️ Ride barangayId (pickup area): $rideBarangayId');

      if (rideBarangayId == null) {
        print('❌ Ride has no barangay assigned');
        return false;
      }

      // Step 2: Get the queue for this barangay
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(rideBarangayId)
          .get();

      List<String> queue = [];
      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        // The queue is ordered by joining time (oldest first)
        queue = List<String>.from(data?['drivers'] ?? []);
      }

      print('📋 Queue document exists: ${queueDoc.exists}');
      print('📋 Drivers in queue: ${queue.length}');
      print('📋 Queue order: $queue');

      if (queue.isEmpty) {
        print('❌ No drivers in queue for ride $rideId in barangay $rideBarangayId');
        return false;
      }
      
      // Step 3: Find first eligible and available driver in queue order (FIFO)
      String? availableDriverId;

      // Get list of drivers who already declined this ride
      final declinedBy = List<String>.from(rideData['declinedBy'] as List? ?? []);

      // Create a list of driver data with their queueJoinedAt timestamp
      List<Map<String, dynamic>> driverQueueData = [];
      for (String driverId in queue) {
        // Skip drivers who already declined
        if (declinedBy.contains(driverId)) {
          print('⏭️ Skipping driver $driverId (already declined this ride)');
          continue;
        }

        final DocumentSnapshot driverDoc = await _firestore.collection('users').doc(driverId).get();
        if (driverDoc.exists) {
          final driverData = driverDoc.data() as Map<String, dynamic>;
          driverQueueData.add({
            'driverId': driverId,
            'queueJoinedAt': driverData['queueJoinedAt'] ?? Timestamp.now(),
          });
        }
      }

      // Sort the drivers by their queueJoinedAt timestamp
      driverQueueData.sort((a, b) => (a['queueJoinedAt'] as Timestamp).compareTo(b['queueJoinedAt'] as Timestamp));

      // Check drivers one by one in queue order to ensure strict FIFO
      for (var driverData in driverQueueData) {
        final driverId = driverData['driverId'];
        print('🔍 Checking queue position ${driverQueueData.indexOf(driverData) + 1}/${driverQueueData.length}: Driver $driverId');
        
        try {
          final DocumentSnapshot driverDoc = await _firestore
              .collection('users')
              .doc(driverId)
              .get();

          if (driverDoc.exists) {
            final driverProfileData = driverDoc.data() as Map<String, dynamic>;
            final status = driverProfileData['status'] ?? 'offline';
            final role = driverProfileData['role'] ?? 'unknown';
            final isApproved = driverProfileData['isApproved'] ?? false;
            var isInQueue = driverProfileData['isInQueue'] ?? false;
            final driverBarangayId = driverProfileData['barangayId'] as String?;

            print('   Driver $driverId details:');
            print('     role: $role');
            print('     status: $status');
            print('     approved: $isApproved');
            print('     inQueue: $isInQueue');
            print('     barangayId: $driverBarangayId');

            // Pick the first eligible driver in queue order (same barangay, approved, still in queue, not busy)
            
            // SELF-HEALING: If driver is in the queue list, they SHOULD be eligible.
            // Fix inconsistencies between queue list and user profile.
            if (isApproved && !isInQueue) {
               print('⚠️ Driver $driverId is in queue list but marked isInQueue=false. Auto-fixing...');
               try {
                 await _firestore.collection('users').doc(driverId).update({'isInQueue': true});
               } catch (e) {
                 print('⚠️ Permission denied auto-fixing isInQueue for driver $driverId (User is likely passenger). Ignoring.');
               }
               // Trust the queue list regardless of update success
               isInQueue = true;
            }

            if (isApproved && driverBarangayId != rideBarangayId) {
               print('⚠️ Driver $driverId is in queue for $rideBarangayId but has barangay $driverBarangayId. Assuming valid queue membership.');
               // Don't update barangayId permanently as it might be a valid move, but allow assignment
               // Or better: strict check? No, let's trust the queue list location.
               // We'll just treat them as matching for this assignment.
            }

            // Check eligibility (relaxed barangay check if they are in the correct queue list)
            if (isApproved && isInQueue) {
              // Auto-resolve busy status if driver is in queue
              await _resolveBusyStatusIfInQueue(driverId);

              final isTrulyAvailable = await _isDriverAvailable(driverId);
              print('   Available check result: $isTrulyAvailable');
              
              if (isTrulyAvailable) {
                availableDriverId = driverId;
                print('✅ SELECTED Driver $driverId (Queue Position ${driverQueueData.indexOf(driverData) + 1}) - FIRST AVAILABLE DRIVER');
                break; // Found first available driver in queue
              } else {
                print('❌ Driver $driverId is busy, checking next in queue');
              }
            } else {
              print('❌ Driver $driverId not eligible: approved=$isApproved, inQueue=$isInQueue, barangayMatch=${driverBarangayId == rideBarangayId}');
            }
          } else {
            print('❌ Driver document does not exist: $driverId');
          }
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            print('⚠️ Permission denied accessing driver $driverId profile. Skipping...');
            continue;
          }
          print('❌ Error checking driver $driverId: $e');
        } catch (e) {
          print('❌ Error checking driver $driverId: $e');
        }
      }

      if (availableDriverId == null && queue.isNotEmpty) {
        final fallbackDriverId = queue.first;
        print('⚠️ No fully eligible drivers found, using first in queue as fallback: $fallbackDriverId');
        availableDriverId = fallbackDriverId;
      }

      print('🎯 FINAL RESULT:');
      if (availableDriverId != null) {
        final selectedPosition = queue.indexOf(availableDriverId) + 1;
        print('✅ Selected Driver: $availableDriverId (Queue Position: $selectedPosition)');
        
        // Step 4: Send ride request to the available driver (don't auto-accept)
        print('📝 Assigning ride $rideId to driver $availableDriverId');
        print('📝 Updating Firestore with assignedDriverId and assignedAt (status remains pending)');
        
        await _firestore.collection('rides').doc(rideId).update({
          'assignedDriverId': availableDriverId,
          'assignedAt': Timestamp.now(),
        });
        print('✅ Ride document updated in Firestore');
        
        // Verify the update
        final verifyDoc = await _firestore.collection('rides').doc(rideId).get();
        final verifyData = verifyDoc.data() as Map<String, dynamic>;
        print('🔍 Verification - Ride $rideId:');
        print('   - assignedDriverId: ${verifyData['assignedDriverId']}');
        print('   - status: ${verifyData['status']}');
        print('   - Driver should see this ride now!');

        // Step 5: Get ride details to include passenger information
        final rideDoc = await _firestore.collection('rides').doc(rideId).get();
        final rideData = rideDoc.data() as Map<String, dynamic>;

        // Get passenger details
        final passengerId = rideData['passengerId'];
        final passengerDoc = await _firestore
            .collection('users')
            .doc(passengerId)
            .get();
        final passengerData = passengerDoc.data() as Map<String, dynamic>;

        // Step 6: Create ride request notification for driver
        print('📱 Creating notification for driver $availableDriverId');
        print('   Passenger: ${passengerData['name']}');
        print('   From: ${rideData['pickupAddress']}');
        print('   To: ${rideData['dropoffAddress']}');
        print('   Fare: ₱${rideData['fare']}');
        
        print('📋 Ride request created and assigned to driver $availableDriverId');

        // Real-time updates also handled via Firestore listeners in driver dashboard

        // Don't remove from queue or change status until driver accepts

        print(
          '✅ Ride $rideId assigned to queued online driver $availableDriverId (Position $selectedPosition)',
        );
        return true;
      } else {
        print('❌ NO AVAILABLE DRIVERS FOUND in queue for ride $rideId');
        return false;
      }
    } catch (e) {
      print('❌ FATAL ERROR in ride assignment: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> diagnoseRideAssignment(String rideId) async {
    try {
      print('=== DIAGNOSE RIDE ASSIGNMENT for $rideId ===');
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        print('Ride not found: $rideId');
        return {'exists': false};
      }
      final rideData = rideDoc.data() as Map<String, dynamic>;
      final barangayId = rideData['barangayId'] as String?;
      print('Ride barangayId: $barangayId');
      if (barangayId == null) {
        return {'exists': true, 'barangayId': null};
      }
      final queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();
      final queue = queueDoc.exists
          ? List<String>.from((queueDoc.data() as Map<String, dynamic>?)?['drivers'] ?? [])
          : <String>[];
      print('Queue: $queue');
      final checked = <Map<String, dynamic>>[];
      String? firstEligible;
      String? firstAvailable;
      for (int i = 0; i < queue.length; i += 10) {
        final batchIds = queue.skip(i).take(10).toList();
        final snap = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: batchIds)
            .get();
        final map = {for (var d in snap.docs) d.id: d.data() as Map<String, dynamic>};
        for (final id in batchIds) {
          final d = map[id];
          if (d == null) {
            checked.add({'id': id, 'exists': false});
            continue;
          }
          final isApproved = d['isApproved'] ?? false;
          final isInQueue = d['isInQueue'] ?? false;
          final role = d['role'] ?? 'unknown';
          final driverBarangayId = d['barangayId'] as String?;
          final barangayMatch = driverBarangayId == barangayId;
          final eligible = role == 'driver' && isApproved && isInQueue && barangayMatch;
          bool available = false;
          if (eligible) {
            available = await _isDriverAvailable(id);
          }
          checked.add({
            'id': id,
            'exists': true,
            'approved': isApproved,
            'inQueue': isInQueue,
            'role': role,
            'barangayMatch': barangayMatch,
            'eligible': eligible,
            'available': available,
          });
          if (firstEligible == null && eligible) {
            firstEligible = id;
          }
          if (firstAvailable == null && eligible && available) {
            firstAvailable = id;
          }
        }
      }
      print('First eligible: $firstEligible');
      print('First available: $firstAvailable');
      return {
        'exists': true,
        'barangayId': barangayId,
        'queue': queue,
        'firstEligible': firstEligible,
        'firstAvailable': firstAvailable,
        'checked': checked,
      };
    } catch (e) {
      print('Error diagnosing ride assignment: $e');
      return {'error': e.toString()};
    }
  }

  // Driver accepts a ride request
  Future<void> acceptRideRequest(String rideId, String driverId) async {
    print('📤 Driver accepting ride $rideId via acceptRideRequest at ${DateTime.now()}');
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
        print('🔥 Firestore transaction updated ride $rideId to accepted status');
      });

      // Update driver status to busy
      await _firestore.collection('users').doc(driverId).update({
        'status': 'busy',
        'currentRide': rideId,
        'currentPasaBuy': null, // Clear any potential PasaBuy
        'lastAssigned': Timestamp.now(),
      });

      // Remove driver from queue (they're now busy)
      await removeDriverFromQueue(driverId);

      // STEP 6: Reassign any pending requests (Rides and PasaBuy) from this driver
      await _reassignPendingRideRequestsFromDriver(driverId);
      await _reassignPendingPasaBuyRequestsFromDriver(driverId);

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

  /// Reassign any pending PasaBuy requests from a busy driver to the next available driver
  Future<void> _reassignPendingPasaBuyRequestsFromDriver(String busyDriverId) async {
    try {
      print('🔄 === REASSIGNING PASABUY REQUESTS FROM BUSY DRIVER ===');
      print('   Busy Driver ID: $busyDriverId');
      
      // Find all pending PasaBuy requests assigned to this driver
      final pendingPasaBuySnapshot = await _firestore
          .collection('pasabuy_requests')
          .where('assignedDriverId', isEqualTo: busyDriverId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (pendingPasaBuySnapshot.docs.isEmpty) {
        print('✅ No pending PasaBuy requests to reassign');
        return;
      }

      print('📋 Found ${pendingPasaBuySnapshot.docs.length} pending PasaBuy requests to reassign');

      // Get the busy driver's barangay for queue access
      final driverDoc = await _firestore.collection('users').doc(busyDriverId).get();
      if (!driverDoc.exists) {
        print('❌ Busy driver not found');
        return;
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      final barangayId = driverData['barangayId'] as String?;

      if (barangayId == null) {
        print('❌ Driver has no barangay assigned');
        return;
      }

      // Get the driver queue for this barangay
      final queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();

      if (!queueDoc.exists) {
        print('❌ Queue not found for barangay: $barangayId');
        return;
      }

      final queueData = queueDoc.data() as Map<String, dynamic>;
      final driverQueue = List<String>.from(queueData['drivers'] as List? ?? []);
      
      print('🚗 Driver queue for $barangayId: $driverQueue');

      // Reassign each pending PasaBuy request
      for (final pasabuyDoc in pendingPasaBuySnapshot.docs) {
        final pasabuyData = pasabuyDoc.data() as Map<String, dynamic>;
        final pasabuyId = pasabuyDoc.id;
        final passengerId = pasabuyData['passengerId'] as String?;
        
        // Get list of drivers who already declined this request
        final declinedBy = List<String>.from(pasabuyData['declinedBy'] as List? ?? []);
        
        // Find next available driver (not busy, not declined)
        String? nextDriverId;
        for (final driverId in driverQueue) {
          if (driverId != busyDriverId && !declinedBy.contains(driverId)) {
            try {
              // Check if this driver is available (not busy with another ride/PasaBuy)
              // AND still has isInQueue=true (verified from user data)
              final isAvailable = await _isDriverAvailable(driverId);
              if (isAvailable) {
                // Double check driver eligibility and order
                final dDoc = await _firestore.collection('users').doc(driverId).get();
                if (dDoc.exists) {
                  final dData = dDoc.data() as Map<String, dynamic>;
                  if ((dData['isApproved'] ?? false) && (dData['isInQueue'] ?? false)) {
                    nextDriverId = driverId;
                    break;
                  }
                }
              }
            } on FirebaseException catch (e) {
              if (e.code == 'permission-denied') {
                print('⚠️ Permission denied accessing driver $driverId profile during reassignment. Skipping...');
                continue;
              }
              print('Error checking driver $driverId for reassignment: $e');
            } catch (e) {
              print('Error checking driver $driverId for reassignment: $e');
            }
          }
        }

        if (nextDriverId != null) {
          // Assign to next available driver
          await _firestore.collection('pasabuy_requests').doc(pasabuyId).update({
            'assignedDriverId': nextDriverId,
            'declinedBy': FieldValue.arrayUnion([busyDriverId]), // Mark busy driver as declined
          });

          print('✅ PasaBuy $pasabuyId reassigned: $busyDriverId → $nextDriverId');

          // Notify passenger about reassignment
          if (passengerId != null) {
            await _createPasaBuyReassignedNotification(
              pasabuyId,
              passengerId,
              nextDriverId,
            );
          }
          
        } else {
          // No available drivers found - keep as pending but notify passenger
          print('⚠️ No available drivers for PasaBuy $pasabuyId');
          
          if (passengerId != null) {
            await _createPasaBuyNoDriversAvailableNotification(
              pasabuyId,
              passengerId,
              pasabuyData,
            );
          }
        }
      }

      print('✅ PasaBuy reassignment completed for driver $busyDriverId');
    } catch (e) {
      print('❌ Error reassigning PasaBuy requests: $e');
    }
  }

  /// Public wrapper for availability check
  Future<bool> checkDriverAvailability(String driverId) async {
    return _isDriverAvailable(driverId);
  }

  /// Check if a driver is available (not busy with ride or PasaBuy)
  Future<bool> _isDriverAvailable(String driverId) async {
    try {
      // Check for active rides
      final activeRides = await _firestore
          .collection('rides')
          .where('assignedDriverId', isEqualTo: driverId)
          .where('status', whereIn: ['accepted', 'inProgress', 'driverOnWay', 'driverArrived'])
          .get();

      if (activeRides.docs.isNotEmpty) {
        final ride = activeRides.docs.first;
        final rideData = ride.data();
        final status = rideData['status'];
        final timestamp = rideData['acceptedAt'] as Timestamp? ?? rideData['createdAt'] as Timestamp?;
        
        print('⚠️ Driver $driverId has active ride ${ride.id} ($status)');

        // AUTO-FIX: If ride is stale (> 2 hours), cancel it and allow new assignment
        if (timestamp != null) {
          final diff = DateTime.now().difference(timestamp.toDate());
          if (diff.inHours >= 2) {
             print('🧹 Auto-clearing STALE ride ${ride.id} (${diff.inHours} hours old)');
             await _firestore.collection('rides').doc(ride.id).update({
               'status': 'cancelled',
               'cancelledBy': 'system_cleanup',
               'cancelReason': 'Stale ride auto-cleanup',
               'cancelledAt': Timestamp.now(),
             });
             // Reset driver status
             await _firestore.collection('users').doc(driverId).update({
                'status': 'available',
                'currentRide': null,
             });
             print('✅ Driver $driverId status reset to available');
             // Proceed to check PasaBuy
          } else {
             return false; // Driver genuinely busy
          }
        } else {
           return false; // Driver busy (no timestamp)
        }
      }

      // Check for active PasaBuy requests
      final activePasaBuys = await _firestore
          .collection('pasabuy_requests')
          .where('assignedDriverId', isEqualTo: driverId)
          .where('status', whereIn: [
            'accepted', 
            'driver_on_way', 
            'arrived_pickup', 
            'delivery_in_progress'
          ])
          .get();

      if (activePasaBuys.docs.isNotEmpty) {
        final pasabuy = activePasaBuys.docs.first;
        final pData = pasabuy.data();
        final status = pData['status'];
        final timestamp = pData['acceptedAt'] as Timestamp? ?? pData['createdAt'] as Timestamp?;

        print('⚠️ Driver $driverId has active PasaBuy ${pasabuy.id} ($status)');
        
        if (timestamp != null) {
           final diff = DateTime.now().difference(timestamp.toDate());
           if (diff.inHours >= 2) {
              print('🧹 Auto-clearing STALE PasaBuy ${pasabuy.id}');
              await _firestore.collection('pasabuy_requests').doc(pasabuy.id).update({
                'status': 'cancelled',
                'cancelledBy': 'system_cleanup',
                'cancelReason': 'Stale pasabuy auto-cleanup',
                'cancelledAt': Timestamp.now(),
              });
              await _firestore.collection('users').doc(driverId).update({
                'status': 'available',
                'currentPasaBuy': null,
              });
              print('✅ Driver $driverId status reset to available (from PasaBuy)');
           } else {
              return false; // Driver genuinely busy
           }
        } else {
           return false; // Driver busy
        }
      }

      return true; // Driver is available
    } catch (e) {
      print('Error checking driver availability: $e');
      return false;
    }
  }

  /// Create notification for passenger when PasaBuy is reassigned to another driver
  Future<void> _createPasaBuyReassignedNotification(
    String requestId,
    String passengerId,
    String newDriverId,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'type': 'pasabuy_reassigned',
        'userId': passengerId,
        'requestId': requestId,
        'newDriverId': newDriverId,
        'title': 'Driver Assigned to Another Request',
        'body': 'Your previous driver was assigned to another request. We\'ve found you a new driver! Please wait for their acceptance.',
        'createdAt': Timestamp.now(),
        'read': false,
        'action': 'wait_for_driver',
      });
    } catch (e) {
      print('Error creating PasaBuy reassigned notification: $e');
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
        'canBeCancelled': true, // Allow passenger to cancel again
      });
      print('✅ Ride unassigned from driver $driverId');

      // STEP 2: Remove driver from queue (instead of moving to end)
      print('🔄 Removing driver from queue due to decline...');
      await removeDriverFromQueue(driverId);
      print('✅ Driver removed from queue');

      // STEP 3: Track that this driver declined this ride
      await _firestore.collection('users').doc(driverId).update({
        'lastDeclinedAt': Timestamp.now(),
        'declineCount': FieldValue.increment(1),
      });

      // STEP 4: Auto-reassign to next driver immediately
      print('🔄 Auto-reassigning ride $rideId to next driver...');
      final reassignSuccess = await _assignRideToAvailableDriver(rideId);
      
      final passengerId = rideData['passengerId'];
      if (passengerId != null && !reassignSuccess) {
        // Only notify passenger if reassignment failed (no drivers available)
        await _createPassengerDeclineNotification(
          rideId,
          passengerId,
          driverId,
          rideData,
        );
        print('⚠️ No drivers available for reassignment. Notified passenger.');
      } else {
        print('✅ Ride successfully reassigned to next driver.');
      }

      // NOTE: Ride stays in 'pending' status with no assigned driver
      // Passenger will see option to "Find Another Driver" or "Cancel Ride"
      // Next driver in queue remains #1 but NOT assigned yet
      
      print(
        '✅ Ride $rideId declined by driver $driverId. Driver removed from queue.',
      );
    } catch (e) {
      print('Error declining ride request: $e');
      rethrow;
    }
  }

  /// Passenger chooses to find another driver after previous driver declined
  Future<bool> requestAnotherDriver(String rideId) async {
    try {
      print('🔍 Passenger requesting another driver for ride $rideId');
      
      // Verify ride exists and is still pending
      final rideDoc = await _firestore.collection('rides').doc(rideId).get();
      if (!rideDoc.exists) {
        throw Exception('Ride not found');
      }
      
      final rideData = rideDoc.data() as Map<String, dynamic>;
      final status = rideData['status'];
      
      if (status != 'pending') {
        throw Exception('Ride is no longer pending (current status: $status)');
      }
      
      // Try to assign to next available driver in queue
      print('🔄 Looking for next available driver...');
      await diagnoseRideAssignment(rideId);
      final reassigned = await _assignRideToAvailableDriver(rideId);
      
      if (reassigned) {
        print('✅ Successfully assigned ride $rideId to next driver');
        
        // Notify passenger that we found another driver
        final passengerId = rideData['passengerId'];
        if (passengerId != null) {
          await _createFoundAnotherDriverNotification(rideId, passengerId);
        }
        return true;
      } else {
        print('❌ No more drivers available for ride $rideId');
        
        // Mark ride as failed - no drivers available
        try {
          await _firestore.collection('rides').doc(rideId).update({
            'status': 'failed',
            'failedReason': 'No available drivers',
            'failedAt': Timestamp.now(),
          });
        } catch (e) {
          print('⚠️ Could not update ride status to failed (likely permission): $e');
        }
        
        // Notify passenger
        final passengerId = rideData['passengerId'];
        if (passengerId != null) {
          await _createNoDriversAvailableNotification(rideId, passengerId, rideData);
        }
        return false;
      }
    } catch (e) {
      print('Error requesting another driver: $e');
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
      print('📝 Creating decline notification for passenger');
      print('   Passenger ID: $passengerId');
      print('   Ride ID: $rideId');
      print('   Driver ID: $driverId');
      
      final notificationData = {
        'type': 'ride_declined',
        'userId': passengerId,
        'rideId': rideId,
        'driverId': driverId,
        'title': 'Driver Declined Your Request',
        'body':
            'The assigned driver declined your ride request from ${rideData['pickupAddress'] ?? 'pickup location'} to ${rideData['dropoffAddress'] ?? 'destination'}. Would you like to find another driver?',
        'createdAt': Timestamp.now(),
        'read': false,
        'action': 'find_another_driver',
        'pickupAddress': rideData['pickupAddress'] ?? '',
        'dropoffAddress': rideData['dropoffAddress'] ?? '',
      };
      
      print('   Notification data: $notificationData');
      print('   Attempting to write to Firestore...');
      
      final docRef = await _firestore.collection('notifications').add(notificationData);
      
      print('✅ Decline notification created with ID: ${docRef.id}');
      print('   Document successfully written to Firestore');
    } catch (e, stackTrace) {
      print('❌ Error creating passenger decline notification: $e');
      print('   Stack trace: $stackTrace');
      print('   Error type: ${e.runtimeType}');
      rethrow; // Re-throw so the caller knows it failed
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
    // QUEUE SYSTEM: Only show rides specifically assigned to this driver
    print('📡 [getDriverNotifications] Setting up stream for driver: $driverId');
    return _firestore
        .collection('rides')
        .where('assignedDriverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .asyncMap((snapshot) async {
          final rideRequests = <Map<String, dynamic>>[];
          
          print('🔍 [getDriverNotifications] Processing ${snapshot.docs.length} ride(s) assigned to driver $driverId');
          
          if (snapshot.docs.isEmpty) {
            print('   ℹ️ No rides found with assignedDriverId=$driverId and status=pending');
          }
          
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final passengerId = data['passengerId'] as String?;
            
            print('  🚗 Assigned ride ${doc.id}: ${data['pickupAddress']} → ${data['dropoffAddress']}');
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

            Timestamp? expiresAt = data['expiresAt'] as Timestamp?;
            if (expiresAt == null) {
              final assignedAt = data['assignedAt'] as Timestamp?;
              final createdAt = data['createdAt'] as Timestamp?;
              final base = assignedAt?.toDate() ?? createdAt?.toDate() ?? DateTime.now();
              expiresAt = Timestamp.fromDate(base.add(const Duration(minutes: 3)));
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
              'assignedToMe': true, // Always true since we only fetch rides assigned to this driver
              'passengerCount': data['passengerCount'] ?? 1,
              'expiresAt': expiresAt,
            });
          }
          
          print('📋 Returning ${rideRequests.length} assigned ride requests');
          
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
      // 1. Status is still 'pending' or 'failed'
      // 2. canBeCancelled flag is true (unless pending/failed, which should always be cancellable)
      if (status == 'pending' || status == 'failed') {
        return true;
      }
      return canBeCancelled;
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

  /// SECURITY: Validate PasaBuy status transitions
  bool _isValidPasaBuyStatusTransition(String? currentStatus, String newStatus) {
    // Allow any transition from null/pending to any status (initial creation)
    if (currentStatus == null || currentStatus == 'pending' || currentStatus == 'assigned') {
      return true;
    }

    // Define valid transitions
    final validTransitions = {
      'accepted': ['driver_on_way', 'cancelled'],
      'driver_on_way': ['arrived_pickup', 'cancelled'],
      'arrived_pickup': ['delivery_in_progress', 'cancelled'],
      'delivery_in_progress': ['completed', 'cancelled'],
      'completed': [], // Terminal state
      'cancelled': [], // Terminal state
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

  // Helper to normalize ride status strings to camelCase
  String _normalizeRideStatus(String? status) {
    if (status == null) return 'pending';
    switch (status) {
      case 'driver_on_way':
      case 'on_the_way':
      case 'onTheWay':
        return 'driverOnWay';
      case 'driver_arrived':
      case 'arrived_pickup':
      case 'arrived':
        return 'driverArrived';
      case 'in_progress':
      case 'started':
      case 'onTrip':
        return 'inProgress';
      case 'canceled':
        return 'cancelled';
      default:
        return status;
    }
  }

  // Helper to normalize PasaBuy status strings
  String _normalizePasaBuyStatus(String? status) {
    if (status == null) return 'pending';
    switch (status) {
      case 'driverOnWay':
      case 'on_the_way':
      case 'onTheWay':
        return 'driver_on_way';
      case 'arrivedPickup':
      case 'driverArrived':
      case 'driver_arrived':
      case 'arrived':
        return 'arrived_pickup';
      case 'deliveryInProgress':
      case 'in_progress':
      case 'inProgress':
      case 'started':
        return 'delivery_in_progress';
      case 'canceled':
        return 'cancelled';
      default:
        return status;
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
      final currentStatus = _normalizeRideStatus(currentData['status']);
      if (!_isValidStatusTransition(
        currentStatus,
        status.toString().split('.').last,
      )) {
        throw Exception(
          'Invalid status transition from $currentStatus to ${status.toString().split('.').last}',
        );
      }

      // SECURITY: Respect canBeCancelled flag for passenger cancellations
      final canBeCancelled = currentData['canBeCancelled'] as bool? ?? true;
      if (status == RideStatus.cancelled && driverId == null && !canBeCancelled) {
        throw Exception('This ride can no longer be cancelled.');
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

      print('🔥 Firestore updated ride $rideId to status $status at ${DateTime.now()}');

      // Handle driver status updates when ride is completed or cancelled
      if (status == RideStatus.completed || status == RideStatus.cancelled) {
        final driverIdToUpdate = driverId ?? currentDriverId;
        if (driverIdToUpdate != null) {
          try {
            await _firestore.collection('users').doc(driverIdToUpdate).update({
              'status': 'available',
              'currentRide': null,
              'currentPasaBuy': null, // Also ensure PasaBuy is cleared
            }).timeout(const Duration(seconds: 3));
            print('Driver $driverIdToUpdate status updated to available');
          } catch (e) {
            print('Warning: Failed to update driver status: $e');
            // Don't rethrow - ride status update was successful
          }
        }
      }

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
    // Get rides and sort client-side to avoid needing composite index
    return _firestore
        .collection('rides')
        .where(field, isEqualTo: userId)
        .limit(50) // PERFORMANCE: Limit to recent 50 rides to improve load time
        .snapshots()
        .map((snapshot) {
          final rides = snapshot.docs
              .map((doc) => RideModel.fromFirestore(doc))
              .toList();
          // Sort by requestedAt client-side (newest first)
          rides.sort((a, b) => (b.requestedAt ?? DateTime.now()).compareTo(a.requestedAt ?? DateTime.now()));
          return rides;
        });
  }

  Stream<RideModel?> getRideStream(String rideId) {
    print('🔍 getRideStream called for rideId: $rideId');
    return _firestore.collection('rides').doc(rideId).snapshots().map((doc) {
      print('🔍 getRideStream received snapshot for rideId: $rideId, exists: ${doc.exists}');
      if (doc.exists) {
        final ride = RideModel.fromFirestore(doc);
        print('🔍 getRideStream parsed ride status: ${ride.status}');
        return ride;
      }
      print('🔍 getRideStream: document does not exist');
      return null;
    });
  }

  // Queue operations - PER BARANGAY
  Future<void> addDriverToQueue(String driverId) async {
    try {
      // Get driver's barangay
      final driverDoc = await _firestore
          .collection('users')
          .doc(driverId)
          .get();
      
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }
      
      final driverData = driverDoc.data() as Map<String, dynamic>;
      
      // VALIDATION: Check if driver is approved
      final isApproved = driverData['isApproved'] ?? false;
      final role = driverData['role'] ?? '';
      final isAlreadyInQueue = driverData['isInQueue'] ?? false;
      
      if (role != 'driver') {
        throw Exception('Only drivers can join the queue');
      }
      
      if (!isApproved) {
        throw Exception('Your driver account is pending approval. Please wait for admin approval before joining the queue.');
      }
      
      final barangayId = driverData['barangayId'] as String?;
      
      if (barangayId == null || barangayId.isEmpty) {
        throw Exception('Driver has no barangay assigned');
      }
      
      print('🏘️ Adding driver $driverId to queue for barangay: $barangayId');

      // FAST PATH: If driver is already marked in queue, avoid extra queue writes
      if (isAlreadyInQueue) {
        print('ℹ️ Driver $driverId is already in queue, skipping re-add.');
        return;
      }

      // Proceed to add driver to queue atomically
      {
        bool hasRecentDecline = false;

        // Check if driver has recently declined a ride (within last hour)
        final lastDeclinedAt = driverData['lastDeclinedAt'] as Timestamp?;

        if (lastDeclinedAt != null) {
          final declineTime = lastDeclinedAt.toDate();
          final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
          hasRecentDecline = declineTime.isAfter(hourAgo);
        }

        // ATOMIC UPDATE: Use arrayUnion to prevent race conditions
        // This ensures the driver is added atomically without overwriting other drivers
        final batch = _firestore.batch();
        
        // Update barangay queue document using arrayUnion (atomic, prevents race conditions)
        // Use set with merge if document doesn't exist, update if it does
        final queueRef = _firestore
            .collection('system')
            .doc('queues')
            .collection('barangays')
            .doc(barangayId);
        
        // Use set with merge to avoid needing an upfront read of the queue document
        batch.set(queueRef, {
          'drivers': FieldValue.arrayUnion([driverId]),
          'barangayId': barangayId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Update driver queue status in users collection
        batch.update(_firestore.collection('users').doc(driverId), {
          'isInQueue': true,
          // Position is now derived from queueJoinedAt + server-side logic.
          // We no longer depend on the current queue length here to avoid an
          // extra read and possible race conditions.
          'queuePosition': 0,
          'status': 'available', // Set status to available when joining queue
          'queueJoinedAt': Timestamp.now(),
          'penaltyApplied': hasRecentDecline,
        });

        await batch.commit();

        if (hasRecentDecline) {
          print(
            '✅ Driver $driverId added to $barangayId queue with penalty (recent decline)',
          );
        } else {
          print('✅ Driver $driverId added to $barangayId queue');
        }
      }
    } catch (e) {
      print('❌ Error adding driver to queue: $e');
      rethrow;
    }
  }

  Future<void> removeDriverFromQueue(String driverId) async {
    try {
      print('🔄 [removeDriverFromQueue] Starting checkout for driver: $driverId');
      
      // Get driver's barangay
      final driverDoc = await _firestore
          .collection('users')
          .doc(driverId)
          .get();
      
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }
      
      final driverData = driverDoc.data() as Map<String, dynamic>;
      final barangayId = driverData['barangayId'] as String?;
      
      if (barangayId == null || barangayId.isEmpty) {
        throw Exception('Driver has no barangay assigned');
      }
      
      print('   Removing from barangay queue: $barangayId');
      
      // Use atomic arrayRemove to avoid reading and rewriting full queue
      await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .set({
            'drivers': FieldValue.arrayRemove([driverId]),
            'barangayId': barangayId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Update removed driver's queue status
      print('   Updating driver $driverId: isInQueue=false, queuePosition=0');
      await _firestore.collection('users').doc(driverId).update({
        'isInQueue': false,
        'queuePosition': 0,
      });

      print('✅ [removeDriverFromQueue] Successfully checked out driver $driverId from $barangayId');
    } catch (e) {
      print('❌ [removeDriverFromQueue] Error removing driver from queue: $e');
      rethrow;
    }
  }

  /// Cleanup invalid drivers from barangay queue (deleted or deactivated drivers)
  Future<void> _cleanupInvalidDriversFromQueueForBarangay(
    String barangayId,
    List<String> invalidDriverIds,
  ) async {
    try {
      print('🧹 [cleanupInvalidDriversFromQueueForBarangay] Removing ${invalidDriverIds.length} invalid drivers from $barangayId');
      
      final queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();
      
      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        List<String> queue = List<String>.from(data?['drivers'] ?? []);
        
        // Remove all invalid driver IDs
        final originalLength = queue.length;
        queue.removeWhere((driverId) => invalidDriverIds.contains(driverId));
        
        print('🧹 $barangayId queue cleaned: $originalLength → ${queue.length} drivers');
        
        // Update queue with cleaned list
        await _firestore
            .collection('system')
            .doc('queues')
            .collection('barangays')
            .doc(barangayId)
            .set({
              'drivers': queue,
              'barangayId': barangayId,
              'lastCleanup': Timestamp.now(),
            });
        
        print('✅ [cleanupInvalidDriversFromQueueForBarangay] Queue cleanup complete for $barangayId');
      }
    } catch (e) {
      print('❌ [cleanupInvalidDriversFromQueueForBarangay] Error cleaning up queue: $e');
      // Don't rethrow - this is a background cleanup operation
    }
  }

  /// Cleanup invalid drivers from queue (deleted or deactivated drivers)
  Future<void> _cleanupInvalidDriversFromQueue(List<String> invalidDriverIds) async {
    try {
      print('🧹 [cleanupInvalidDriversFromQueue] Removing ${invalidDriverIds.length} invalid drivers');
      
      final queueDoc = await _firestore.collection('system').doc('queue').get();
      
      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        List<String> queue = List<String>.from(data?['drivers'] ?? []);
        
        // Remove all invalid driver IDs
        final originalLength = queue.length;
        queue.removeWhere((driverId) => invalidDriverIds.contains(driverId));
        
        print('🧹 Queue cleaned: $originalLength → ${queue.length} drivers');
        
        // Update queue with cleaned list
        await _firestore.collection('system').doc('queue').set({
          'drivers': queue,
          'lastCleanup': Timestamp.now(),
        });
        
        print('✅ [cleanupInvalidDriversFromQueue] Queue cleanup complete');
      }
    } catch (e) {
      print('❌ [cleanupInvalidDriversFromQueue] Error cleaning up queue: $e');
      // Don't rethrow - this is a background cleanup operation
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

  /// Move driver to end of queue (used when driver declines a ride) - PER BARANGAY
  Future<void> _moveDriverToEndOfQueue(String driverId) async {
    try {
      print('🔄 Moving driver $driverId to end of queue...');
      
      // Get driver's barangay
      final driverDoc = await _firestore.collection('users').doc(driverId).get();
      if (!driverDoc.exists) {
        print('⚠️ Driver not found');
        return;
      }
      
      final driverData = driverDoc.data() as Map<String, dynamic>;
      final barangayId = driverData['barangayId'] as String?;
      
      if (barangayId == null || barangayId.isEmpty) {
        print('⚠️ Driver has no barangay assigned');
        return;
      }
      
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();

      if (!queueDoc.exists) {
        print('⚠️ Queue document does not exist for barangay $barangayId');
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

      print('📋 New queue order for $barangayId: $queue');

      // Update queue document
      await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .set({
        'drivers': queue,
        'barangayId': barangayId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Driver $driverId moved to position ${queue.length} (end of $barangayId queue)');
    } catch (e) {
      print('❌ Error moving driver to end of queue: $e');
      rethrow;
    }
  }


  /// Get queue stream for a specific barangay (PER-BARANGAY QUEUE)
  Stream<List<String>> getQueueStreamForBarangay(String barangayId) {
    // Validate barangayId
    if (barangayId.trim().isEmpty) {
      print('❌ [getQueueStreamForBarangay] Invalid barangayId: cannot be empty');
      return Stream.value([]);
    }
    
    return _firestore
        .collection('system')
        .doc('queues')
        .collection('barangays')
        .doc(barangayId)
        .snapshots()
        .asyncMap((doc) async {
      if (doc.exists) {
        final data = doc.data();
        final allDriverIds = List<String>.from(data?['drivers'] ?? []);
        
        if (kDebugMode) {
          print('📊 [getQueueStreamForBarangay] Barangay: $barangayId, Queue: $allDriverIds');
        }
        
        // Return the queue as-is without validation
        // Validation and cleanup should only happen during consolidation, not on every read
        // This prevents race conditions where drivers are temporarily removed during validation
        return allDriverIds;
      }
      if (kDebugMode) {
        print('📊 [getQueueStreamForBarangay] Barangay: $barangayId, Queue document does not exist');
      }
      return <String>[];
    });
  }

  /// Get queue for a specific barangay (one-time fetch)
  Future<List<String>> getQueueForBarangay(String barangayId) async {
    try {
      // Validate barangayId
      if (barangayId.trim().isEmpty) {
        print('❌ [getQueueForBarangay] Invalid barangayId: cannot be empty');
        return [];
      }
      
      DocumentSnapshot queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();

      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        final queue = List<String>.from(data?['drivers'] ?? []);
        
        if (kDebugMode) {
          print('📊 [getQueueForBarangay] Barangay: $barangayId, Queue: $queue');
        }
        
        return queue;
      }
      
      if (kDebugMode) {
        print('📊 [getQueueForBarangay] Barangay: $barangayId, Queue document does not exist');
      }
      return [];
    } catch (e) {
      print('❌ [getQueueForBarangay] Error getting queue for barangay $barangayId: $e');
      return [];
    }
  }

  /// Legacy global queue stream (kept for backward compatibility, but should use per-barangay)
  @Deprecated('Use getQueueStreamForBarangay instead')
  Stream<List<String>> getQueueStream() {
    return _firestore.collection('system').doc('queue').snapshots().asyncMap((doc) async {
      if (doc.exists) {
        final data = doc.data();
        final allDriverIds = List<String>.from(data?['drivers'] ?? []);
        
        // Validate that drivers still exist and are approved
        final validDriverIds = <String>[];
        final invalidDriverIds = <String>[];
        
        for (final driverId in allDriverIds) {
          try {
            final driverDoc = await _firestore.collection('users').doc(driverId).get();
            if (driverDoc.exists) {
              final driverData = driverDoc.data() as Map<String, dynamic>?;
              final isApproved = driverData?['isApproved'] ?? false;
              final role = driverData?['role'] ?? '';
              
              // Only include approved drivers with driver role
              if (isApproved && role == 'driver') {
                validDriverIds.add(driverId);
              } else {
                invalidDriverIds.add(driverId);
                print('⚠️ Driver $driverId is not approved or not a driver, will be removed from queue');
              }
            } else {
              invalidDriverIds.add(driverId);
              print('⚠️ Driver $driverId does not exist, will be removed from queue');
            }
          } catch (e) {
            print('Error validating driver $driverId: $e');
            invalidDriverIds.add(driverId);
          }
        }
        
        // If there are invalid drivers, clean up the queue
        if (invalidDriverIds.isNotEmpty) {
          print('🧹 Cleaning up ${invalidDriverIds.length} invalid drivers from queue');
          _cleanupInvalidDriversFromQueue(invalidDriverIds);
        }
        
        return validDriverIds;
      }
      return <String>[];
    });
  }

  /// Get driver's real-time queue position from the per-barangay queue
  Future<int> getDriverQueuePosition(String driverId, {String? barangayId}) async {
    try {
      // If barangayId not provided, fetch driver's barangay first
      String? driverBarangayId = barangayId;
      
      if (driverBarangayId == null) {
        final driverDoc = await _firestore.collection('users').doc(driverId).get();
        if (driverDoc.exists) {
          final driverData = driverDoc.data() as Map<String, dynamic>?;
          driverBarangayId = driverData?['barangayId'] as String?;
        }
      }
      
      if (driverBarangayId == null || driverBarangayId.isEmpty) {
        return 0;
      }
      
      final queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(driverBarangayId)
          .get();
          
      if (queueDoc.exists) {
        final data = queueDoc.data();
        final queue = List<String>.from(data?['drivers'] ?? []);
        final position = queue.indexOf(driverId);
        return position >= 0 ? position + 1 : 0; // 1-indexed, 0 if not in queue
      }
      return 0;
    } catch (e) {
      print('Error getting driver queue position: $e');
      return 0;
    }
  }

  /// Stream driver's real-time queue position (per-barangay)
  Stream<int> getDriverQueuePositionStream(String driverId, {String? barangayId}) async* {
    // If barangayId not provided, fetch driver's barangay first
    String? driverBarangayId = barangayId;
    
    if (driverBarangayId == null) {
      final driverDoc = await _firestore.collection('users').doc(driverId).get();
      if (driverDoc.exists) {
        final driverData = driverDoc.data() as Map<String, dynamic>?;
        driverBarangayId = driverData?['barangayId'] as String?;
      }
    }
    
    if (driverBarangayId == null || driverBarangayId.isEmpty) {
      if (kDebugMode) {
        print('⚠️ [getDriverQueuePositionStream] Driver $driverId has no barangayId');
      }
      yield 0;
      return;
    }
    
    // Stream the per-barangay queue
    await for (final doc in _firestore
        .collection('system')
        .doc('queues')
        .collection('barangays')
        .doc(driverBarangayId)
        .snapshots()) {
      if (doc.exists) {
        final data = doc.data();
        final queue = List<String>.from(data?['drivers'] ?? []);
        final position = queue.indexOf(driverId);
        
        if (kDebugMode) {
          print('📍 [getDriverQueuePositionStream] Driver: $driverId, Barangay: $driverBarangayId, Queue: $queue, Position: ${position >= 0 ? position + 1 : 0}');
        }
        
        yield position >= 0 ? position + 1 : 0; // 1-indexed, 0 if not in queue
      } else {
        if (kDebugMode) {
          print('⚠️ [getDriverQueuePositionStream] Queue document does not exist for barangay: $driverBarangayId');
        }
        yield 0;
      }
    }
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
      final adminRole = adminData['role'];
      if (adminRole != 'admin') {
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
        'isActive': true,
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
      final adminRole = adminData['role'];
      if (adminRole != 'admin') {
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

      final driverData = driverDoc.data() as Map<String, dynamic>;

      // Update in users collection where driver profile is loaded from
      await _firestore.collection('users').doc(driverId).update({
        'isApproved': false,
      });

      // Remove from queue if in queue
      await removeDriverFromQueue(driverId);
      
      print('✅ Driver deactivated successfully');
    } catch (e) {
      print('Error deactivating driver: $e');
      rethrow;
    }
  }

  /// Reactivate a deactivated driver (barangay admin only)
  Future<void> reactivateDriver(String driverId, String adminId) async {
    try {
      // SECURITY: Verify the user performing this action is an admin
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin user not found');
      }

      final adminData = adminDoc.data() as Map<String, dynamic>;
      final adminRole = adminData['role'];
      if (adminRole != 'admin') {
        throw Exception('Unauthorized: Only admins can reactivate drivers');
      }

      // SECURITY: Verify driver exists
      final driverDoc = await _firestore
          .collection('users')
          .doc(driverId)
          .get();
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;

      // Reactivate the driver (set isApproved back to true)
      await _firestore.collection('users').doc(driverId).update({
        'isApproved': true,
      });
      
      print('✅ Driver reactivated successfully');
    } catch (e) {
      print('Error reactivating driver: $e');
      rethrow;
    }
  }

  /// Reject a pending driver application
  Future<void> rejectDriver(String driverId, String adminId) async {
    try {
      // SECURITY: Verify the user performing this action is an admin
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin user not found');
      }

      final adminData = adminDoc.data() as Map<String, dynamic>;
      final adminRole = adminData['role'];
      if (adminRole != 'admin') {
        throw Exception('Unauthorized: Only admins can reject drivers');
      }

      // SECURITY: Verify driver exists
      final driverDoc = await _firestore
          .collection('users')
          .doc(driverId)
          .get();
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;

      // Reject the driver (set isApproved to false, keep approvedAt as null, set rejectedAt)
      await _firestore.collection('users').doc(driverId).update({
        'isApproved': false,
        'approvedAt': null,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': adminId,
      });

      // Remove from queue if in queue
      await removeDriverFromQueue(driverId);
      
      print('✅ Driver rejected successfully');
    } catch (e) {
      print('Error rejecting driver: $e');
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

  /// Get drivers filtered by barangay (for barangay admins)
  Stream<List<DriverModel>> getDriversByBarangay(String barangayId) {
    print('🔍 [getDriversByBarangay] Querying drivers for barangayId: $barangayId');
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .where('barangayId', isEqualTo: barangayId)
        .snapshots()
        .map(
          (snapshot) {
            print('📊 [getDriversByBarangay] Found ${snapshot.docs.length} drivers for barangayId: $barangayId');
            for (var doc in snapshot.docs) {
              print('  - Driver: ${doc['name']} (barangayId: ${doc['barangayId']})');
            }
            return snapshot.docs
                .map((doc) => DriverModel.fromFirestore(doc))
                .toList();
          },
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

  /// Get active rides filtered by barangay (for barangay admins)
  Stream<List<RideModel>> getActiveRidesByBarangay(String barangayId) {
    return _firestore
        .collection('rides')
        .where('barangayId', isEqualTo: barangayId)
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

  /// Manually cleanup queue to remove all invalid drivers (admin function)
  Future<void> cleanupDriverQueue() async {
    try {
      print('🧹 Manual queue cleanup initiated');
      
      final queueDoc = await _firestore.collection('system').doc('queue').get();
      
      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        final allDriverIds = List<String>.from(data?['drivers'] ?? []);
        
        print('📋 Checking ${allDriverIds.length} drivers in queue');
        
        final validDriverIds = <String>[];
        final invalidDriverIds = <String>[];
        
        for (final driverId in allDriverIds) {
          try {
            final driverDoc = await _firestore.collection('users').doc(driverId).get();
            if (driverDoc.exists) {
              final driverData = driverDoc.data() as Map<String, dynamic>?;
              final isApproved = driverData?['isApproved'] ?? false;
              final role = driverData?['role'] ?? '';
              
              if (isApproved && role == 'driver') {
                validDriverIds.add(driverId);
              } else {
                invalidDriverIds.add(driverId);
              }
            } else {
              invalidDriverIds.add(driverId);
            }
          } catch (e) {
            print('Error validating driver $driverId: $e');
            invalidDriverIds.add(driverId);
          }
        }
        
        if (invalidDriverIds.isNotEmpty) {
          await _cleanupInvalidDriversFromQueue(invalidDriverIds);
          print('✅ Removed ${invalidDriverIds.length} invalid drivers from queue');
        } else {
          print('✅ Queue is clean - no invalid drivers found');
        }
      } else {
        print('ℹ️ Queue document does not exist');
      }
    } catch (e) {
      print('❌ Error during manual queue cleanup: $e');
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

  /// Update geofence for a specific barangay
  Future<void> updateBarangayGeofence(
    String barangayId,
    List<Map<String, dynamic>> coordinates,
  ) async {
    try {
      await _firestore.collection('barangays').doc(barangayId).update({
        'geofenceCoordinates': coordinates,
      });
      print('✅ Updated service area geofence for barangay: $barangayId');
    } catch (e) {
      print('Error updating barangay geofence: $e');
      rethrow;
    }
  }

  /// Update TODA terminal geofence for a specific barangay
  Future<void> updateBarangayTerminalGeofence(
    String barangayId,
    List<Map<String, dynamic>> coordinates,
  ) async {
    try {
      await _firestore.collection('barangays').doc(barangayId).update({
        'terminalGeofenceCoordinates': coordinates,
      });
      print('✅ Updated terminal geofence for barangay: $barangayId');
    } catch (e) {
      print('Error updating barangay terminal geofence: $e');
      rethrow;
    }
  }

  /// Get all barangays
  Future<List<BarangayModel>> getAllBarangays({bool includeInactive = false}) async {
    try {
      Future<QuerySnapshot<Map<String, dynamic>>> _fetchBarangays() {
        return _firestore.collection('barangays').orderBy('name').get();
      }

      var snapshot = await _fetchBarangays();

      if (snapshot.docs.isEmpty) {
        // Attempt to initialize barangays if none exist yet
        final barangayService = BarangayService();
        await barangayService.initializeBarangays();
        snapshot = await _fetchBarangays();
      }

      final barangaysList = snapshot.docs
          .map((doc) => BarangayModel.fromFirestore(doc))
          .where((barangay) => !_excludedBarangayNames.contains(barangay.name.toLowerCase()))
          .toList();

      // Deduplicate by name
      final uniqueBarangaysMap = <String, BarangayModel>{};
      for (var b in barangaysList) {
        final name = b.name.trim();
        if (!uniqueBarangaysMap.containsKey(name)) {
          uniqueBarangaysMap[name] = b;
        } else {
           // If duplicate exists, prefer the one with 'barangay_' ID
          final existing = uniqueBarangaysMap[name]!;
          if (!existing.id.startsWith('barangay_') && b.id.startsWith('barangay_')) {
            uniqueBarangaysMap[name] = b;
          }
        }
      }
      
      final barangays = uniqueBarangaysMap.values.toList();
      // Sort alphabetically by name
      barangays.sort((a, b) => a.name.compareTo(b.name));

      if (includeInactive) {
        return barangays;
      }

      return barangays.where((barangay) => barangay.isActive).toList();
    } catch (e) {
      print('Error fetching barangays: $e');
      return [];
    }
  }

  /// Get barangay by ID (tries direct ID first, then searches by name)
  Future<BarangayModel?> getBarangayById(String barangayId) async {
    try {
      // First try direct document ID
      final doc = await _firestore
          .collection('barangays')
          .doc(barangayId)
          .get();
      
      if (doc.exists) {
        return BarangayModel.fromFirestore(doc);
      }
      
      // If not found, extract barangay name from ID (e.g., barangay_10 -> get all and match)
      print('🔍 Direct ID not found, searching all barangays: $barangayId');
      final snapshot = await _firestore
          .collection('barangays')
          .get();
      
      // Try to find by matching the barangayId or by index
      for (var doc in snapshot.docs) {
        final barangay = BarangayModel.fromFirestore(doc);
        // Match by document ID or by barangayId field if it exists
        if (doc.id == barangayId) {
          print('✅ Found barangay by document ID: $barangayId');
          return barangay;
        }
      }
      
      print('❌ Barangay not found: $barangayId');
      return null;
    } catch (e) {
      print('Error fetching barangay: $e');
      return null;
    }
  }

  // Document upload for driver verification (stored as base64 in Firestore)
  Future<String> uploadDriverDocument(
    String driverId,
    String documentType,
    XFile imageFile,
  ) async {
    try {
      // Read image bytes
      var bytes = await imageFile.readAsBytes();
      
      print('📸 Original image size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
      
      // Compress image if it's too large (> 500KB)
      if (bytes.length > 500 * 1024) {
        print('🔄 Compressing document in background...');
        
        // Use compute to run compression in a background isolate
        // This prevents the UI from freezing on large images
        bytes = await compute(_compressDocumentStatic, bytes);
        
        print('✅ Compressed document size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
      }
      
      // Verify size is acceptable for Firestore (< 1MB per field)
      if (bytes.length > 1024 * 1024) {
        throw Exception('Image is too large even after compression. Please use a smaller image.');
      }
      
      // Convert to base64 and prefix with data URI for easier rendering
      final base64String = base64Encode(bytes);
      final dataUri = 'data:image/jpeg;base64,$base64String';
      
      print('✅ Document converted to base64: ${(base64String.length / 1024).toStringAsFixed(2)} KB (with data URI)');
      return dataUri;
    } catch (e) {
      print('❌ Error processing driver document: $e');
      rethrow;
    }
  }

  Future<String> uploadDriverProfileImage(
    String driverId,
    XFile imageFile,
  ) async {
    try {
      var bytes = await imageFile.readAsBytes();
      print('📸 Original profile image size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
      if (bytes.length > 500 * 1024) {
        bytes = await compute(_compressDocumentStatic, bytes);
        print('✅ Compressed profile image size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
      }
      if (bytes.length > 1024 * 1024) {
        throw Exception('Image is too large even after compression. Please use a smaller image.');
      }
      final base64String = base64Encode(bytes);
      final dataUri = 'data:image/jpeg;base64,$base64String';
      await _firestore.collection('users').doc(driverId).update({
        'photoUrl': dataUri,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return dataUri;
    } catch (e) {
      print('❌ Error uploading driver profile image: $e');
      rethrow;
    }
  }

  // Notification management removed - using Firestore listeners

  // All notification methods removed - using Firestore listeners for real-time updates

  // All FCM and notification methods removed - app now uses Firestore real-time listeners

  /// Determine which barangay a location belongs to by checking geofences
  Future<String?> getBarangayForLocation(double latitude, double longitude) async {
    try {
      print('🔍 Finding barangay for location: ($latitude, $longitude)');
      
      // Get all barangays with geofence data
      final barangaysSnapshot = await _firestore
          .collection('barangays')
          .where('isActive', isEqualTo: true)
          .get();
      
      print('Checking ${barangaysSnapshot.docs.length} barangays...');
      
      for (var doc in barangaysSnapshot.docs) {
        final data = doc.data();
        final geofenceCoordinates = data['geofenceCoordinates'] as List?;
        
        if (geofenceCoordinates == null || geofenceCoordinates.isEmpty) {
          continue;
        }
        
        // Convert geofence coordinates to LatLng format
        List<List<double>> polygon = [];
        try {
          for (var coord in geofenceCoordinates) {
            if (coord is Map) {
              polygon.add([
                (coord['lat'] as num).toDouble(),
                (coord['lng'] as num).toDouble(),
              ]);
            }
          }
        } catch (e) {
          print('Error parsing geofence for ${data['name']}: $e');
          continue;
        }
        
        // Check if location is inside this barangay's geofence using ray casting algorithm
        if (_isPointInPolygon(latitude, longitude, polygon)) {
          print('✅ Location found in barangay: ${data['name']} (ID: ${doc.id})');
          return doc.id;
        }
      }
      
      print('❌ Location not found in any barangay geofence');
      return null;
    } catch (e) {
      print('Error finding barangay for location: $e');
      return null;
    }
  }

  /// Ray casting algorithm to check if a point is inside a polygon
  bool _isPointInPolygon(double lat, double lng, List<List<double>> polygon) {
    if (polygon.length < 3) return false;
    
    bool inside = false;
    int j = polygon.length - 1;
    
    // Improved precision ray casting with epsilon to avoid division by zero or horizontal edge issues
    const double epsilon = 0.0000000001;
    const double tolerance = 0.000001; // ~0.1 meter

    for (int i = 0; i < polygon.length; i++) {
      double xi = polygon[i][0]; // latitude
      double yi = polygon[i][1]; // longitude
      double xj = polygon[j][0];
      double yj = polygon[j][1];
      
      // Point-on-vertex check
      if ((lat - xi).abs() < tolerance && (lng - yi).abs() < tolerance) return true;

      // Point-on-edge check (simplified)
      double d2 = (xj - xi) * (xj - xi) + (yj - yi) * (yj - yi);
      if (d2 > 0) {
        double t = ((lat - xi) * (xj - xi) + (lng - yi) * (yj - yi)) / d2;
        if (t >= 0 && t <= 1) {
          double pLat = xi + t * (xj - xi);
          double pLng = yi + t * (yj - yi);
          double dist2 = (lat - pLat) * (lat - pLat) + (lng - pLng) * (lng - pLng);
          if (dist2 < tolerance * tolerance) return true;
        }
      }

      bool intersect = ((yi > lng) != (yj > lng)) &&
          (lat < (xj - xi) * (lng - yi) / (yj - yi + epsilon) + xi);
      if (intersect) inside = !inside;
      j = i;
    }
    
    return inside;
  }

  // ============ PASABUY OPERATIONS ============

  /// Create PasaBuy request with queue-based driver assignment
  /// Can route based on either CURRENT GPS LOCATION or SELECTED PICKUP LOCATION
  Future<Map<String, dynamic>> createPasaBuyWithDriverCheck(
    String passengerId,
    String passengerName,
    String passengerPhone,
    GeoPoint pickupLocation,
    String pickupAddress,
    GeoPoint dropoffLocation,
    String dropoffAddress,
    String itemDescription,
    double fare,
    String barangayId,
    String barangayName,
    GeoPoint? currentPassengerLocation, // Passenger's current GPS location
    bool? useCurrentLocation, // true = use current GPS, false = use pickup location
  ) async {
    try {
      print('=== CREATING PASABUY WITH DRIVER CHECK ===');

      // SECURITY: Validate coordinates
      if (!_isValidCoordinate(pickupLocation.latitude, pickupLocation.longitude) ||
          !_isValidCoordinate(dropoffLocation.latitude, dropoffLocation.longitude)) {
        return {
          'success': false,
          'error': 'Invalid location coordinates.',
          'requestId': null,
        };
      }

      // SECURITY: Validate fare
      if (fare <= 0) {
        return {
          'success': false,
          'error': 'Invalid fare amount.',
          'requestId': null,
        };
      }

      final routeByCurrentLocation = useCurrentLocation ?? true;

      final assignmentLocation = routeByCurrentLocation
          ? (currentPassengerLocation ?? GeoPoint(pickupLocation.latitude, pickupLocation.longitude))
          : GeoPoint(pickupLocation.latitude, pickupLocation.longitude);
      
      var passengerBarangayId = await getBarangayForLocation(
        assignmentLocation.latitude,
        assignmentLocation.longitude,
      );

      // Fallback to provided barangayId if location search fails but we have a value
      if (passengerBarangayId == null && barangayId.isNotEmpty) {
        print('⚠️ getBarangayForLocation failed, falling back to provided barangayId: $barangayId');
        passengerBarangayId = barangayId;
      }

      final locationType = routeByCurrentLocation ? 'current GPS location' : 'selected pickup location';
      print('📍 Routing based on $locationType: $passengerBarangayId');

      if (passengerBarangayId == null) {
        return {
          'success': false,
          'error': 'Your current location is outside all service areas. Please select a location within any covered barangay.',
          'requestId': null,
        };
      }

      final passengerBarangayDoc = await _firestore
          .collection('barangays')
          .doc(passengerBarangayId)
          .get();

      final passengerBarangayName = passengerBarangayDoc.exists
          ? (passengerBarangayDoc.data()?['name'] as String? ?? barangayName)
          : barangayName;

      final onlineDrivers = await getOnlineDrivers(
        passengerBarangayId: passengerBarangayId,
      );

      if (onlineDrivers.isEmpty) {
        return {
          'success': false,
          'error': 'No drivers are currently available in your area. Please try again later.',
          'requestId': null,
        };
      }

      final pasabuyData = {
        'passengerId': passengerId,
        'passengerName': passengerName,
        'passengerPhone': passengerPhone,
        'pickupLocation': pickupLocation,
        'pickupAddress': pickupAddress,
        'dropoffLocation': dropoffLocation,
        'dropoffAddress': dropoffAddress,
        'itemDescription': itemDescription,
        'fare': fare,
        'status': 'pending',
        'assignedDriverId': null,
        'declinedBy': [],
        'driverId': null,
        'driverName': null,
        'createdAt': FieldValue.serverTimestamp(),
        'acceptedAt': null,
        'completedAt': null,
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(seconds: 30))),
        'barangayId': passengerBarangayId,
        'barangayName': passengerBarangayName,
        'canBeCancelled': true, // Allow cancellation until driver accepts
      };

      final docRef = await _firestore
          .collection('pasabuy_requests')
          .add(pasabuyData);

      print('✅ PasaBuy request created: ${docRef.id}');

      _assignPasaBuyToAvailableDriver(docRef.id).then((assigned) async {
        if (!assigned && onlineDrivers.isNotEmpty) {
          try {
            final fallbackDriverId = onlineDrivers.first['id'] as String;
            await docRef.update({
              'assignedDriverId': fallbackDriverId,
            });
            print('Fallback PasaBuy assignment to driver $fallbackDriverId for ${docRef.id}');
          } catch (e) {
            print('Fallback PasaBuy assignment error for ${docRef.id}: $e');
          }
        }
      }).catchError((e) {
        print('Background PasaBuy assignment error for ${docRef.id}: $e');
      });

      return {
        'success': true,
        'requestId': docRef.id,
        'assignedDriverId': null,
      };
    } catch (e) {
      print('Error creating PasaBuy with driver check: $e');
      return {
        'success': false,
        'error': 'Failed to book PasaBuy: $e',
        'requestId': null,
      };
    }
  }

  /// Get PasaBuy requests for a passenger
  Stream<List<PasaBuyModel>> getPassengerPasaBuyRequests(String passengerId) {
    // Query without orderBy to avoid composite index requirement
    return _firestore
        .collection('pasabuy_requests')
        .where('passengerId', isEqualTo: passengerId)
        .snapshots()
        .map((snapshot) {
          // Sort client-side by createdAt descending
          final docs = snapshot.docs.toList();
          docs.sort((a, b) {
            final aCreatedAt = a['createdAt'] as Timestamp?;
            final bCreatedAt = b['createdAt'] as Timestamp?;
            if (aCreatedAt == null || bCreatedAt == null) return 0;
            return bCreatedAt.compareTo(aCreatedAt); // descending order
          });
          return docs
              .map((doc) => PasaBuyModel.fromFirestore(doc))
              .toList();
        });
  }

  /// Get PasaBuy requests assigned to a specific driver (pending)
  Stream<List<PasaBuyModel>> getAssignedPasaBuyRequestsForDriver(String driverId) {
    return _firestore
        .collection('pasabuy_requests')
        .where('assignedDriverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.toList();
          docs.sort((a, b) {
            final aCreatedAt = a['createdAt'] as Timestamp?;
            final bCreatedAt = b['createdAt'] as Timestamp?;
            if (aCreatedAt == null || bCreatedAt == null) return 0;
            return bCreatedAt.compareTo(aCreatedAt); // descending order
          });
          return docs
              .map((doc) => PasaBuyModel.fromFirestore(doc))
              .toList();
        });
  }

  /// Get active PasaBuy requests for a driver (accepted/in-progress)
  Stream<List<PasaBuyModel>> getActivePasaBuyForDriver(String driverId) {
    return _firestore
        .collection('pasabuy_requests')
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.toList();
          return docs
              .map((doc) => PasaBuyModel.fromFirestore(doc))
              .where((req) => 
                req.status != PasaBuyStatus.completed && 
                req.status != PasaBuyStatus.cancelled &&
                req.status != PasaBuyStatus.pending
              )
              .toList();
        });
  }

  /// Get pending PasaBuy requests for drivers in a barangay (deprecated - use getAssignedPasaBuyRequestsForDriver)
  Stream<List<PasaBuyModel>> getPendingPasaBuyRequestsForBarangay(String barangayId) {
    // Query without orderBy to avoid composite index requirement
    return _firestore
        .collection('pasabuy_requests')
        .where('barangayId', isEqualTo: barangayId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          // Sort client-side by createdAt descending
          final docs = snapshot.docs.toList();
          docs.sort((a, b) {
            final aCreatedAt = a['createdAt'] as Timestamp?;
            final bCreatedAt = b['createdAt'] as Timestamp?;
            if (aCreatedAt == null || bCreatedAt == null) return 0;
            return bCreatedAt.compareTo(aCreatedAt); // descending order
          });
          return docs
              .map((doc) => PasaBuyModel.fromFirestore(doc))
              .toList();
        });
  }

  /// Accept a PasaBuy request (with conflict check)
  Future<bool> acceptPasaBuyRequest(
    String requestId,
    String driverId,
    String driverName,
  ) async {
    try {
      // Check if driver has an active ride
      final activeRides = await _firestore
          .collection('rides')
          .where('assignedDriverId', isEqualTo: driverId)
          .where('status', whereIn: ['accepted', 'inProgress', 'driverOnWay', 'driverArrived'])
          .get();

      if (activeRides.docs.isNotEmpty) {
        print('❌ Driver has an active ride, cannot accept PasaBuy');
        return false;
      }

      // Check if this request is assigned to this driver
      final requestDoc = await _firestore
          .collection('pasabuy_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        print('❌ PasaBuy request not found');
        return false;
      }

      final assignedDriverId = requestDoc.get('assignedDriverId') as String?;
      if (assignedDriverId != driverId) {
        print('❌ This request is not assigned to this driver');
        return false;
      }

      await _firestore.collection('pasabuy_requests').doc(requestId).update({
        'status': 'accepted',
        'driverId': driverId,
        'driverName': driverName,
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // Update driver status to busy
      await _firestore.collection('users').doc(driverId).update({
        'status': 'busy',
        'currentPasaBuy': requestId,
        'currentRide': null, // Clear any potential Ride
        'lastAssigned': Timestamp.now(),
      });

      // Remove driver from queue (they're now busy)
      await removeDriverFromQueue(driverId);

      // Reassign any pending requests (Rides and PasaBuy) from this driver
      await _reassignPendingRideRequestsFromDriver(driverId);
      await _reassignPendingPasaBuyRequestsFromDriver(driverId);

      print('✅ PasaBuy request accepted: $requestId');
      return true;
    } catch (e) {
      print('❌ Error accepting PasaBuy request: $e');
      return false;
    }
  }

  /// Reassign any pending ride requests from a busy driver to the next available driver
  Future<void> _reassignPendingRideRequestsFromDriver(String busyDriverId) async {
    try {
      print('🔄 === REASSIGNING RIDE REQUESTS FROM BUSY DRIVER ===');
      print('   Busy Driver ID: $busyDriverId');
      
      // Find all pending ride requests assigned to this driver
      final pendingRidesSnapshot = await _firestore
          .collection('rides')
          .where('assignedDriverId', isEqualTo: busyDriverId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (pendingRidesSnapshot.docs.isEmpty) {
        print('✅ No pending ride requests to reassign');
        return;
      }

      print('📋 Found ${pendingRidesSnapshot.docs.length} pending ride requests to reassign');

      // Get the busy driver's barangay for queue access
      final driverDoc = await _firestore.collection('users').doc(busyDriverId).get();
      if (!driverDoc.exists) {
        print('❌ Busy driver not found');
        return;
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      final barangayId = driverData['barangayId'] as String?;

      if (barangayId == null) {
        print('❌ Driver has no barangay assigned');
        return;
      }

      // Get the driver queue for this barangay
      final queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();

      if (!queueDoc.exists) {
        print('❌ Queue not found for barangay: $barangayId');
        return;
      }

      final queueData = queueDoc.data() as Map<String, dynamic>;
      final driverQueue = List<String>.from(queueData['drivers'] as List? ?? []);
      
      print('🚗 Driver queue for $barangayId: $driverQueue');

      // Reassign each pending ride request
      for (final rideDoc in pendingRidesSnapshot.docs) {
        final rideData = rideDoc.data() as Map<String, dynamic>;
        final rideId = rideDoc.id;
        final passengerId = rideData['passengerId'] as String?;
        
        // Get list of drivers who already declined this request
        final declinedBy = List<String>.from(rideData['declinedBy'] as List? ?? []);
        
        // Find next available driver (not busy, not declined)
        String? nextDriverId;
        for (final driverId in driverQueue) {
          if (driverId != busyDriverId && !declinedBy.contains(driverId)) {
            // Check if this driver is available (not busy with another ride/PasaBuy)
            final isAvailable = await _isDriverAvailable(driverId);
            if (isAvailable) {
              nextDriverId = driverId;
              break;
            }
          }
        }

        if (nextDriverId != null) {
          // Assign to next available driver
          await _firestore.collection('rides').doc(rideId).update({
            'assignedDriverId': nextDriverId,
            'declinedBy': FieldValue.arrayUnion([busyDriverId]), // Mark busy driver as declined
          });

          print('✅ Ride $rideId reassigned: $busyDriverId → $nextDriverId');

          // Notify passenger about reassignment
          if (passengerId != null) {
            await _createRideReassignedNotification(
              rideId,
              passengerId,
              nextDriverId,
            );
          }
          
        } else {
          // No available drivers found - keep as pending but notify passenger
          print('⚠️ No available drivers for ride $rideId');
          
          if (passengerId != null) {
            await _createNoDriversAvailableNotification(rideId, passengerId, rideData);
          }
        }
      }

      print('✅ Ride reassignment completed for driver $busyDriverId');
    } catch (e) {
      print('❌ Error reassigning ride requests: $e');
    }
  }

  /// Create notification for passenger when ride is reassigned to another driver
  Future<void> _createRideReassignedNotification(
    String rideId,
    String passengerId,
    String newDriverId,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'type': 'ride_reassigned',
        'userId': passengerId,
        'rideId': rideId,
        'newDriverId': newDriverId,
        'title': 'Driver Assigned to Another Request',
        'body': 'Your previous driver was assigned to another request. We\'ve found you a new driver! Please wait for their acceptance.',
        'createdAt': Timestamp.now(),
        'read': false,
        'action': 'wait_for_driver',
      });
    } catch (e) {
      print('Error creating ride reassigned notification: $e');
    }
  }

  // Update pasabuy request status
  Future<void> updatePasaBuyStatus(
    String requestId,
    PasaBuyStatus status, {
    String? driverId,
  }) async {
    try {
      // SECURITY: Verify request exists and get current data
      final requestDoc = await _firestore.collection('pasabuy_requests').doc(requestId).get()
          .timeout(const Duration(seconds: 5));
      if (!requestDoc.exists) {
        throw Exception('PasaBuy request not found');
      }

      final currentData = requestDoc.data() as Map<String, dynamic>;
      final currentDriverId = currentData['driverId'];

      // SECURITY: For driver-initiated status updates, verify authorization
      if (driverId != null &&
          currentDriverId != null &&
          currentDriverId != driverId) {
        throw Exception(
          'Unauthorized: Only assigned driver can update this PasaBuy request',
        );
      }

      // SECURITY: Validate status transitions
      final currentStatus = _normalizePasaBuyStatus(currentData['status']);
      final newStatusStr = status.toString().split('.').last;
      
      if (!_isValidPasaBuyStatusTransition(
        currentStatus,
        newStatusStr,
      )) {
        throw Exception(
          'Invalid PasaBuy status transition from $currentStatus to $newStatusStr',
        );
      }

      // SECURITY: Respect canBeCancelled flag for passenger cancellations
      final canBeCancelled = currentData['canBeCancelled'] as bool? ?? true;
      if (status == PasaBuyStatus.cancelled && driverId == null && !canBeCancelled) {
        throw Exception('This PasaBuy request can no longer be cancelled.');
      }

      Map<String, dynamic> updates = {
        'status': newStatusStr,
      };

      switch (status) {
        case PasaBuyStatus.accepted:
          updates['acceptedAt'] = Timestamp.now();
          if (driverId != null) updates['driverId'] = driverId;
          break;
        case PasaBuyStatus.driver_on_way:
          updates['driverOnWayAt'] = Timestamp.now();
          break;
        case PasaBuyStatus.arrived_pickup:
          updates['arrivedAtPickupAt'] = Timestamp.now();
          updates['shoppingStartedAt'] = Timestamp.now();
          break;
        case PasaBuyStatus.delivery_in_progress:
          updates['purchaseCompletedAt'] = Timestamp.now();
          updates['deliveryStartedAt'] = Timestamp.now();
          break;
        case PasaBuyStatus.completed:
          updates['completedAt'] = Timestamp.now();
          break;
        case PasaBuyStatus.cancelled:
          updates['cancelledAt'] = Timestamp.now();
          break;
        default:
          break;
      }

      await _firestore.collection('pasabuy_requests').doc(requestId).update(updates)
          .timeout(const Duration(seconds: 5));

      try {
        await _firestore.collection('pasabuy_status_logs').add({
          'requestId': requestId,
          'oldStatus': currentStatus,
          'newStatus': newStatusStr,
          'changedByDriverId': driverId ?? currentDriverId,
          'changedByPassengerId': driverId == null ? currentData['passengerId'] : null,
          'actorRole': driverId != null ? 'driver' : 'system_or_passenger',
          'timestamp': Timestamp.now(),
        }).timeout(const Duration(seconds: 5));
      } catch (e) {
        print('Warning: Failed to log PasaBuy status change: $e');
      }

      // Handle driver status updates when PasaBuy is completed or cancelled
      if (status == PasaBuyStatus.completed || status == PasaBuyStatus.cancelled) {
        final driverIdToUpdate = driverId ?? currentDriverId;
        if (driverIdToUpdate != null) {
          try {
            await _firestore.collection('users').doc(driverIdToUpdate).update({
              'status': 'available',
              'currentPasaBuy': null,
              'currentRide': null, // Also ensure Ride is cleared
            }).timeout(const Duration(seconds: 3));
            print('Driver $driverIdToUpdate status updated to available');
          } catch (e) {
            print('Warning: Failed to update driver status: $e');
          }
        }
      }

      // Send push notification for status updates (except accepted)
      if (status != PasaBuyStatus.accepted) {
        _sendPasaBuyStatusNotification(requestId, status, driverId)
            .timeout(const Duration(seconds: 3))
            .catchError((e) {
          print('Warning: Failed to send PasaBuy notification: $e');
        });
      }

      print('✅ PasaBuy status updated to $status for request: $requestId');
    } catch (e) {
      print('Error updating PasaBuy status: $e');
      rethrow;
    }
  }

  /// Send push notification for PasaBuy status updates
  Future<void> _sendPasaBuyStatusNotification(
    String requestId,
    PasaBuyStatus status,
    String? driverId,
  ) async {
    try {
      final requestDoc = await _firestore.collection('pasabuy_requests').doc(requestId).get();
      if (!requestDoc.exists) return;

      final data = requestDoc.data() as Map<String, dynamic>;
      final passengerId = data['passengerId'];

      String driverName = 'Driver';
      if (driverId != null) {
        final driverDoc = await _firestore.collection('users').doc(driverId).get();
        if (driverDoc.exists) {
          driverName = (driverDoc.data() as Map<String, dynamic>)['name'] ?? 'Driver';
        }
      }

      String title = '🛍️ PasaBuy Update';
      String body = 'Your PasaBuy request status has changed.';

      switch (status) {
        case PasaBuyStatus.driver_on_way:
          title = '🚗 Driver On The Way!';
          body = 'Your PasaBuy driver $driverName is on the way to the store!';
          break;
        case PasaBuyStatus.arrived_pickup:
          title = '📍 Driver Arrived at Store!';
          body = 'Your PasaBuy driver $driverName has arrived at the store.';
          break;
        case PasaBuyStatus.delivery_in_progress:
          title = '🛍️ Delivery In Progress!';
          body = 'Your PasaBuy driver $driverName has started the delivery to your location.';
          break;
        case PasaBuyStatus.completed:
          title = '✅ PasaBuy Completed!';
          body = 'Your PasaBuy request with $driverName has been completed. Enjoy your items!';
          break;
        case PasaBuyStatus.cancelled:
          title = '❌ PasaBuy Cancelled';
          body = 'Your PasaBuy request has been cancelled.';
          break;
        default:
          break;
      }

      await _firestore.collection('notifications').add({
        'userId': passengerId,
        'type': 'pasabuy_${status.name}',
        'title': title,
        'body': body,
        'data': data,
        'read': false,
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      print('Error sending PasaBuy status notification: $e');
    }
  }

  /// Complete a PasaBuy request
  Future<bool> completePasaBuyRequest(String requestId, {String? driverId}) async {
    try {
      await updatePasaBuyStatus(requestId, PasaBuyStatus.completed, driverId: driverId);
      print('✅ PasaBuy request completed: $requestId');
      return true;
    } catch (e) {
      print('❌ Error completing PasaBuy request: $e');
      return false;
    }
  }

  /// Decline a PasaBuy request - same logic as regular rides
  Future<bool> declinePasaBuyRequest(String requestId, String driverId) async {
    try {
      print('🚫 === DECLINE PASABUY REQUEST DEBUG ===');
      print('   Request ID: $requestId');
      print('   Driver ID: $driverId');
      
      // SECURITY: Verify request exists and is assigned to this driver
      print('📄 Checking if PasaBuy request exists...');
      final requestDoc = await _firestore
          .collection('pasabuy_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        print('❌ PasaBuy request not found');
        return false;
      }
      print('✅ PasaBuy request document found');

      final data = requestDoc.data() as Map<String, dynamic>;
      final assignedDriverId = data['assignedDriverId'];
      final status = data['status'];
      final barangayId = data['barangayId'] as String?;
      final passengerId = data['passengerId'];
      
      print('📋 PasaBuy request details:');
      print('   Assigned Driver: $assignedDriverId');
      print('   Current Status: $status');
      print('   Requesting Driver: $driverId');
      print('   Barangay: $barangayId');

      // SECURITY: Verify this driver is assigned to this request
      if (assignedDriverId != driverId) {
        print('❌ Authorization failed: Driver not assigned to this PasaBuy request');
        return false;
      }
      print('✅ Authorization passed');

      // STEP 1: Unassign the request from the declining driver
      print('📝 Unassigning PasaBuy request from declining driver...');
      await _firestore.collection('pasabuy_requests').doc(requestId).update({
        'assignedDriverId': FieldValue.delete(),
        'status': 'pending', // Reset to pending for reassignment
        'declinedBy': FieldValue.arrayUnion([driverId]), // Track who declined
        'declinedAt': Timestamp.now(),
      });
      print('✅ PasaBuy request unassigned from driver $driverId');

      // STEP 2: Remove driver from queue (instead of moving to end)
      print('🔄 Removing driver from queue due to decline...');
      await removeDriverFromQueue(driverId);
      print('✅ Driver removed from queue');

      // STEP 3: Track that this driver declined this request
      await _firestore.collection('users').doc(driverId).update({
        'lastDeclinedAt': Timestamp.now(),
        'declineCount': FieldValue.increment(1),
      });

      // STEP 4: Notify passenger and WAIT for their decision (same as rides)
      if (passengerId != null) {
        // Notify passenger that driver declined
        // Passenger must manually choose to find another driver
        await _createPasaBuyDeclineNotification(
          requestId,
          passengerId,
          driverId,
          data,
        );
        print('✅ Passenger notified about PasaBuy decline. Waiting for passenger decision...');

        // AUTO-REASSIGN: Try to find another driver immediately
        print('🔄 Auto-reassigning PasaBuy $requestId to next driver...');
        await _assignPasaBuyToAvailableDriver(requestId);
      }

      // NOTE: Request stays in 'pending' status with no assigned driver
      // Passenger will see option to "Find Another Driver" or "Cancel Request"
      // Next driver in queue remains #1 but NOT assigned yet
      
      print(
        '✅ PasaBuy request $requestId declined by driver $driverId. Driver removed from queue. Waiting for passenger decision.',
      );
      return true;
    } catch (e) {
      print('❌ Error declining PasaBuy request: $e');
      return false;
    }
  }

  /// Create notification for passenger when driver declines PasaBuy request
  Future<void> _createPasaBuyDeclineNotification(
    String requestId,
    String passengerId,
    String driverId,
    Map<String, dynamic> requestData,
  ) async {
    try {
      print('📝 Creating PasaBuy decline notification for passenger');
      print('   Passenger ID: $passengerId');
      print('   Request ID: $requestId');
      print('   Driver ID: $driverId');
      
      final notificationData = {
        'type': 'pasabuy_declined',
        'userId': passengerId,
        'requestId': requestId,
        'driverId': driverId,
        'title': 'Driver Declined Your PasaBuy Request',
        'body':
            'The assigned driver declined your PasaBuy request from ${requestData['pickupAddress'] ?? 'pickup location'} to ${requestData['dropoffAddress'] ?? 'destination'}. Would you like to find another driver?',
        'createdAt': Timestamp.now(),
        'read': false,
        'action': 'find_another_driver',
        'pickupAddress': requestData['pickupAddress'] ?? '',
        'dropoffAddress': requestData['dropoffAddress'] ?? '',
        'itemDescription': requestData['itemDescription'] ?? '',
      };
      
      print('   Notification data: $notificationData');
      print('   Attempting to write to Firestore...');
      
      final docRef = await _firestore.collection('notifications').add(notificationData);
      
      print('✅ PasaBuy decline notification created with ID: ${docRef.id}');
      print('   Document successfully written to Firestore');
    } catch (e, stackTrace) {
      print('❌ Error creating PasaBuy decline notification: $e');
      print('   Stack trace: $stackTrace');
      print('   Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Create notification for passenger when another driver is found for PasaBuy
  Future<void> _createPasaBuyFoundAnotherDriverNotification(
    String requestId,
    String passengerId,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'type': 'pasabuy_found_another_driver',
        'userId': passengerId,
        'requestId': requestId,
        'title': 'Found Another Driver for Your PasaBuy!',
        'body': 'Great! We found another driver for your PasaBuy request. Please wait for confirmation.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'action': 'wait_for_driver',
      });
    } catch (e) {
      print('Error creating PasaBuy found another driver notification: $e');
    }
  }

  /// Create notification for passenger when no drivers are available for PasaBuy
  Future<void> _createPasaBuyNoDriversAvailableNotification(
    String requestId,
    String passengerId,
    Map<String, dynamic> requestData,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'type': 'pasabuy_no_drivers_available',
        'userId': passengerId,
        'requestId': requestId,
        'title': 'No Drivers Available for PasaBuy',
        'body':
            'Sorry, there are no drivers available for your PasaBuy request from ${requestData['pickupAddress'] ?? 'pickup location'} to ${requestData['dropoffAddress'] ?? 'destination'}. Please try again later.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'action': 'return_home',
        'pickupAddress': requestData['pickupAddress'] ?? '',
        'dropoffAddress': requestData['dropoffAddress'] ?? '',
        'itemDescription': requestData['itemDescription'] ?? '',
      });
    } catch (e) {
      print('Error creating PasaBuy no drivers notification: $e');
    }
  }

  /// Passenger chooses to find another driver for PasaBuy after previous driver declined
  Future<bool> requestAnotherPasaBuyDriver(String requestId) async {
    try {
      print('🔍 Passenger requesting another driver for PasaBuy $requestId');
      
      // Verify request exists and is still pending
      final requestDoc = await _firestore.collection('pasabuy_requests').doc(requestId).get();
      if (!requestDoc.exists) {
        throw Exception('PasaBuy request not found');
      }
      
      final requestData = requestDoc.data() as Map<String, dynamic>;
      final status = requestData['status'];
      
      if (status != 'pending') {
        throw Exception('PasaBuy request is no longer pending (current status: $status)');
      }
      
      // Try to assign to next available driver in queue (same logic as rides)
      print('🔄 Looking for next available driver for PasaBuy...');
      await diagnosePasaBuyAssignment(requestId);
      final reassigned = await _assignPasaBuyToAvailableDriver(requestId);
      
      if (reassigned) {
        print('✅ Successfully assigned PasaBuy $requestId to next driver');
        
        // Notify passenger that we found another driver
        final passengerId = requestData['passengerId'];
        if (passengerId != null) {
          await _createPasaBuyFoundAnotherDriverNotification(requestId, passengerId);
        }
        return true;
      } else {
        print('❌ No more drivers available for PasaBuy $requestId');
        
        // Mark request as cancelled - no drivers available
        // Note: We use 'cancelled' instead of 'failed' because:
        // 1. 'failed' is not in the PasaBuyStatus enum
        // 2. Firestore rules allow passengers to update status to 'cancelled' but not arbitrary statuses
        await _firestore.collection('pasabuy_requests').doc(requestId).update({
          'status': 'cancelled',
          'cancelledReason': 'No available drivers',
          'cancelledAt': Timestamp.now(),
        });
        
        // Notify passenger
        final passengerId = requestData['passengerId'];
        if (passengerId != null) {
          await _createPasaBuyNoDriversAvailableNotification(requestId, passengerId, requestData);
        }
        return false;
      }
    } catch (e) {
      print('Error requesting another PasaBuy driver: $e');
      rethrow;
    }
  }

  /// Assign PasaBuy request to next available driver in queue (same logic as rides)
  Future<bool> _assignPasaBuyToAvailableDriver(String requestId) async {
    try {
      print('=== PASABUY ASSIGNMENT DEBUG for request $requestId ===');

      // Step 1: Get request data to find passenger and their barangay
      final requestDoc = await _firestore.collection('pasabuy_requests').doc(requestId).get();
      if (!requestDoc.exists) {
        print('PasaBuy request not found: $requestId');
        return false;
      }
      final requestData = requestDoc.data() as Map<String, dynamic>;
      
      final passengerId = requestData['passengerId'] as String?;
      if (passengerId == null) {
        print('No passenger ID in PasaBuy request data');
        return false;
      }

      final barangayId = requestData['barangayId'] as String?;
      if (barangayId == null) {
        print('No barangay ID in PasaBuy request data');
        return false;
      }

      // Step 2: Get the driver queue for this barangay
      final queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();

      if (!queueDoc.exists) {
        print('No queue found for barangay: $barangayId');
        return false;
      }

      final queueData = queueDoc.data() as Map<String, dynamic>;
      final driverQueue = List<String>.from(queueData['drivers'] as List? ?? []);
      
      print('Driver queue for $barangayId: $driverQueue');

      if (driverQueue.isEmpty) {
        print('No drivers in queue for barangay $barangayId');
        return false;
      }

      // Step 3: Get list of drivers who already declined this request
      final declinedBy = List<String>.from(requestData['declinedBy'] as List? ?? []);
      print('Drivers who already declined: $declinedBy');

      // Step 4: Find first available driver who hasn't declined
      String? availableDriverId;

      // Check drivers one by one in queue order to ensure strict FIFO
      for (String driverId in driverQueue) {
        try {
          final DocumentSnapshot driverDoc = await _firestore
              .collection('users')
              .doc(driverId)
              .get();

          if (driverDoc.exists) {
            final driverData = driverDoc.data() as Map<String, dynamic>;
            final isApproved = driverData['isApproved'] ?? false;
            final isInQueue = driverData['isInQueue'] ?? false;
            final driverBarangayId = driverData['barangayId'] as String?;

            print('Checking driver $driverId for PasaBuy: approved=$isApproved, inQueue=$isInQueue');

            // Check if driver is available (not in declinedBy, approved, same barangay)
            if (!declinedBy.contains(driverId) && isApproved && driverBarangayId == barangayId) {
              // Also double check if they are truly available (not busy)
              final isTrulyAvailable = await _isDriverAvailable(driverId);
              if (isTrulyAvailable) {
                availableDriverId = driverId;
                print('✅ Found available driver for PasaBuy (first in queue order): $driverId');
                break;
              }
            }
          }
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied') {
            print('⚠️ Permission denied accessing driver $driverId profile for PasaBuy. Skipping...');
            continue;
          }
          print('Error checking driver $driverId for PasaBuy: $e');
        } catch (e) {
          print('Error checking driver $driverId for PasaBuy: $e');
        }
      }

      if (availableDriverId == null) {
        print('No available drivers found in queue for PasaBuy $requestId');
        return false;
      }

      // Step 5: Assign the request to the available driver
      await _firestore.collection('pasabuy_requests').doc(requestId).update({
        'assignedDriverId': availableDriverId,
        'status': 'pending',
        'assignedAt': Timestamp.now(),
      });

      print('✅ PasaBuy request $requestId assigned to driver $availableDriverId');

      // Step 6: Assignment complete
      final passengerName = requestData['passengerName'] as String? ?? 'Passenger';
      
      print('📋 PasaBuy assigned to driver $availableDriverId');

      return true;
    } catch (e) {
      print('Error assigning PasaBuy to available driver: $e');
      return false;
    }
  }
  
  Future<Map<String, dynamic>> diagnosePasaBuyAssignment(String requestId) async {
    try {
      print('=== DIAGNOSE PASABUY ASSIGNMENT for $requestId ===');
      final doc = await _firestore.collection('pasabuy_requests').doc(requestId).get();
      if (!doc.exists) {
        print('PasaBuy not found: $requestId');
        return {'exists': false};
      }
      final data = doc.data() as Map<String, dynamic>;
      final barangayId = data['barangayId'] as String?;
      print('PasaBuy barangayId: $barangayId');
      if (barangayId == null) {
        return {'exists': true, 'barangayId': null};
      }
      final queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();
      final queue = queueDoc.exists
          ? List<String>.from((queueDoc.data() as Map<String, dynamic>?)?['drivers'] ?? [])
          : <String>[];
      print('Queue: $queue');
      final declined = List<String>.from(data['declinedBy'] as List? ?? []);
      final checked = <Map<String, dynamic>>[];
      String? firstEligible;
      String? firstAvailable;
      for (int i = 0; i < queue.length; i += 10) {
        final batchIds = queue.skip(i).take(10).toList();
        final snap = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: batchIds)
            .get();
        final map = {for (var d in snap.docs) d.id: d.data() as Map<String, dynamic>};
        for (final id in batchIds) {
          final d = map[id];
          if (d == null) {
            checked.add({'id': id, 'exists': false});
            continue;
          }
          final isApproved = d['isApproved'] ?? false;
          final isInQueue = d['isInQueue'] ?? false;
          final role = d['role'] ?? 'unknown';
          final driverBarangayId = d['barangayId'] as String?;
          final barangayMatch = driverBarangayId == barangayId;
          final notDeclined = !declined.contains(id);
          final eligible = role == 'driver' && isApproved && isInQueue && barangayMatch && notDeclined;
          bool available = false;
          if (eligible) {
            available = await _isDriverAvailable(id);
          }
          checked.add({
            'id': id,
            'exists': true,
            'approved': isApproved,
            'inQueue': isInQueue,
            'role': role,
            'barangayMatch': barangayMatch,
            'notDeclined': notDeclined,
            'eligible': eligible,
            'available': available,
          });
          if (firstEligible == null && eligible) {
            firstEligible = id;
          }
          if (firstAvailable == null && eligible && available) {
            firstAvailable = id;
          }
        }
      }
      print('First eligible: $firstEligible');
      print('First available: $firstAvailable');
      return {
        'exists': true,
        'barangayId': barangayId,
        'queue': queue,
        'declinedBy': declined,
        'firstEligible': firstEligible,
        'firstAvailable': firstAvailable,
        'checked': checked,
      };
    } catch (e) {
      print('Error diagnosing pasabuy assignment: $e');
      return {'error': e.toString()};
    }
  }

  /// Cancel a PasaBuy request
  Future<bool> cancelPasaBuyRequest(String requestId) async {
    try {
      await updatePasaBuyStatus(requestId, PasaBuyStatus.cancelled);
      print('✅ PasaBuy request cancelled: $requestId');
      return true;
    } catch (e) {
      print('❌ Error cancelling PasaBuy request: $e');
      return false;
    }
  }

  /// Get a single PasaBuy request
  Future<PasaBuyModel?> getPasaBuyRequest(String requestId) async {
    try {
      final doc = await _firestore
          .collection('pasabuy_requests')
          .doc(requestId)
          .get();
      
      if (doc.exists) {
        return PasaBuyModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error fetching PasaBuy request: $e');
      return null;
    }
  }

  /// Get stream of a single PasaBuy request
  Stream<PasaBuyModel?> getPasaBuyStream(String requestId) {
    return _firestore
        .collection('pasabuy_requests')
        .doc(requestId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists) {
        return PasaBuyModel.fromFirestore(snapshot);
      }
      return null;
    });
  }

  /// Get PasaBuy requests accepted by a driver
  Stream<List<PasaBuyModel>> getDriverPasaBuyRequests(String driverId) {
    // Query without orderBy to avoid composite index requirement
    return _firestore
        .collection('pasabuy_requests')
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: ['accepted', 'completed'])
        .snapshots()
        .map((snapshot) {
          // Sort client-side by acceptedAt descending
          final docs = snapshot.docs.toList();
          docs.sort((a, b) {
            final aAcceptedAt = a['acceptedAt'] as Timestamp?;
            final bAcceptedAt = b['acceptedAt'] as Timestamp?;
            if (aAcceptedAt == null || bAcceptedAt == null) return 0;
            return bAcceptedAt.compareTo(aAcceptedAt); // descending order
          });
          return docs
              .map((doc) => PasaBuyModel.fromFirestore(doc))
              .toList();
        });
  }

  // ============ ADMIN USER MANAGEMENT ============

  /// Get all drivers grouped by barangay
  Stream<Map<String, List<DriverModel>>> getAllDriversByBarangay() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .snapshots()
        .map((snapshot) {
          final drivers = snapshot.docs
              .map((doc) => DriverModel.fromFirestore(doc))
              .toList();
          
          // Group by barangay
          final Map<String, List<DriverModel>> grouped = {};
          for (var driver in drivers) {
            if (!grouped.containsKey(driver.barangayId)) {
              grouped[driver.barangayId] = [];
            }
            grouped[driver.barangayId]!.add(driver);
          }
          return grouped;
        });
  }

  /// Get all passengers grouped by barangay
  Stream<Map<String, List<Map<String, dynamic>>>> getAllPassengersByBarangay() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'passenger')
        .snapshots()
        .map((snapshot) {
          final passengers = snapshot.docs
              .map((doc) => {
                    ...doc.data(),
                    'id': doc.id, // Ensure document ID is always available
                  })
              .toList();
          
          // Group by barangayName
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (var passenger in passengers) {
            final barangayName = passenger['barangayName']?.toString() ?? 'Unknown';
            if (!grouped.containsKey(barangayName)) {
              grouped[barangayName] = [];
            }
            grouped[barangayName]!.add(passenger);
          }
          return grouped;
        });
  }

  /// Deactivate a user (driver or passenger)
  Future<void> deactivateUser(String userId, String adminId) async {
    try {
      if (userId.isEmpty || adminId.isEmpty) {
        throw Exception('Invalid user ID or admin ID');
      }
      
      // SECURITY: Verify the user performing this action is an admin
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin not found');
      }
      
      final adminData = adminDoc.data() as Map<String, dynamic>?;
      if (adminData == null || adminData['role'] != 'admin') {
        throw Exception('Only admin can deactivate users');
      }

      // Deactivate the user
      await _firestore.collection('users').doc(userId).update({
        'isActive': false,
        'deactivatedAt': Timestamp.now(),
        'deactivatedBy': adminId,
      });

      print('✅ User deactivated: $userId');
    } catch (e) {
      print('❌ Error deactivating user: $e');
      rethrow;
    }
  }

  /// Activate a deactivated user
  Future<void> activateUser(String userId, String adminId) async {
    try {
      if (userId.isEmpty || adminId.isEmpty) {
        throw Exception('Invalid user ID or admin ID');
      }
      
      // SECURITY: Verify the user performing this action is an admin
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin not found');
      }
      
      final adminData = adminDoc.data() as Map<String, dynamic>?;
      if (adminData == null || adminData['role'] != 'admin') {
        throw Exception('Only admin can activate users');
      }

      // Activate the user
      await _firestore.collection('users').doc(userId).update({
        'isActive': true,
        'deactivatedAt': FieldValue.delete(),
        'deactivatedBy': FieldValue.delete(),
      });

      print('✅ User activated: $userId');
    } catch (e) {
      print('❌ Error activating user: $e');
      rethrow;
    }
  }

  /// Mark driver as paid (Admin)
  Future<void> markDriverAsPaid(String driverId, String adminId) async {
    try {
      if (driverId.isEmpty || adminId.isEmpty) {
        throw Exception('Invalid driver ID or admin ID');
      }
      
      // SECURITY: Verify the user performing this action is an admin
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin not found');
      }
      
      final adminData = adminDoc.data() as Map<String, dynamic>?;
      if (adminData == null || adminData['role'] != 'admin') {
        throw Exception('Only admin can mark drivers as paid');
      }

      // SECURITY: Verify driver exists
      final driverDoc = await _firestore.collection('users').doc(driverId).get();
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }

      // Mark driver as paid
      await _firestore.collection('users').doc(driverId).update({
        'isPaid': true,
        'lastPaidAt': Timestamp.now(),
        'paidBy': adminId,
      });

      print('✅ Driver marked as paid: $driverId');
    } catch (e) {
      print('❌ Error marking driver as paid: $e');
      rethrow;
    }
  }

  Future<void> markDriversAsPaidBulk(List<String> driverIds, String adminId) async {
    try {
      final uniqueIds = driverIds.where((id) => id.isNotEmpty).toSet().toList();
      if (uniqueIds.isEmpty || adminId.isEmpty) {
        throw Exception('Invalid driver IDs or admin ID');
      }

      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin not found');
      }

      final adminData = adminDoc.data() as Map<String, dynamic>?;
      if (adminData == null || adminData['role'] != 'admin') {
        throw Exception('Only admin can mark drivers as paid');
      }

      const batchLimit = 500;
      for (var i = 0; i < uniqueIds.length; i += batchLimit) {
        final chunk = uniqueIds.sublist(i, (i + batchLimit) > uniqueIds.length ? uniqueIds.length : (i + batchLimit));
        final batch = _firestore.batch();
        for (final driverId in chunk) {
          batch.update(_firestore.collection('users').doc(driverId), {
            'isPaid': true,
            'lastPaidAt': Timestamp.now(),
            'paidBy': adminId,
          });
        }
        await batch.commit();
      }

      print('✅ Drivers marked as paid (bulk): ${uniqueIds.length}');
    } catch (e) {
      print('❌ Error marking drivers as paid (bulk): $e');
      rethrow;
    }
  }

  /// Send membership expiration notice to all drivers in a barangay
  Future<void> sendMembershipExpirationNotice(String barangayId) async {
    try {
      // Get all drivers in the barangay
      final driversQuery = await _firestore
          .collection('users')
          .where('barangayId', isEqualTo: barangayId)
          .where('role', isEqualTo: 'driver')
          .get();

      int notificationCount = 0;

      // Create notification for each driver
      for (final driverDoc in driversQuery.docs) {
        final driverData = driverDoc.data();
        final driverName = driverData['name'] ?? 'Driver';

        await _firestore.collection('notifications').add({
          'type': 'membership_expiration',
          'userId': driverDoc.id,
          'title': '⚠️ Membership Expiring Soon',
          'body':
              'Your membership is ending this week. Please renew your membership using the qr code in the app or the gcash number.\n\nThank you for your service and understanding.',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'barangayId': barangayId,
          'driverId': driverDoc.id,
          'driverName': driverName,
          'action': 'renew_membership',
        });

        notificationCount++;
      }

      print('✅ Sent membership expiration notice to $notificationCount drivers in barangay: $barangayId');
    } catch (e) {
      print('❌ Error sending membership expiration notices: $e');
      rethrow;
    }
  }

  Future<void> sendMembershipExpirationNoticeToDriver(String driverId) async {
    try {
      final driverDoc = await _firestore.collection('users').doc(driverId).get();
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      
      // Get the correct driver ID (some docs use 'userId' field, others use doc.id)
      final actualDriverId = driverData['userId'] as String? ?? driverDoc.id;
      final role = driverData['role'] as String? ?? '';
      
      if (role != 'driver') {
        throw Exception('User is not a driver');
      }

      final barangayId = driverData['barangayId'] as String? ?? '';
      final driverName = driverData['name'] ?? 'Driver';

      await _firestore.collection('notifications').add({
        'type': 'membership_expiration',
        'userId': actualDriverId,
        'title': '⚠️ Membership Expiring Soon',
        'body':
            'Your membership is ending this week. Please renew your membership using the qr code in the app or the gcash number.\n\nThank you for your service and understanding.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'barangayId': barangayId,
        'driverId': actualDriverId,
        'driverName': driverName,
        'action': 'renew_membership',
      });
    } catch (e) {
      rethrow;
    }
  }

  /// Send membership expiration notice to all drivers in all barangays
  Future<void> sendMembershipExpirationNoticeToAllBarangays() async {
    try {
      // Get all barangays
      final barangaysQuery = await _firestore.collection('barangays').get();

      int totalNotifications = 0;

      // Send notice to each barangay
      for (final barangayDoc in barangaysQuery.docs) {
        final barangayId = barangayDoc.id;

        // Get all drivers in this barangay
        final driversQuery = await _firestore
            .collection('users')
            .where('barangayId', isEqualTo: barangayId)
            .where('role', isEqualTo: 'driver')
            .get();

        // Create notification for each driver
        for (final driverDoc in driversQuery.docs) {
          final driverData = driverDoc.data();
          final driverName = driverData['name'] ?? 'Driver';

          await _firestore.collection('notifications').add({
            'type': 'membership_expiration',
            'userId': driverDoc.id,
            'title': '⚠️ Membership Expiring Soon',
            'body':
                'Your membership is ending this week. Please renew your membership using the qr code in the app or the gcash number.\n\nThank you for your service and understanding.',
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
            'barangayId': barangayId,
            'driverId': driverDoc.id,
            'driverName': driverName,
            'action': 'renew_membership',
          });

          totalNotifications++;
        }
      }

      print('✅ Sent membership expiration notice to $totalNotifications drivers across all barangays');
    } catch (e) {
      print('❌ Error sending membership expiration notices to all barangays: $e');
      rethrow;
    }
  }

  /// Clear all membership expiration notices for all drivers
  /// Only admins can perform this operation (enforced by Firestore rules)
  Future<void> clearAllMembershipNotices(String adminId) async {
    try {
      // Get all membership expiration notifications
      final notificationsQuery = await _firestore
          .collection('notifications')
          .where('type', isEqualTo: 'membership_expiration')
          .get();

      if (notificationsQuery.docs.isEmpty) {
        print('✅ No membership expiration notices to clear');
        return;
      }

      // Use batch write for better performance
      WriteBatch batch = _firestore.batch();
      int deletedCount = 0;

      // Add delete operations to batch
      for (final notificationDoc in notificationsQuery.docs) {
        batch.delete(notificationDoc.reference);
        deletedCount++;
        
        // Firestore batch has a limit of 500 operations, so commit in chunks
        if (deletedCount % 500 == 0) {
          await batch.commit();
          batch = _firestore.batch();
        }
      }

      // Commit remaining operations
      if (deletedCount % 500 != 0) {
        await batch.commit();
      }

      print('✅ Cleared $deletedCount membership expiration notices');
    } catch (e) {
      print('❌ Error clearing membership expiration notices: $e');
      rethrow;
    }
  }

  /// Mark driver as unpaid (Admin)
  Future<void> markDriverAsUnpaid(String driverId, String adminId) async {
    try {
      if (driverId.isEmpty || adminId.isEmpty) {
        throw Exception('Invalid driver ID or admin ID');
      }
      
      // SECURITY: Verify the user performing this action is an admin
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin not found');
      }
      
      final adminData = adminDoc.data() as Map<String, dynamic>?;
      if (adminData == null || adminData['role'] != 'admin') {
        throw Exception('Only admin can mark drivers as unpaid');
      }

      // SECURITY: Verify driver exists
      final driverDoc = await _firestore.collection('users').doc(driverId).get();
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }

      // Mark driver as unpaid
      await _firestore.collection('users').doc(driverId).update({
        'isPaid': false,
        'lastPaidAt': FieldValue.delete(),
        'paidBy': FieldValue.delete(),
      });

      print('✅ Driver marked as unpaid: $driverId');
    } catch (e) {
      print('❌ Error marking driver as unpaid: $e');
      rethrow;
    }
  }

  Future<void> markDriversAsUnpaidBulk(List<String> driverIds, String adminId) async {
    try {
      final uniqueIds = driverIds.where((id) => id.isNotEmpty).toSet().toList();
      if (uniqueIds.isEmpty || adminId.isEmpty) {
        throw Exception('Invalid driver IDs or admin ID');
      }

      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      if (!adminDoc.exists) {
        throw Exception('Admin not found');
      }

      final adminData = adminDoc.data() as Map<String, dynamic>?;
      if (adminData == null || adminData['role'] != 'admin') {
        throw Exception('Only admin can mark drivers as unpaid');
      }

      const batchLimit = 500;
      for (var i = 0; i < uniqueIds.length; i += batchLimit) {
        final chunk = uniqueIds.sublist(i, (i + batchLimit) > uniqueIds.length ? uniqueIds.length : (i + batchLimit));
        final batch = _firestore.batch();
        for (final driverId in chunk) {
          batch.update(_firestore.collection('users').doc(driverId), {
            'isPaid': false,
            'lastPaidAt': FieldValue.delete(),
            'paidBy': FieldValue.delete(),
          });
        }
        await batch.commit();
      }

      print('✅ Drivers marked as unpaid (bulk): ${uniqueIds.length}');
    } catch (e) {
      print('❌ Error marking drivers as unpaid (bulk): $e');
      rethrow;
    }
  }

  /// Consolidate queue for a barangay - ensures all approved drivers in the barangay are in ONE queue
  /// This fixes issues where drivers might be split across multiple queue documents
  Future<void> consolidateQueueForBarangay(String barangayId) async {
    try {
      print('🔧 [consolidateQueueForBarangay] Starting consolidation for barangay: $barangayId');
      
      // Get all approved drivers in this barangay who are in queue
      final driversSnapshot = await _firestore
          .collection('users')
          .where('barangayId', isEqualTo: barangayId)
          .where('role', isEqualTo: 'driver')
          .where('isApproved', isEqualTo: true)
          .where('isInQueue', isEqualTo: true)
          .get();
      
      final driverIds = driversSnapshot.docs.map((doc) => doc.id).toList();
      print('   Found ${driverIds.length} approved drivers in queue for barangay: $barangayId');
      
      if (driverIds.isEmpty) {
        print('   No drivers in queue, skipping consolidation');
        return;
      }
      
      // Get current queue document
      final queueDoc = await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .get();
      
      List<String> currentQueue = [];
      if (queueDoc.exists) {
        final data = queueDoc.data() as Map<String, dynamic>?;
        currentQueue = List<String>.from(data?['drivers'] ?? []);
      }
      
      // Check if all drivers are in the current queue
      final missingDrivers = driverIds.where((id) => !currentQueue.contains(id)).toList();
      
      if (missingDrivers.isEmpty) {
        print('   ✅ Queue is already consolidated - all drivers present');
        return;
      }
      
      print('   ⚠️ Found ${missingDrivers.length} drivers not in queue: $missingDrivers');
      
      // Consolidate: Add missing drivers to the end of queue
      final consolidatedQueue = [...currentQueue];
      for (final driverId in missingDrivers) {
        if (!consolidatedQueue.contains(driverId)) {
          consolidatedQueue.add(driverId);
        }
      }
      
      // Update queue document with consolidated list
      await _firestore
          .collection('system')
          .doc('queues')
          .collection('barangays')
          .doc(barangayId)
          .set({
            'drivers': consolidatedQueue,
            'barangayId': barangayId,
            'updatedAt': FieldValue.serverTimestamp(),
            'consolidatedAt': FieldValue.serverTimestamp(),
          });
      
      // Update queue positions for all drivers
      final batch = _firestore.batch();
      for (int i = 0; i < consolidatedQueue.length; i++) {
        batch.update(
          _firestore.collection('users').doc(consolidatedQueue[i]),
          {'queuePosition': i + 1},
        );
      }
      await batch.commit();
      
      print('✅ [consolidateQueueForBarangay] Queue consolidated for $barangayId');
      print('   Consolidated queue: ${consolidatedQueue.length} drivers');
    } catch (e) {
      print('❌ Error consolidating queue for barangay: $e');
      rethrow;
    }
  }

  /// Consolidate queues for ALL barangays
  /// Call this as an admin maintenance function to fix any split queues across the system
  Future<void> consolidateAllQueues() async {
    try {
      print('🔧 [consolidateAllQueues] Starting consolidation for all barangays...');
      
      // Get all barangays
      final barangaysSnapshot = await _firestore.collection('barangays').get();
      
      for (final barangayDoc in barangaysSnapshot.docs) {
        final barangayId = barangayDoc.id;
        try {
          await consolidateQueueForBarangay(barangayId);
        } catch (e) {
          print('   ⚠️ Error consolidating queue for $barangayId: $e');
        }
      }
      
      print('✅ [consolidateAllQueues] All queues consolidated');
    } catch (e) {
      print('❌ Error consolidating all queues: $e');
      rethrow;
    }
  }

  // ============ GCASH QR CODE MANAGEMENT ============

  /// Upload GCash QR code image bytes to Firestore as base64 (no Firebase Storage needed)
  Future<String> uploadGcashQrImageBytes(Uint8List imageBytes, String adminId) async {
    try {
      print('📤 Starting GCash QR image upload to Firestore...');
      print('   Image size: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Convert image bytes to base64
      final base64Image = base64Encode(imageBytes);
      print('   Base64 encoded: ${(base64Image.length / 1024).toStringAsFixed(2)} KB');
      
      // Prefix with data URI so UI components can render it as memory image
      final dataUri = 'data:image/png;base64,$base64Image';
      print('✅ Image converted to base64 successfully (data URI length: ${dataUri.length})');
      return dataUri;
    } catch (e) {
      print('❌ Error converting image: $e');
      rethrow;
    }
  }

  /// Save GCash QR code information to Firestore
  Future<void> saveGcashQrCode({
    required String qrImageUrl,
    required String accountName,
    required String accountNumber,
    required String uploadedBy,
    required String uploadedByName,
  }) async {
    try {
      await _firestore.collection('gcash_qr_codes').add({
        'qrImageUrl': qrImageUrl,
        'accountName': accountName,
        'accountNumber': accountNumber,
        'uploadedBy': uploadedBy,
        'uploadedByName': uploadedByName,
        'uploadedAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });
      
      print('✅ GCash QR code saved to Firestore');
    } catch (e) {
      print('❌ Error saving GCash QR code: $e');
      rethrow;
    }
  }

  /// Get all active GCash QR codes
  Stream<List<GcashQrModel>> getActiveGcashQrCodes() {
    print('🔍 Getting active GCash QR codes...');
    return _firestore
        .collection('gcash_qr_codes')
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          print('🔍 Snapshot received with ${snapshot.docs.length} documents');
          final activeQrCodes = snapshot.docs
              .where((doc) => doc['isActive'] == true)
              .map((doc) {
                print('🔍 Processing QR code: ${doc.id}');
                return GcashQrModel.fromFirestore(doc);
              })
              .toList();
          print('🔍 Active QR codes found: ${activeQrCodes.length}');
          return activeQrCodes;
        });
  }

  /// Deactivate a GCash QR code
  Future<void> deactivateGcashQrCode(String qrCodeId) async {
    try {
      await _firestore.collection('gcash_qr_codes').doc(qrCodeId).update({
        'isActive': false,
        'deactivatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ GCash QR code deactivated: $qrCodeId');
    } catch (e) {
      print('❌ Error deactivating GCash QR code: $e');
      rethrow;
    }
  }

  /// Get all notifications for a user (membership expiration, etc.)
  Stream<List<Map<String, dynamic>>> getNotificationsForUser(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => {
                    ...doc.data(),
                    'id': doc.id,
                  })
              .toList();
        });
  }

  // ============ PAYMENT PROOF UPLOAD ============

  /// Compress and convert payment proof image to base64 and save to Firestore
  Future<void> uploadPaymentProofImage(Uint8List imageBytes, String driverId) async {
    try {
      print('📤 Processing payment proof image for driver: $driverId');
      print('   Original size: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Compress image if needed
      Uint8List compressedBytes = imageBytes;
      
      // If image is larger than 500KB, compress it
      if (imageBytes.length > 500 * 1024) {
        print('🔄 Compressing image in background...');
        
        // Use compute to run compression in a background isolate
        // This prevents the UI from freezing on large images
        compressedBytes = await compute(_compressImageStatic, imageBytes);
        
        print('✅ Image compressed: ${(compressedBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
      }
      
      // Check if still too large
      if (compressedBytes.length > 900 * 1024) {
        throw Exception('Image is still too large (${(compressedBytes.length / 1024 / 1024).toStringAsFixed(2)} MB). Please use a smaller image.');
      }
      
      // Convert to base64 with data URI prefix for easier rendering
      final base64String = base64Encode(compressedBytes);
      final dataUri = 'data:image/jpeg;base64,$base64String';
      
      print('✅ Image converted to base64: ${(dataUri.length / 1024).toStringAsFixed(2)} KB');
      
      // Save to Firestore
      await _firestore.collection('users').doc(driverId).update({
        'paymentProofImageBase64': dataUri,
        'paymentProofUploadedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ Payment proof saved to Firestore for driver: $driverId');
    } catch (e) {
      print('❌ Error uploading payment proof image: $e');
      rethrow;
    }
  }

  /// Static helper for image compression to be used with compute()
  static Uint8List _compressImageStatic(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // Resize to max 800px width (maintain aspect ratio)
    final resized = img.copyResize(
      image,
      width: 800,
      height: (image.height * 800 ~/ image.width),
      interpolation: img.Interpolation.linear,
    );

    // Encode as JPEG with quality 80
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  /// Static helper for document compression (plate, license) to be used with compute()
  static Uint8List _compressDocumentStatic(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // Resize to max 1200px width (maintain aspect ratio)
    final resized = img.copyResize(
      image,
      width: 1200,
      height: (image.height * 1200 ~/ image.width),
      interpolation: img.Interpolation.linear,
    );

    // Encode as JPEG with quality 85 for better document clarity
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  /// Get payment proof for a driver (returns base64 string)
  Future<String?> getPaymentProof(String driverId) async {
    try {
      final doc = await _firestore.collection('users').doc(driverId).get();
      return doc.data()?['paymentProofImageBase64'] as String?;
    } catch (e) {
      print('❌ Error getting payment proof: $e');
      return null;
    }
  }
}
