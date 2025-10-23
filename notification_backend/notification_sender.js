/**
 * FREE Push Notification Backend Service
 * 
 * This Node.js script watches Firestore for new notification requests
 * and sends FCM notifications to users. Run this on any free hosting:
 * - Railway.app (free tier)
 * - Render.com (free tier)
 * - Heroku (free tier with GitHub Student Pack)
 * - Your own computer/VPS
 * 
 * Setup:
 * 1. npm install firebase-admin
 * 2. Download service account key from Firebase Console
 * 3. Place serviceAccountKey.json in this directory
 * 4. Run: node notification_sender.js
 */

const admin = require('firebase-admin');
const path = require('path');

// Initialize Firebase Admin SDK
try {
  const serviceAccount = require('./serviceAccountKey.json');
  
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  
  console.log('✅ Firebase Admin initialized successfully');
} catch (error) {
  console.error('❌ Error initializing Firebase Admin:', error);
  console.error('Make sure serviceAccountKey.json exists in this directory');
  process.exit(1);
}

const db = admin.firestore();
const messaging = admin.messaging();

console.log('🔔 Notification sender started...');
console.log('👀 Watching for new notification requests...');

// Watch for new notification requests
const unsubscribe = db.collection('notification_requests')
  .where('processed', '==', false)
  .onSnapshot(async (snapshot) => {
    console.log(`📨 Received ${snapshot.docChanges().length} changes`);
    
    for (const change of snapshot.docChanges()) {
      if (change.type === 'added') {
        const notificationDoc = change.doc;
        const notification = notificationDoc.data();
        
        console.log('\n📬 New notification request:', notificationDoc.id);
        console.log('   Target User:', notification.targetUserId);
        console.log('   Title:', notification.title);
        console.log('   Body:', notification.body);
        
        try {
          // Get user's FCM token
          const userDoc = await db.collection('users').doc(notification.targetUserId).get();
          
          if (!userDoc.exists) {
            console.error('   ❌ User not found:', notification.targetUserId);
            await notificationDoc.ref.update({
              processed: true,
              error: 'User not found',
              processedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            continue;
          }
          
          const userData = userDoc.data();
          const fcmToken = userData.fcmToken;
          
          if (!fcmToken) {
            console.error('   ❌ No FCM token found for user:', notification.targetUserId);
            await notificationDoc.ref.update({
              processed: true,
              error: 'No FCM token',
              processedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            continue;
          }
          
          console.log('   🔑 FCM Token:', fcmToken.substring(0, 20) + '...');
          
          // Prepare FCM message
          const message = {
            token: fcmToken,
            notification: {
              title: notification.title,
              body: notification.body,
            },
            data: notification.data || {},
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
                channelId: 'ride_requests',
                priority: 'high',
                defaultSound: true,
                defaultVibrateTimings: true,
              }
            },
            apns: {
              payload: {
                aps: {
                  contentAvailable: true,
                  sound: 'default',
                  badge: 1,
                }
              }
            }
          };
          
          // Send notification via FCM
          console.log('   📤 Sending FCM notification...');
          const response = await messaging.send(message);
          console.log('   ✅ Notification sent successfully:', response);
          
          // Mark as processed
          await notificationDoc.ref.update({
            processed: true,
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
            fcmResponse: response
          });
          
          console.log('   ✅ Marked as processed');
          
        } catch (error) {
          console.error('   ❌ Error sending notification:', error);
          
          // Mark as processed with error
          await notificationDoc.ref.update({
            processed: true,
            error: error.message,
            errorCode: error.code,
            processedAt: admin.firestore.FieldValue.serverTimestamp()
          });
        }
      }
    }
  }, (error) => {
    console.error('❌ Error watching notifications:', error);
  });

// Cleanup function for graceful shutdown
function cleanup() {
  console.log('\n🛑 Shutting down notification sender...');
  unsubscribe();
  process.exit(0);
}

// Handle shutdown signals
process.on('SIGINT', cleanup);
process.on('SIGTERM', cleanup);

// Keep alive message every 5 minutes
setInterval(() => {
  console.log('💓 Service is running... Watching for notifications');
}, 5 * 60 * 1000);

console.log('✅ Service is now running and watching for notification requests');
console.log('Press Ctrl+C to stop\n');
