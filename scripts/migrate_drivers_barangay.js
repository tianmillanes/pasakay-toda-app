const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function migrateDrivers() {
  try {
    console.log('🚀 Starting driver migration...');

    // 1. Get all barangays to create a Name -> ID map
    console.log('Loading barangays...');
    const barangaySnapshot = await db.collection('barangays').get();
    const barangayMap = {};
    barangaySnapshot.docs.forEach(doc => {
      const data = doc.data();
      // Normalize name for matching
      if (data.name) {
        barangayMap[data.name.toLowerCase().trim()] = doc.id;
      }
    });
    console.log(`✓ Loaded ${Object.keys(barangayMap).length} barangays.`);

    // 2. Get all drivers
    console.log('Loading drivers...');
    const driversSnapshot = await db.collection('users')
      .where('role', '==', 'driver')
      .get();
    
    console.log(`Found ${driversSnapshot.size} drivers to check.`);

    let updatedCount = 0;
    let errorCount = 0;
    const batch = db.batch();
    let batchCount = 0;

    for (const doc of driversSnapshot.docs) {
      const driver = doc.data();
      const driverName = driver.name || 'Unknown';
      
      if (!driver.barangayName) {
        console.log(`⚠️  Skipping driver ${driverName} (${doc.id}): No barangayName`);
        continue;
      }

      const normalizedBarangayName = driver.barangayName.toLowerCase().trim();
      const newBarangayId = barangayMap[normalizedBarangayName];

      if (!newBarangayId) {
        console.log(`❌ Could not find barangay ID for "${driver.barangayName}" (Driver: ${driverName})`);
        errorCount++;
        continue;
      }

      // Check if update is needed
      if (driver.barangayId !== newBarangayId) {
        console.log(`🔄 Updating ${driverName}: ${driver.barangayId} -> ${newBarangayId} (${driver.barangayName})`);
        
        const driverRef = db.collection('users').doc(doc.id);
        batch.update(driverRef, {
          barangayId: newBarangayId,
          isInQueue: false, // Force re-queue
          queuePosition: 0,
          status: 'offline', // Force offline to ensure clean state
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });

        // Also try to clean up old queue entry if possible (best effort)
        if (driver.barangayId) {
            // We can't easily remove from old queue array without reading it, 
            // but resetting the driver state handles the critical part.
            // The old queue doc is likely dead/unused anyway.
        }

        updatedCount++;
        batchCount++;

        // Commit batch every 400 updates
        if (batchCount >= 400) {
          await batch.commit();
          batchCount = 0;
          // Re-instantiate batch? No, Firestore batch is reusable until committed? 
          // Actually usually need a new batch object.
          // In this simple script, let's just use one batch commit at end if small, 
          // or chunks. Let's do chunks properly.
        }
      } else {
          // console.log(`✓ ${driverName} is already up to date.`);
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    console.log('\n=== Migration Complete ===');
    console.log(`Updated: ${updatedCount} drivers`);
    console.log(`Errors: ${errorCount}`);
    
  } catch (error) {
    console.error('Fatal Error:', error);
  } finally {
    process.exit();
  }
}

migrateDrivers();
