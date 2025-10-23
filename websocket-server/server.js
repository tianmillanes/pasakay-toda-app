const WebSocket = require('ws');
const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Store connected clients
const clients = new Map();

// Create HTTP server
const server = require('http').createServer(app);

// Create WebSocket server
const wss = new WebSocket.Server({ 
  server,
  path: '/ws'
});

// WebSocket connection handler
wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const userId = url.searchParams.get('userId');
  const clientId = uuidv4();
  
  console.log(`📱 New WebSocket connection: ${clientId} for user: ${userId}`);
  
  // Store client connection
  const clientInfo = {
    id: clientId,
    userId: userId,
    ws: ws,
    connectedAt: new Date(),
    lastPing: new Date()
  };
  
  clients.set(clientId, clientInfo);
  
  // Send connection confirmation
  ws.send(JSON.stringify({
    type: 'connected',
    clientId: clientId,
    message: 'Connected to TODA notification server',
    timestamp: new Date().toISOString()
  }));
  
  // Handle incoming messages
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      handleMessage(clientId, data);
    } catch (error) {
      console.error('❌ Error parsing message:', error);
    }
  });
  
  // Handle connection close
  ws.on('close', () => {
    console.log(`🔌 WebSocket disconnected: ${clientId}`);
    clients.delete(clientId);
  });
  
  // Handle connection error
  ws.on('error', (error) => {
    console.error(`❌ WebSocket error for ${clientId}:`, error);
    clients.delete(clientId);
  });
});

// Handle WebSocket messages
function handleMessage(clientId, data) {
  const client = clients.get(clientId);
  if (!client) return;
  
  const { type } = data;
  
  switch (type) {
    case 'ping':
      // Respond to heartbeat
      client.lastPing = new Date();
      client.ws.send(JSON.stringify({
        type: 'pong',
        timestamp: new Date().toISOString()
      }));
      break;
      
    case 'auth':
      // Update user authentication
      client.userId = data.userId;
      console.log(`✅ Client ${clientId} authenticated as user: ${data.userId}`);
      break;
      
    case 'send_notification':
      // Send notification to specific user
      sendNotificationToUser(data.targetUserId, data.notification);
      break;
      
    default:
      console.log(`❓ Unknown message type: ${type}`);
  }
}

// Send notification to specific user
function sendNotificationToUser(userId, notification) {
  let sent = false;
  
  for (const [clientId, client] of clients) {
    if (client.userId === userId && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(JSON.stringify({
        type: 'notification',
        title: notification.title,
        body: notification.body,
        data: notification.data || {},
        timestamp: new Date().toISOString()
      }));
      
      console.log(`📤 Notification sent to user ${userId}: ${notification.title}`);
      sent = true;
    }
  }
  
  if (!sent) {
    console.log(`❌ User ${userId} not connected, notification not delivered`);
  }
  
  return sent;
}

// Broadcast notification to all connected clients
function broadcastNotification(notification) {
  let count = 0;
  
  for (const [clientId, client] of clients) {
    if (client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(JSON.stringify({
        type: 'notification',
        title: notification.title,
        body: notification.body,
        data: notification.data || {},
        timestamp: new Date().toISOString()
      }));
      count++;
    }
  }
  
  console.log(`📢 Broadcast notification sent to ${count} clients`);
  return count;
}

// REST API endpoints for sending notifications
app.post('/api/notify/user', (req, res) => {
  const { userId, title, body, data } = req.body;
  
  if (!userId || !title || !body) {
    return res.status(400).json({
      error: 'Missing required fields: userId, title, body'
    });
  }
  
  const sent = sendNotificationToUser(userId, { title, body, data });
  
  res.json({
    success: sent,
    message: sent ? 'Notification sent' : 'User not connected',
    userId: userId,
    timestamp: new Date().toISOString()
  });
});

