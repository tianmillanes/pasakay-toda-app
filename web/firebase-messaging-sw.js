// Firebase Cloud Messaging Service Worker
// Version: v9 compatible

// Import Firebase scripts
importScripts('https://www.gstatic.com/firebasejs/9.15.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.15.0/firebase-messaging-compat.js');

// Firebase configuration
const firebaseConfig = {
  apiKey: "AIzaSyBTC5aLlbLs99h8q4rP8mGBDWEvpLBlpVg",
  authDomain: "pasakay-toda-dispatch.firebaseapp.com",
  projectId: "pasakay-toda-dispatch",
  storageBucket: "pasakay-toda-dispatch.firebasestorage.app",
  messagingSenderId: "563584335869",
  appId: "1:563584335869:web:2f843d05183a0b7ec81fa3",
  measurementId: "G-CTJRVR4DVC"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);

// Initialize Firebase Cloud Messaging
const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message:', payload);

  // Extract notification data
  const notificationTitle = payload.notification?.title || payload.data?.title || 'Pasakay Toda';
  const notificationOptions = {
    body: payload.notification?.body || payload.data?.body || 'New notification',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: payload.data?.type || 'ride-notification',
    requireInteraction: true,
    vibrate: [200, 100, 200],
    data: {
      ...payload.data,
      click_action: payload.notification?.click_action || payload.data?.click_action || '/',
      url: payload.data?.url || '/'
    },
    actions: []
  };

  // Add action buttons based on notification type
  if (payload.data?.type === 'ride_request') {
    notificationOptions.actions = [
      { action: 'accept', title: 'Accept', icon: '/icons/accept.png' },
      { action: 'decline', title: 'Decline', icon: '/icons/decline.png' }
    ];
  } else if (payload.data?.type === 'ride_accepted') {
    notificationOptions.actions = [
      { action: 'view', title: 'View Ride', icon: '/icons/view.png' }
    ];
  }

  // Show notification
  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle notification click events
self.addEventListener('notificationclick', (event) => {
  console.log('[firebase-messaging-sw.js] Notification clicked:', event);
  
  const notification = event.notification;
  const action = event.action;
  const data = notification.data || {};
  
  notification.close();

  // Handle action button clicks
  if (action === 'accept') {
    // Handle ride accept
    event.waitUntil(
      clients.openWindow(`/driver/ride-request/${data.rideId}?action=accept`)
    );
    return;
  }
  
  if (action === 'decline') {
    // Handle ride decline
    event.waitUntil(
      clients.openWindow(`/driver/ride-request/${data.rideId}?action=decline`)
    );
    return;
  }
  
  if (action === 'view') {
    // Handle view ride
    event.waitUntil(
      clients.openWindow(`/passenger/active-ride/${data.rideId}`)
    );
    return;
  }

  // Default click behavior
  const urlToOpen = data.click_action || data.url || '/';
  
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // Check if app is already open
        for (let i = 0; i < clientList.length; i++) {
          const client = clientList[i];
          if (client.url.includes(self.registration.scope) && 'focus' in client) {
            // Focus existing window and navigate
            return client.focus().then(() => {
              if ('navigate' in client) {
                return client.navigate(urlToOpen);
              }
            });
          }
        }
        // Open new window
        if (clients.openWindow) {
          return clients.openWindow(urlToOpen);
        }
      })
  );
});

// Handle notification close events
self.addEventListener('notificationclose', (event) => {
  console.log('[firebase-messaging-sw.js] Notification closed:', event);
});

// Service worker install event
self.addEventListener('install', (event) => {
  console.log('[firebase-messaging-sw.js] Service worker installing...');
  self.skipWaiting();
});

// Service worker activate event
self.addEventListener('activate', (event) => {
  console.log('[firebase-messaging-sw.js] Service worker activating...');
  event.waitUntil(clients.claim());
});

console.log('[firebase-messaging-sw.js] FCM Service Worker loaded successfully');
