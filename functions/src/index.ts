import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';

admin.initializeApp();

function stringifyData(obj: any): Record<string, string> {
  const out: Record<string, string> = {};
  if (!obj) return out;
  for (const [k, v] of Object.entries(obj)) out[k] = String(v);
  return out;
}

export const onNotificationCreate = onDocumentCreated('notifications/{notificationId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = (snap.data() as any) || {};
    const userId: string = data.userId;
    const title: string = data.title ?? 'Notification';
    const body: string = (data.body ?? data.message ?? '') as string;
    const extra = stringifyData(data.data || {});

    if (!userId) {
      functions.logger.warn('notifications doc missing userId', data);
      return;
    }

    // Collect tokens from both main field and subcollection
    const userRef = admin.firestore().collection('users').doc(userId);
    const userDoc = await userRef.get();
    const primaryToken = userDoc.exists ? (userDoc.get('fcmToken') as string | undefined) : undefined;

    const tokensSnap = await userRef.collection('tokens').get();
    const tokens = new Set<string>();
    if (primaryToken) tokens.add(primaryToken);
    tokensSnap.docs.forEach(d => tokens.add(d.id)); // token as doc id as per client code

    if (tokens.size === 0) {
      functions.logger.warn('No FCM tokens for user', { userId });
      return;
    }

    const message: admin.messaging.MulticastMessage = {
      tokens: Array.from(tokens),
      notification: { title, body },
      data: {
        ...extra,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        channelId: 'ride_requests',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'ride_requests',
          sound: 'default',
          color: '#2196F3',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: {
          aps: {
            sound: 'default',
            contentAvailable: true,
          },
        },
      },
    };

    const resp = await admin.messaging().sendMulticast(message);
    functions.logger.info('FCM send result', {
      success: resp.successCount,
      failure: resp.failureCount,
    });

    // Optional: annotate notification doc with delivery result
    await snap.ref.set(
      {
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        deliveredCount: resp.successCount,
        failedCount: resp.failureCount,
      },
      { merge: true }
    );

    // Optional cleanup of invalid tokens
    const invalid = resp.responses
      .map((r, i) => (r.success ? null : i))
      .filter((i): i is number => i !== null)
      .map(i => Array.from(tokens)[i]);

    if (invalid.length > 0) {
      functions.logger.warn('Cleaning invalid tokens', { count: invalid.length });
      for (const t of invalid) {
        await userRef.collection('tokens').doc(t).delete().catch(() => {});
        if (primaryToken === t) {
          await userRef.set({ fcmToken: admin.firestore.FieldValue.delete() }, { merge: true });
        }
      }
    }
  });

/**
 * Cloud Function to send push notifications for ride requests
 * Watches the notification_requests collection and sends FCM notifications
 */
export const sendRideNotification = onDocumentCreated(
  'notification_requests/{requestId}',
  async (event) => {
    const snap = event.data;
    if (!snap) {
      functions.logger.warn('No data in snapshot');
      return;
    }

    const data = snap.data() as any;
    const targetUserId: string = data.targetUserId;
    const title: string = data.title ?? 'Notification';
    const body: string = data.body ?? '';
    const notificationData = data.data || {};
    const processed = data.processed ?? false;

    functions.logger.info('🔔 New notification request', {
      requestId: snap.id,
      targetUserId,
      title,
      processed,
    });

    // Skip if already processed
    if (processed) {
      functions.logger.info('Already processed, skipping');
      return;
    }

    if (!targetUserId) {
      functions.logger.warn('Missing targetUserId');
      await snap.ref.update({
        processed: true,
        error: 'Missing targetUserId',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    try {
      // Get user's FCM token
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(targetUserId)
        .get();

      if (!userDoc.exists) {
        functions.logger.error('User not found', { targetUserId });
        await snap.ref.update({
          processed: true,
          error: 'User not found',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      const userData = userDoc.data();
      const fcmToken = userData?.fcmToken as string | undefined;

      if (!fcmToken) {
        functions.logger.warn('No FCM token for user', { targetUserId });
        await snap.ref.update({
          processed: true,
          error: 'No FCM token',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return;
      }

      functions.logger.info('📤 Sending FCM notification', {
        token: fcmToken.substring(0, 20) + '...',
      });

      // Prepare FCM message
      const message: admin.messaging.Message = {
        token: fcmToken,
        notification: {
          title,
          body,
        },
        data: stringifyData(notificationData),
        android: {
          priority: 'high',
          notification: {
            channelId: 'ride_requests',
            sound: 'default',
            priority: 'high' as const,
            defaultSound: true,
            defaultVibrateTimings: true,
            color: '#0D7CFF',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
          },
          payload: {
            aps: {
              contentAvailable: true,
              sound: 'default',
              badge: 1,
            },
          },
        },
      };

      // Send notification
      const response = await admin.messaging().send(message);
      
      functions.logger.info('✅ Notification sent successfully', {
        response,
      });

      // Mark as processed
      await snap.ref.update({
        processed: true,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        fcmResponse: response,
      });

    } catch (error: any) {
      functions.logger.error('❌ Error sending notification', {
        error: error.message,
        code: error.code,
      });

      // Mark as processed with error
      await snap.ref.update({
        processed: true,
        error: error.message,
        errorCode: error.code,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }
);
