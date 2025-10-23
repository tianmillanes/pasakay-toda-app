# 🚀 Cloud Functions Deployment Guide

## ✅ What's Already Done

Your Cloud Functions are now configured to send push notifications when passengers book rides!

## 📋 Deployment Steps

### Step 1: Build the Functions

Open a terminal in the project root and run:

```bash
cd functions
npm run build
```

This compiles the TypeScript code to JavaScript.

### Step 2: Deploy to Firebase

Make sure you're logged in to Firebase:

```bash
npx firebase-tools login
```

Then deploy the functions:

```bash
npm run deploy
```

Or from the project root:

```bash
cd functions
npx firebase-tools deploy --only functions
```

### Step 3: Verify Deployment

After deployment, you should see:

```
✔ functions[sendRideNotification] Successful create operation.
Function URL (sendRideNotification): https://...
```

## 🎯 How It Works

1. **Passenger books ride** → Flutter app creates ride
2. **Firestore service** creates document in `notification_requests` collection
3. **Cloud Function** automatically triggers
4. **Function reads** driver's FCM token from Firestore
5. **FCM notification sent** to driver's phone
6. **Driver receives notification** even if app is closed! 🎉

## 💰 Cost

Firebase Cloud Functions **FREE TIER**:
- ✅ **2 million invocations/month**
- ✅ **400,000 GB-seconds**
- ✅ **200,000 CPU-seconds**
- ✅ **5GB outbound networking**

For a ride-booking app, this is **more than enough**!

**Estimated cost for 1000 rides/month**: **$0.00** (well within free tier)

## 🧪 Testing

### Test 1: Check Function is Deployed

```bash
npx firebase-tools functions:list
```

You should see `sendRideNotification` listed.

### Test 2: View Live Logs

```bash
npm run logs
```

Or:

```bash
npx firebase-tools functions:log
```

### Test 3: Book a Test Ride

1. Open your app as passenger
2. Book a ride
3. Watch the Firebase Console or logs
4. Driver should receive notification!

## 📊 Monitor Your Functions

### Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click "Functions" in the left menu
4. You'll see:
   - **Invocations** - How many times function ran
   - **Execution time** - How long it took
   - **Memory usage** - RAM used
   - **Errors** - Any failures

### View Logs

In Firebase Console → Functions → Logs, you'll see:

```
🔔 New notification request
   requestId: abc123
   targetUserId: driver456
   title: 🚗 New Ride Request!

📤 Sending FCM notification
   token: A1B2C3...

✅ Notification sent successfully
```

## 🐛 Troubleshooting

### "Functions not found"

Run: `npm run build` then `npm run deploy`

### "Insufficient permissions"

Make sure you're logged in: `npx firebase-tools login`

### "Build failed"

```bash
cd functions
npm install
npm run build
```

### Notifications not sending

1. Check Firebase Console → Functions → Logs for errors
2. Verify driver has `fcmToken` in Firestore
3. Check `notification_requests` collection is being created
4. Ensure function is deployed: `npx firebase-tools functions:list`

## 📱 Test Notifications Manually

You can manually create a test notification in Firestore:

1. Go to Firebase Console → Firestore
2. Open `notification_requests` collection
3. Add a document:

```javascript
{
  targetUserId: "driver_user_id_here",
  title: "🚗 Test Ride Request!",
  body: "From: Test Pickup to Test Destination",
  data: {
    type: "ride_request",
    rideId: "test123",
    passengerName: "Test User"
  },
  processed: false,
  createdAt: [Timestamp: now]
}
```

4. Watch the driver's phone - notification should appear!
5. Check the document - `processed` should become `true`

## 🔄 Update Functions

After making changes to `functions/src/index.ts`:

```bash
cd functions
npm run build
npm run deploy
```

## 🎉 You're Done!

Your push notification system is now live! When passengers book rides:

1. ✅ Driver gets notification instantly
2. ✅ Works even if app is closed
3. ✅ Works even if phone is locked
4. ✅ Completely FREE (within limits)

## 📚 Additional Resources

- [Firebase Functions Docs](https://firebase.google.com/docs/functions)
- [FCM Admin SDK](https://firebase.google.com/docs/cloud-messaging/admin)
- [Monitor Functions](https://firebase.google.com/docs/functions/monitoring)

---

**Need help?** Check the logs in Firebase Console! 🚀
