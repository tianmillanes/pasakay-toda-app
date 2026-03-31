/**
 * Firestore System Collection Initialization Script
 * 
 * This script initializes the required system documents in Firestore.
 * Run this ONCE as an admin user to set up the system collection.
 * 
 * Usage:
 * 1. Install dependencies: npm install firebase-admin
 * 2. Download your Firebase service account key from Firebase Console
 * 3. Save it as 'serviceAccountKey.json' in the scripts folder
 * 4. Run: node initialize_firestore.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function initializeSystemCollection() {
  console.log('🚀 Starting Firestore system collection initialization...\n');

  try {
    // 1. Initialize Barangay Geofence
    console.log('🗺️  Creating barangay geofence...');
    await db.collection('system').doc('geofence').set({
      coordinates: [
        { lat: 14.6020, lng: 120.9850 },
        { lat: 14.6040, lng: 120.9870 },
        { lat: 14.6060, lng: 120.9890 },
        { lat: 14.6050, lng: 120.9910 },
        { lat: 14.6030, lng: 120.9890 },
        { lat: 14.6010, lng: 120.9870 },
      ],
      name: 'Service Area',
      type: 'barangay',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ Barangay geofence created\n');

    // 2. Initialize Terminal Geofence
    console.log('🏢 Creating terminal geofence...');
    await db.collection('system').doc('terminal_geofence').set({
      coordinates: [
        { lat: 14.6020, lng: 120.9850 },
        { lat: 14.6025, lng: 120.9845 },
        { lat: 14.6030, lng: 120.9855 },
        { lat: 14.6025, lng: 120.9860 },
        { lat: 14.6015, lng: 120.9855 },
      ],
      name: 'TODA Terminal',
      type: 'terminal',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ Terminal geofence created\n');

    // 3. Initialize Maintenance Mode
    console.log('🔧 Creating maintenance mode settings...');
    await db.collection('system').doc('maintenance').set({
      enabled: false,
      message: 'System is under maintenance. Please try again later.',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ Maintenance mode settings created\n');

    // 4. Initialize Driver Queue
    console.log('🚗 Creating driver queue...');
    await db.collection('system').doc('queue').set({
      drivers: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ Driver queue created\n');

    // 5. Initialize System Settings
    console.log('⚙️  Creating system settings...');
    await db.collection('system').doc('settings').set({
      baseFare: 15.0,
      farePerKm: 8.0,
      minimumFare: 15.0,
      maxWaitTime: 300, // 5 minutes in seconds
      driverTrackingInterval: 10, // seconds
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ System settings created\n');

    console.log('🎉 System collection initialization complete!');
    console.log('\n📋 Summary:');
    console.log('   ✓ Barangay geofence');
    console.log('   ✓ Terminal geofence');
    console.log('   ✓ Maintenance mode');
    console.log('   ✓ Driver queue');
    console.log('   ✓ System settings');
    console.log('\n✨ Your app is now ready to use!\n');

  } catch (error) {
    console.error('❌ Error initializing system collection:', error);
    process.exit(1);
  }

  process.exit(0);
}

// Run initialization
initializeSystemCollection();
