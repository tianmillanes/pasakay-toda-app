# 🚀 Pasakay Stress Testing Guide (Free & Unlimited)

This guide explains how to stress test the Pasakay app without hitting Firebase daily limits or incurring any billing costs. We achieve this by using the **Firebase Local Emulator Suite**.

---

## 1. Prerequisites
- **Firebase CLI** installed (`npm install -g firebase-tools`)
- **Java JRE** installed (Required for emulators)
- **ADB** (Android Debug Bridge) installed and added to PATH

---

## 2. Setting up the Local Backend (Emulator)
We run a "fake" Firebase on our local machine.

1.  Open `firebase.json` in the project root and ensure it includes the `emulators` block:
    ```json
    {
      "firestore": {
        "rules": "firestore.rules"
      },
      "emulators": {
        "auth": { "port": 9099 },
        "firestore": { "port": 8080 },
        "ui": { "enabled": true, "port": 4000 }
      }
    }
    ```
2.  Start the emulators:
    ```bash
    firebase emulators:start
    ```
3.  You can view the local database at `http://localhost:4000`.

---

## 3. Configuring the Flutter App
We must tell the app to connect to `localhost` (or `10.0.2.2` for Android) instead of the real Firebase servers.

In `lib/main.dart`, add this logic inside `void main()` after `Firebase.initializeApp()`:

```dart
if (kDebugMode) {
  // 10.0.2.2 is the IP Android emulators use to reach your host PC
  String host = defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
  
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  
  print('✅ STRESS TEST MODE: Connected to Local Emulators');
}
```

---

## 4. Running the Stress Test (ADB Monkey)
Once the app is running on your emulator and connected to the local backend, you can start the "Monkey Test." This simulates thousands of random user interactions per minute.

1.  Connect your Android emulator/device.
2.  Run the following command in your terminal:
    ```bash
    # Sends 10,000 random events to the app with a 10ms delay between them
    adb shell monkey -p com.toda.transport.booking --throttle 10 -v 10000
    ```

---

## 5. Why use this method?
- **Zero Cost:** No Firebase reads/writes are charged.
- **No Limits:** You won't hit the "50k free reads" daily limit.
- **Safe:** You can fill the local database with millions of junk records for testing, then just reset the emulator.
- **Performance:** You can find UI crashes and memory leaks before they reach real users.

---
*Created for the Pasakay Development Team.*
