# 🔑 How to Get Firebase Service Account Key

## Step 1: Go to Firebase Console

1. Open: https://console.firebase.google.com/
2. Select your project: **pasakay-toda-dispatch**

## Step 2: Navigate to Service Accounts

1. Click the **⚙️ gear icon** (top left)
2. Click **Project settings**
3. Go to the **"Service accounts"** tab

## Step 3: Generate Key

1. Click **"Generate new private key"** button
2. Click **"Generate key"** in the confirmation dialog
3. A JSON file will download (e.g., `pasakay-toda-dispatch-firebase-adminsdk-xxxxx.json`)

## Step 4: Save the Key

1. **Rename** the downloaded file to: `serviceAccountKey.json`
2. **Move** it to: `E:\toda\originalpasakaytoda - Copy\toda\notification_backend\`
3. **IMPORTANT**: Never commit this file to Git!

## Step 5: Run the Service

```bash
cd E:\toda\originalpasakaytoda - Copy\toda\notification_backend
npm start
```

You should see:
```
✅ Firebase Admin initialized successfully
🔔 Notification sender started...
👀 Watching for new notification requests...
```

## ✅ That's It!

Now when passengers book rides, this service will:
1. Watch Firestore for new notification requests
2. Send FCM push notifications to drivers
3. Mark requests as processed

## 🌐 Deploy to Free Hosting (Optional)

Once it works locally, deploy to **Railway.app** (500 hours/month FREE):

1. Create account: https://railway.app
2. Click "New Project"
3. Choose "Deploy from GitHub"
4. Connect your repo
5. Add `serviceAccountKey.json` as secret file
6. Deploy!

Or keep it running on your computer - it's fine! 💻
