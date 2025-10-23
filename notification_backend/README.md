# 🔔 Notification Backend Service (FREE)

This is a simple Node.js backend service that sends push notifications to drivers when passengers book rides. It's completely **FREE** and doesn't require Firebase Cloud Functions paid plan.

## 🚀 Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Get Firebase Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click the gear icon ⚙️ → Project Settings
4. Go to "Service Accounts" tab
5. Click "Generate New Private Key"
6. Save the downloaded file as `serviceAccountKey.json` in this directory

⚠️ **IMPORTANT**: Never commit `serviceAccountKey.json` to version control!

### 3. Run the Service

```bash
npm start
```

You should see:
```
✅ Firebase Admin initialized successfully
🔔 Notification sender started...
👀 Watching for new notification requests...
✅ Service is now running and watching for notification requests
```

## 🌐 Deploy to Free Hosting

### Option 1: Railway.app (Recommended)

1. Create account at [railway.app](https://railway.app)
2. Click "New Project" → "Deploy from GitHub"
3. Connect your repository
4. Set environment variable (if storing key in env):
   - Add `FIREBASE_SERVICE_ACCOUNT` with your key content
5. Deploy!

**Free Tier**: 500 hours/month, $5 credit

### Option 2: Render.com

1. Create account at [render.com](https://render.com)
2. Click "New" → "Background Worker"
3. Connect GitHub repository
4. Build command: `npm install`
5. Start command: `npm start`
6. Add secret files (serviceAccountKey.json)
7. Deploy!

**Free Tier**: 750 hours/month

### Option 3: Your Own Server/Computer

Just run `npm start` on any computer/VPS that stays online.

## 📊 How It Works

1. **Flutter app** creates a document in Firestore collection `notification_requests`
2. **This backend** watches for new documents in that collection
3. When a new request appears, it:
   - Gets the target user's FCM token from Firestore
   - Sends push notification via Firebase Admin SDK
   - Marks the request as processed

## 🔧 Configuration

### Environment Variables (Optional)

If you want to use environment variables instead of serviceAccountKey.json:

Create `.env` file:
```env
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n..."
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
```

Then modify `notification_sender.js`:
```javascript
require('dotenv').config();

admin.initializeApp({
  credential: admin.credential.cert({
    projectId: process.env.FIREBASE_PROJECT_ID,
    privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
  })
});
```

## 📝 Firestore Structure

The service watches this collection:

**Collection**: `notification_requests`

**Document Structure**:
```javascript
{
  targetUserId: "driver123",      // User ID to send notification to
  title: "🚗 New Ride Request!",  // Notification title
  body: "From: A to B",           // Notification body
  data: {                          // Additional data
    type: "ride_request",
    rideId: "ride456",
    passengerName: "John Doe",
    // ... other data
  },
  processed: false,                // Processing status
  createdAt: Timestamp
}
```

After processing:
```javascript
{
  // ... original fields ...
  processed: true,
  processedAt: Timestamp,
  fcmResponse: "projects/xxx/messages/yyy"  // FCM response
}
```

## 🐛 Troubleshooting

### "Cannot find module 'firebase-admin'"

Run: `npm install`

### "serviceAccountKey.json not found"

Make sure you downloaded the service account key and placed it in this directory.

### Notifications not being sent

1. Check if the service is running (look for heartbeat logs every 5 minutes)
2. Check Firestore `notification_requests` collection - are documents being created?
3. Check if `processed` field is being set to `true`
4. Check user documents - do they have `fcmToken` field?

### Service crashes on cloud hosting

- Make sure to add `serviceAccountKey.json` as a secret file
- Check deployment logs for errors
- Ensure Node.js version is compatible (use Node 18+)

## 💰 Cost Comparison

| Solution | Cost | Setup Difficulty |
|----------|------|------------------|
| This Backend (Railway/Render) | **FREE** ⭐ | Easy |
| Firebase Cloud Functions | Free tier available* | Medium |
| Dedicated VPS | $5-10/month | Medium |
| Your own computer | **FREE** | Very Easy |

*Cloud Functions free tier: 2M invocations/month (usually enough)

## 🎯 Alternative: Use Cloud Functions Free Tier

Firebase Cloud Functions **does have a generous free tier**! If you prefer serverless:

1. Run `firebase init functions`
2. Create `functions/index.js`:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendNotification = functions.firestore
  .document('notification_requests/{requestId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(notification.targetUserId)
      .get();
    
    const fcmToken = userDoc.data().fcmToken;
    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: notification.title,
          body: notification.body
        },
        data: notification.data
      });
      await snap.ref.update({ processed: true });
    }
  });
```

3. Deploy: `firebase deploy --only functions`

## 📚 Resources

- [Firebase Admin SDK](https://firebase.google.com/docs/admin/setup)
- [FCM Send Messages](https://firebase.google.com/docs/cloud-messaging/send-message)
- [Railway.app Docs](https://docs.railway.app/)
- [Render Docs](https://render.com/docs)

---

**Now you have FREE push notifications! 🎉**
