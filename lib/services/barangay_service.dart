import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/barangay_model.dart';

class BarangayService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'barangays';
  static bool _initializationInProgress = false;

  /// The static list of 41 barangays for Concepcion, Tarlac (after exclusions)
  static const List<String> staticBarangays = [
    'Alfonso', 'Balutu', 'Cafe', 'Calius Gueco', 'Caluluan',
    'Castillo', 'Corazon de Jesus', 'Culatingan', 'Dutung-A-Matas (Jefmin)',
    'Green Village', 'Lilibangan', 'Mabilog', 'Magao',
    'Malupa', 'Minane', 'Panalicsican', 'Pando',
    'Parang', 'Parulung', 'Pitabunan', 'San Agustin (Murcia)',
    'San Antonio', 'San Bartolome', 'San Francisco', 'San Isidro (Almendras)',
    'San Jose (Poblacion)', 'San Juan (Castro)', 'San Nicolas Balas',
    'San Nicolas (Poblacion)', 'Sta. Cruz', 'Sta. Maria',
    'Sta. Monica', 'Sta. Rita', 'Santa Rosa', 'Santiago',
    'Santo Cristo', 'Santo Niño', 'Santo Rosario (Magunting)',
    'San Vicente (Calius/Corba)', 'Talimunduc San Miguel', 'Tinang'
  ];

  /// Get all barangays
  Future<List<BarangayModel>> getAllBarangays() async {
    try {
      // Fetch without orderBy to avoid index requirement
      final snapshot = await _firestore
          .collection(_collection)
          .get()
          .timeout(const Duration(seconds: 15));

      // Fetched ${snapshot.docs.length} barangays from Firestore

      // Sort by name in Dart instead of Firestore
      final barangays = snapshot.docs.map((doc) {
        final barangay = BarangayModel.fromFirestore(doc);
        return barangay;
      }).toList();

      // Deduplicate by name (keep the one with 'barangay_' ID if conflict)
      final uniqueBarangaysMap = <String, BarangayModel>{};
      for (var b in barangays) {
        final name = b.name.trim(); // Case-sensitive or insensitive? Let's assume consistent casing
        
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
      
      final uniqueBarangays = uniqueBarangaysMap.values.toList();

      // Sort alphabetically by name
      uniqueBarangays.sort((a, b) => a.name.compareTo(b.name));

      // Total unique barangays: ${uniqueBarangays.length}
      return uniqueBarangays;
    } catch (e) {
      // Error fetching barangays: $e
      return [];
    }
  }

  /// Get barangays by municipality
  Future<List<BarangayModel>> getBarangaysByMunicipality(
    String municipality,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .where('municipality', isEqualTo: municipality)
          .get();

      return snapshot.docs
          .map((doc) => BarangayModel.fromFirestore(doc))
          .where((barangay) => barangay.isActive)
          .toList();
    } catch (e) {
      // Error fetching barangays by municipality: $e
      return [];
    }
  }

  /// Get barangay by ID
  Future<BarangayModel?> getBarangayById(String barangayId) async {
    try {
      final doc = await _firestore
          .collection(_collection)
          .doc(barangayId)
          .get();

      if (doc.exists) {
        return BarangayModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      // Error fetching barangay: $e
      return null;
    }
  }

  /// Create a new barangay
  Future<String?> createBarangay(BarangayModel barangay) async {
    try {
      final docRef = await _firestore
          .collection(_collection)
          .add(barangay.toFirestore());
      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  /// Update barangay
  Future<bool> updateBarangay(String barangayId, BarangayModel barangay) async {
    try {
      await _firestore
          .collection(_collection)
          .doc(barangayId)
          .update(barangay.toFirestore());
      return true;
    } catch (e) {
      // Error updating barangay: $e
      return false;
    }
  }

  /// Get barangays as stream
  Stream<List<BarangayModel>> getBarangaysStream() {
    return _firestore.collection(_collection).snapshots().map((snapshot) {
      final barangays = snapshot.docs
          .map((doc) => BarangayModel.fromFirestore(doc))
          .toList();
      // Sort by name in Dart
      barangays.sort((a, b) => a.name.compareTo(b.name));
      return barangays;
    });
  }

  /// Initialize barangays and fix duplicates
  /// This method ensures that we don't have duplicate barangay names
  /// and that all required barangays exist.
  Future<void> initializeBarangays() async {
    // Prevent multiple concurrent initializations
    if (_initializationInProgress) {
      // Barangay initialization already in progress, skipping...
      return;
    }

    _initializationInProgress = true;

    try {
      // Checking for barangay duplicates and missing entries...
      
      // Fetch all existing barangays
      final snapshot = await _firestore
          .collection(_collection)
          .get()
          .timeout(const Duration(seconds: 15));

      final batch = _firestore.batch();
      bool changesMade = false;
      int duplicatesRemoved = 0;
      int addedCount = 0;

      // Map to group docs by name (normalized)
      final Map<String, List<DocumentSnapshot>> nameToDocs = {};
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        // Handle potential missing name field
        final name = (data['name'] as String? ?? '').toLowerCase().trim();
        if (name.isEmpty) continue;
        
        if (!nameToDocs.containsKey(name)) {
          nameToDocs[name] = [];
        }
        nameToDocs[name]!.add(doc);
      }

      // 1. Remove duplicates
      for (var name in nameToDocs.keys) {
        final docs = nameToDocs[name]!;
        
        if (docs.length > 1) {
          // Found ${docs.length} duplicates for "$name"
          
          // Sort to prioritize keeping the one with correct ID format ('barangay_')
          // or the one with most recent update/creation if IDs are similar
          docs.sort((a, b) {
            final aId = a.id;
            final bId = b.id;
            final aIsFixed = aId.startsWith('barangay_');
            final bIsFixed = bId.startsWith('barangay_');
            
            if (aIsFixed && !bIsFixed) return -1; // Keep a (comes first)
            if (!aIsFixed && bIsFixed) return 1;  // Keep b (comes first)
            return 0;
          });

          // Keep the first one, delete the rest
          for (var i = 1; i < docs.length; i++) {
            // Deleting duplicate: ${docs[i].id} (${docs[i].get('name')})
            batch.delete(docs[i].reference);
            duplicatesRemoved++;
            changesMade = true;
          }
        }
      }

      // 2. Add missing barangays
      final targetBarangays = _getConceptionBarangays();
      for (var target in targetBarangays) {
        final targetName = target.name.toLowerCase().trim();
        
        if (!nameToDocs.containsKey(targetName)) {
          // Adding missing barangay: ${target.name}
          // Use the specific ID from the model
          final docRef = _firestore.collection(_collection).doc(target.id);
          batch.set(docRef, target.toFirestore());
          addedCount++;
          changesMade = true;
        }
      }

      if (changesMade) {
        await batch.commit();
        // Barangay initialization complete: Removed $duplicatesRemoved duplicates, Added $addedCount.
      } else {
        // Barangay data is clean and complete. No changes needed.
      }

    } catch (e) {
      // Barangay initialization failed: $e
    } finally {
      _initializationInProgress = false;
    }
  }

  /// Helper function to create a square geofence around a center point
  /// Radius in degrees (approximately 0.01 degree = 1.1 km)
  List<List<double>> _createGeofence(
    double lat,
    double lng, {
    double radiusDegrees = 0.01,
  }) {
    return [
      [lat + radiusDegrees, lng - radiusDegrees], // NW
      [lat + radiusDegrees, lng + radiusDegrees], // NE
      [lat - radiusDegrees, lng + radiusDegrees], // SE
      [lat - radiusDegrees, lng - radiusDegrees], // SW
      [lat + radiusDegrees, lng - radiusDegrees], // Close polygon
    ];
  }

  /// Get 45 barangays of Concepcion, Tarlac
  List<BarangayModel> _getConceptionBarangays() {
    final now = DateTime.now();
    final baseLatitude = 15.2833;
    final baseLongitude = 121.0167;

    return [
      BarangayModel(
        id: 'barangay_1',
        name: 'Alfonso',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(baseLatitude, baseLongitude),
      ),
      BarangayModel(
        id: 'barangay_2',
        name: 'Balutu',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.01,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.01,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_3',
        name: 'Cafe',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.02,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.02,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_4',
        name: 'Calius Gueco',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.03,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.03,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_6',
        name: 'Caluluan',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.05,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.05,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_7',
        name: 'Castillo',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude + 0.01,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude + 0.01,
        ),
      ),
      BarangayModel(
        id: 'barangay_8',
        name: 'Corazon de Jesus',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude + 0.02,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude + 0.02,
        ),
      ),
      BarangayModel(
        id: 'barangay_9',
        name: 'Culatingan',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude + 0.03,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude + 0.03,
        ),
      ),
      BarangayModel(
        id: 'barangay_10',
        name: 'Dungan',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude + 0.04,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude + 0.04,
        ),
      ),
      BarangayModel(
        id: 'barangay_11',
        name: 'Dutung-A-Matas (Jefmin)',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude + 0.05,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude + 0.05,
        ),
      ),
      BarangayModel(
        id: 'barangay_12',
        name: 'Green Village',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude - 0.01,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude - 0.01,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_13',
        name: 'Lilibangan',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude - 0.02,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude - 0.02,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_14',
        name: 'Mabilog',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude - 0.03,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude - 0.03,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_15',
        name: 'Magao',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude - 0.04,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude - 0.04,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_16',
        name: 'Malupa',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude - 0.05,
        longitude: baseLongitude,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude - 0.05,
          baseLongitude,
        ),
      ),
      BarangayModel(
        id: 'barangay_17',
        name: 'Minane',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude - 0.01,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude - 0.01,
        ),
      ),
      BarangayModel(
        id: 'barangay_18',
        name: 'Panalicsican',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude - 0.02,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude - 0.02,
        ),
      ),
      BarangayModel(
        id: 'barangay_19',
        name: 'Pando',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude - 0.03,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude - 0.03,
        ),
      ),
      BarangayModel(
        id: 'barangay_20',
        name: 'Parang',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude - 0.04,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude - 0.04,
        ),
      ),
      BarangayModel(
        id: 'barangay_21',
        name: 'Parulung',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude,
        longitude: baseLongitude - 0.05,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude,
          baseLongitude - 0.05,
        ),
      ),
      BarangayModel(
        id: 'barangay_22',
        name: 'Pitabunan',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.01,
        longitude: baseLongitude + 0.01,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.01,
          baseLongitude + 0.01,
        ),
      ),
      BarangayModel(
        id: 'barangay_23',
        name: 'San Agustin (Murcia)',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.02,
        longitude: baseLongitude + 0.01,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.02,
          baseLongitude + 0.01,
        ),
      ),
      BarangayModel(
        id: 'barangay_24',
        name: 'San Antonio',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.03,
        longitude: baseLongitude + 0.01,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.03,
          baseLongitude + 0.01,
        ),
      ),
      BarangayModel(
        id: 'barangay_25',
        name: 'San Bartolome',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.04,
        longitude: baseLongitude + 0.01,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.04,
          baseLongitude + 0.01,
        ),
      ),
      BarangayModel(
        id: 'barangay_26',
        name: 'San Francisco',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.05,
        longitude: baseLongitude + 0.01,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.05,
          baseLongitude + 0.01,
        ),
      ),
      BarangayModel(
        id: 'barangay_27',
        name: 'San Isidro (Almendras)',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.01,
        longitude: baseLongitude + 0.02,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.01,
          baseLongitude + 0.02,
        ),
      ),
      BarangayModel(
        id: 'barangay_28',
        name: 'San Jose (Poblacion)',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.02,
        longitude: baseLongitude + 0.02,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.02,
          baseLongitude + 0.02,
        ),
      ),
      BarangayModel(
        id: 'barangay_29',
        name: 'San Juan (Castro)',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.03,
        longitude: baseLongitude + 0.02,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.03,
          baseLongitude + 0.02,
        ),
      ),
      BarangayModel(
        id: 'barangay_30',
        name: 'San Martin',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.04,
        longitude: baseLongitude + 0.02,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.04,
          baseLongitude + 0.02,
        ),
      ),
      BarangayModel(
        id: 'barangay_31',
        name: 'San Nicolas Balas',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.05,
        longitude: baseLongitude + 0.02,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.05,
          baseLongitude + 0.02,
        ),
      ),
      BarangayModel(
        id: 'barangay_32',
        name: 'San Nicolas (Poblacion)',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.01,
        longitude: baseLongitude + 0.03,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.01,
          baseLongitude + 0.03,
        ),
      ),
      BarangayModel(
        id: 'barangay_33',
        name: 'Sta. Cruz',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.02,
        longitude: baseLongitude + 0.03,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.02,
          baseLongitude + 0.03,
        ),
      ),
      BarangayModel(
        id: 'barangay_34',
        name: 'Sta. Maria',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.03,
        longitude: baseLongitude + 0.03,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.03,
          baseLongitude + 0.03,
        ),
      ),
      BarangayModel(
        id: 'barangay_35',
        name: 'Sta. Monica',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.04,
        longitude: baseLongitude + 0.03,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.04,
          baseLongitude + 0.03,
        ),
      ),
      BarangayModel(
        id: 'barangay_36',
        name: 'Sta. Rita',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.05,
        longitude: baseLongitude + 0.03,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.05,
          baseLongitude + 0.03,
        ),
      ),
      BarangayModel(
        id: 'barangay_37',
        name: 'Santa Rosa',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.01,
        longitude: baseLongitude + 0.04,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.01,
          baseLongitude + 0.04,
        ),
      ),
      BarangayModel(
        id: 'barangay_38',
        name: 'Santiago',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.02,
        longitude: baseLongitude + 0.04,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.02,
          baseLongitude + 0.04,
        ),
      ),
      BarangayModel(
        id: 'barangay_39',
        name: 'Santo Cristo',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.03,
        longitude: baseLongitude + 0.04,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.03,
          baseLongitude + 0.04,
        ),
      ),
      BarangayModel(
        id: 'barangay_40',
        name: 'Santo Niño',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.04,
        longitude: baseLongitude + 0.04,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.04,
          baseLongitude + 0.04,
        ),
      ),
      BarangayModel(
        id: 'barangay_41',
        name: 'Santo Rosario (Magunting)',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.05,
        longitude: baseLongitude + 0.04,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.05,
          baseLongitude + 0.04,
        ),
      ),
      BarangayModel(
        id: 'barangay_42',
        name: 'San Vicente (Calius/Corba)',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.01,
        longitude: baseLongitude + 0.05,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.01,
          baseLongitude + 0.05,
        ),
      ),
      BarangayModel(
        id: 'barangay_43',
        name: 'Talimunduc Marimla',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.02,
        longitude: baseLongitude + 0.05,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.02,
          baseLongitude + 0.05,
        ),
      ),
      BarangayModel(
        id: 'barangay_44',
        name: 'Talimunduc San Miguel',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.03,
        longitude: baseLongitude + 0.05,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.03,
          baseLongitude + 0.05,
        ),
      ),
      BarangayModel(
        id: 'barangay_46',
        name: 'Tinang',
        municipality: 'Concepcion',
        province: 'Tarlac',
        latitude: baseLatitude + 0.05,
        longitude: baseLongitude + 0.05,
        createdAt: now,
        geofenceCoordinates: _createGeofence(
          baseLatitude + 0.05,
          baseLongitude + 0.05,
        ),
      ),
    ];
  }
}
