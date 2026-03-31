/**
 * Test Firebase Admin SDK connection
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function testConnection() {
  console.log('🔍 Testing Firebase Admin SDK connection...\n');
  
  try {
    // Try to read from Firestore
    console.log('📖 Attempting to read from Firestore...');
    const testDoc = await db.collection('system').doc('queue').get();
    
    if (testDoc.exists) {
      console.log('✅ Successfully connected to Firestore!');
      console.log('📄 Queue document exists');
      console.log('Data:', testDoc.data());
    } else {
      console.log('✅ Successfully connected to Firestore!');
      console.log('ℹ️  Queue document does not exist yet (this is normal)');
    }
    
    console.log('\n🎉 Connection test passed!');
    console.log('You can now run: npm run init\n');
    
  } catch (error) {
    console.error('❌ Connection test failed:', error.message);
    console.error('\n🔧 Troubleshooting:');
    console.error('1. Check that the service account has Firestore permissions');
    console.error('2. Go to: https://console.firebase.google.com/project/pasakay-toda-dispatch/settings/iam');
    console.error('3. Ensure firebase-adminsdk-fbsvc@pasakay-toda-dispatch.iam.gserviceaccount.com has "Firebase Admin" or "Cloud Datastore User" role');
    console.error('4. Download a fresh service account key if needed\n');
  }
  
  process.exit(0);
}

testConnection();