app.post('/api/notify/broadcast', (req, res) => {
  const { title, body, data } = req.body;
  
  if (!title || !body) {
    return res.status(400).json({
      error: 'Missing required fields: title, body'
    });
  }
  
  const count = broadcastNotification({ title, body, data });
  
  res.json({
    success: true,
    message: `Notification broadcast to ${count} clients`,
    clientCount: count,
    timestamp: new Date().toISOString()
  });
});

// TODA-specific notification endpoints
app.post('/api/toda/ride-request', (req, res) => {
  const { driverId, rideId, passengerName, pickupAddress, destinationAddress, fare } = req.body;
  
  const notification = {
    title: '🚗 New Ride Request',
    body: `${passengerName} needs a ride: ${pickupAddress} → ${destinationAddress}`,
    data: {
      type: 'ride_request',
      rideId,
      passengerName,
      pickupAddress,
      destinationAddress,
      fare: fare?.toString()
    }
  };
  
  const sent = sendNotificationToUser(driverId, notification);
  
  res.json({
    success: sent,
    message: sent ? 'Ride request notification sent' : 'Driver not connected',
    driverId,
    rideId,
    timestamp: new Date().toISOString()
  });
});

app.post('/api/toda/ride-accepted', (req, res) => {
  const { passengerId, rideId, driverName, vehicleInfo } = req.body;
  
  const notification = {
    title: '✅ Ride Accepted!',
    body: `Driver ${driverName} accepted your ride request`,
    data: {
      type: 'ride_accepted',
      rideId,
      driverName,
      vehicleInfo
    }
  };
  
  const sent = sendNotificationToUser(passengerId, notification);
  
  res.json({
    success: sent,
    message: sent ? 'Ride accepted notification sent' : 'Passenger not connected',
    passengerId,
    rideId,
    timestamp: new Date().toISOString()
  });
});

app.post('/api/toda/driver-approved', (req, res) => {
  const { driverId } = req.body;
  
  const notification = {
    title: '🎉 Application Approved!',
    body: 'Congratulations! You can now accept rides',
    data: {
      type: 'driver_approved'
    }
  };
  
  const sent = sendNotificationToUser(driverId, notification);
  
  res.json({
    success: sent,
    message: sent ? 'Driver approval notification sent' : 'Driver not connected',
    driverId,
    timestamp: new Date().toISOString()
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    connectedClients: clients.size,
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// Get connected clients info
app.get('/api/clients', (req, res) => {
  const clientList = Array.from(clients.values()).map(client => ({
    id: client.id,
    userId: client.userId,
    connectedAt: client.connectedAt,
    lastPing: client.lastPing
  }));
  
  res.json({
    totalClients: clients.size,
    clients: clientList,
    timestamp: new Date().toISOString()
  });
});

// Cleanup disconnected clients every 5 minutes
setInterval(() => {
  const now = new Date();
  let cleaned = 0;
  
  for (const [clientId, client] of clients) {
    // Remove clients that haven't pinged in 2 minutes
    if (now - client.lastPing > 2 * 60 * 1000) {
      if (client.ws.readyState !== WebSocket.OPEN) {
        clients.delete(clientId);
        cleaned++;
      }
    }
  }
  
  if (cleaned > 0) {
    console.log(`🧹 Cleaned up ${cleaned} disconnected clients`);
  }
}, 5 * 60 * 1000);

// Start server
server.listen(PORT, () => {
  console.log(`🚀 TODA WebSocket server running on port ${PORT}`);
  console.log(`📱 WebSocket endpoint: ws://localhost:${PORT}/ws`);
  console.log(`🌐 HTTP API: http://localhost:${PORT}`);
  console.log(`❤️ Health check: http://localhost:${PORT}/health`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('🛑 Shutting down server...');
  
  // Close all WebSocket connections
  for (const [clientId, client] of clients) {
    client.ws.close();
  }
  
  server.close(() => {
    console.log('✅ Server shut down gracefully');
    process.exit(0);
  });
});
