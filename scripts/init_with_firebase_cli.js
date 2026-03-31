/**
 * Initialize Firestore using Firebase CLI credentials
 * This uses your existing Firebase login instead of service account
 */

const admin = require('firebase-admin');

// Initialize WITHOUT service account - will use application default credentials
try {
  admin.initializeApp({
    projectId: 'pasakay-toda-dispatch'
  });
} catch (e) {
  console.log('Firebase already initialized');
}

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
    console.error('❌ Error initializing system collection:', error.message);
    console.error('\n💡 Make sure you are logged in to Firebase CLI:');
    console.error('   Run: firebase login');
    console.error('   Then run this script again\n');
    process.exit(1);
  }

  process.exit(0);
}

// Run initialization
initializeSystemCollection();
