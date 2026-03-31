import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/fare_service.dart';
import '../../models/pasabuy_model.dart';
import '../../models/lat_lng.dart';
import '../../models/ride_model.dart';
import 'pasabuy_active_ride_screen.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/chat_button.dart';
import '../../utils/app_theme.dart';
import '../../utils/polyline_decoder.dart';

class PasaBuyDetailScreen extends StatefulWidget {
  final PasaBuyModel request;

  const PasaBuyDetailScreen({
    super.key,
    required this.request,
  });

  @override
  State<PasaBuyDetailScreen> createState() => _PasaBuyDetailScreenState();
}

class _PasaBuyDetailScreenState extends State<PasaBuyDetailScreen> {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _circleAnnotationManager;
  mapbox.PolylineAnnotationManager? _lineAnnotationManager;

  late PasaBuyModel _currentRequest;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.request;
    _loadLatestRequest();
  }

  Future<void> _loadLatestRequest() async {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final updated = await firestoreService.getPasaBuyRequest(_currentRequest.id);
    if (updated != null && mounted) {
      setState(() => _currentRequest = updated);
    }
  }

  Future<void> _acceptRequest() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    if (currentUser == null) return;

    setState(() => _isProcessing = true);
    try {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final success = await firestoreService.acceptPasaBuyRequest(
        _currentRequest.id,
        currentUser.uid,
        authService.currentUserModel?.name ?? 'Driver',
      );
      if (mounted) {
        if (success) {
          SnackbarHelper.showSuccess(context, 'Request accepted! Proceed to buy items.');
          // Redirect to active trip screen
          final updated = await firestoreService.getPasaBuyRequest(_currentRequest.id);
          if (updated != null && mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => PasaBuyActiveRideScreen(
                  requestId: updated.id,
                  request: updated,
                ),
              ),
            );
          }
        } else {
          SnackbarHelper.showError(context, 'Failed to accept request');
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _completeRequest() async {
    setState(() => _isProcessing = true);
    try {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final success = await firestoreService.completePasaBuyRequest(_currentRequest.id);
      if (mounted) {
        if (success) {
          SnackbarHelper.showSuccess(context, 'Request marked as completed!');
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) Navigator.of(context).pop();
          });
        } else {
          SnackbarHelper.showError(context, 'Failed to complete request');
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _declineRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.red, size: 32),
                ),
                const SizedBox(height: 24),
                const Text('Decline Request?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 12),
                Text('Are you sure you want to decline this PasaBuy request?', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text('Keep It', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                        ),
                        child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);
      try {
        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
        await firestoreService.cancelPasaBuyRequest(_currentRequest.id);
        if (mounted) {
          SnackbarHelper.showSuccess(context, 'Request declined');
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isProcessing = false);
          SnackbarHelper.showError(context, 'Error declining request');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAccepted = _currentRequest.status == PasaBuyStatus.accepted;
    final isCompleted = _currentRequest.status == PasaBuyStatus.completed;
    final isPending = _currentRequest.status == PasaBuyStatus.pending;
    
    final showChat = !isPending && !isCompleted && _currentRequest.status != PasaBuyStatus.cancelled;

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: showChat 
          ? ChatButton(
              contextId: _currentRequest.id,
              collectionPath: 'pasabuy_requests',
              otherUserName: _currentRequest.passengerName,
              otherUserId: _currentRequest.passengerId,
            )
          : null,
      appBar: AppBar(
        title: const Text(
          'Request Details',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Color(0xFF1A1A1A), letterSpacing: -0.5),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 260,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: mapbox.MapWidget(
                  key: const ValueKey("mapbox_pasabuy_detail_preview"),
                  onMapCreated: _onMapCreated,
                  cameraOptions: mapbox.CameraOptions(
                    center: mapbox.Point(
                      coordinates: mapbox.Position(
                        _currentRequest.pickupLocation.longitude,
                        _currentRequest.pickupLocation.latitude,
                      ),
                    ),
                    zoom: 14.0,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusHeader(),
                  const SizedBox(height: 32),
                  const Text('ITEMS TO BUY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade100, width: 1.5),
                    ),
                    child: Text(
                      _currentRequest.itemDescription,
                      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildPassengerCard(),
                  const SizedBox(height: 32),
                  const Text('DELIVERY LOCATIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 16),
                  _buildLocationRow(Icons.trip_origin_rounded, 'Source', _currentRequest.pickupAddress, const Color(0xFF4CAF50)),
                  Container(margin: const EdgeInsets.only(left: 20), height: 24, width: 2, color: Colors.grey.shade100),
                  _buildLocationRow(Icons.location_on_rounded, 'Destination', _currentRequest.dropoffAddress, const Color(0xFFF44336)),
                  const SizedBox(height: 40),
                  if (isAccepted || isCompleted) ...[
                    const Text('TIMELINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1)),
                    const SizedBox(height: 16),
                    _TimelineItem(title: 'Request Created', time: _formatTime(_currentRequest.createdAt), isCompleted: true),
                    _TimelineItem(
                      title: 'Accepted by Driver',
                      time: _currentRequest.acceptedAt != null ? _formatTime(_currentRequest.acceptedAt!) : 'Pending',
                      isCompleted: isAccepted || isCompleted,
                    ),
                    if (isCompleted)
                      _TimelineItem(
                        title: 'Completed',
                        time: _currentRequest.completedAt != null ? _formatTime(_currentRequest.completedAt!) : 'Pending',
                        isCompleted: true,
                      ),
                    const SizedBox(height: 40),
                  ],
                  _buildActionButtons(isPending, isAccepted),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _circleAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _lineAnnotationManager = await mapboxMap.annotations.createPolylineAnnotationManager();
    await _setupMarkersAndRoute();
  }

  Future<void> _setupMarkersAndRoute() async {
    if (_mapboxMap == null || _circleAnnotationManager == null) return;

    await _circleAnnotationManager!.deleteAll();
    if (_lineAnnotationManager != null) {
      await _lineAnnotationManager!.deleteAll();
    }

    await _circleAnnotationManager!.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(
            _currentRequest.pickupLocation.longitude,
            _currentRequest.pickupLocation.latitude,
          ),
        ),
        circleRadius: 8.0,
        circleColor: const Color(0xFF4CAF50).value, // Consistent Green
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    await _circleAnnotationManager!.create(
      mapbox.CircleAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(
            _currentRequest.dropoffLocation.longitude,
            _currentRequest.dropoffLocation.latitude,
          ),
        ),
        circleRadius: 8.0,
        circleColor: const Color(0xFFF44336).value, // Consistent Red
        circleStrokeWidth: 2.0,
        circleStrokeColor: Colors.white.value,
      ),
    );

    try {
      final routeGeometry = await FareService.getRouteGeometry(
        originLat: _currentRequest.pickupLocation.latitude,
        originLng: _currentRequest.pickupLocation.longitude,
        destLat: _currentRequest.dropoffLocation.latitude,
        destLng: _currentRequest.dropoffLocation.longitude,
        includeTraffic: true,
      );

      if (_lineAnnotationManager != null && routeGeometry.isNotEmpty) {
        final positions = PolylineDecoder.toMapboxPositions(routeGeometry);
        await _lineAnnotationManager!.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: positions),
            lineColor: AppTheme.primaryGreen.value,
            lineWidth: 5.0,
            lineJoin: mapbox.LineJoin.ROUND,
          ),
        );
      }
    } catch (_) {}

    await _fitMapBounds();
  }

  Future<void> _fitMapBounds() async {
    if (_mapboxMap == null) return;

    final coordinates = [
      mapbox.Point(
        coordinates: mapbox.Position(
          _currentRequest.pickupLocation.longitude,
          _currentRequest.pickupLocation.latitude,
        ),
      ),
      mapbox.Point(
        coordinates: mapbox.Position(
          _currentRequest.dropoffLocation.longitude,
          _currentRequest.dropoffLocation.latitude,
        ),
      ),
    ];

    final camera = await _mapboxMap!.cameraForCoordinates(
      coordinates,
      mapbox.MbxEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
      null,
      null,
    );

    _mapboxMap!.setCamera(camera);
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.05),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _getStatusColor(), shape: BoxShape.circle),
            child: Icon(_getStatusIcon(), color: Colors.white, size: 24),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_getStatusText().toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _getStatusColor(), letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text('Budget: ${FareService.formatFare(_currentRequest.budget)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.grey.shade100, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle),
            child: Center(
              child: Text(
                _currentRequest.passengerName.substring(0, 1).toUpperCase(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PASSENGER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey.shade400, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(_currentRequest.passengerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 2),
                Text(_currentRequest.passengerPhone, style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, String label, String address, Color iconColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey.shade400, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(address, style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isPending, bool isAccepted) {
    if (isPending) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _acceptRequest,
              icon: _isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_rounded),
              label: Text(_isProcessing ? 'Accepting...' : 'Accept Request', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: const StadiumBorder(),
                elevation: 8,
                shadowColor: AppTheme.primaryGreen.withOpacity(0.4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _isProcessing ? null : _declineRequest,
              icon: const Icon(Icons.close_rounded, size: 20),
              label: const Text('Decline Request', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      );
    } else if (isAccepted) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isProcessing ? null : _completeRequest,
          icon: _isProcessing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.done_all_rounded),
          label: Text(_isProcessing ? 'Completing...' : 'Mark as Completed', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: const StadiumBorder(),
            elevation: 8,
            shadowColor: AppTheme.primaryGreen.withOpacity(0.4),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Color _getStatusColor() {
    switch (_currentRequest.status) {
      case PasaBuyStatus.pending: return Colors.orange;
      case PasaBuyStatus.accepted:
      case PasaBuyStatus.driver_on_way:
      case PasaBuyStatus.arrived_pickup:
      case PasaBuyStatus.delivery_in_progress:
        return AppTheme.primaryGreen;
      case PasaBuyStatus.completed: return AppTheme.primaryGreen;
      case PasaBuyStatus.cancelled: return Colors.red;
    }
  }

  String _getStatusText() {
    switch (_currentRequest.status) {
      case PasaBuyStatus.pending: return 'Waiting for Driver';
      case PasaBuyStatus.accepted: return 'Accepted';
      case PasaBuyStatus.driver_on_way: return 'Heading to Store';
      case PasaBuyStatus.arrived_pickup: return 'At Store';
      case PasaBuyStatus.delivery_in_progress: return 'Delivering';
      case PasaBuyStatus.completed: return 'Completed';
      case PasaBuyStatus.cancelled: return 'Cancelled';
    }
  }

  IconData _getStatusIcon() {
    switch (_currentRequest.status) {
      case PasaBuyStatus.pending: return Icons.schedule_rounded;
      case PasaBuyStatus.accepted:
      case PasaBuyStatus.driver_on_way:
        return Icons.directions_car_rounded;
      case PasaBuyStatus.arrived_pickup: return Icons.store_rounded;
      case PasaBuyStatus.delivery_in_progress: return Icons.local_shipping_rounded;
      case PasaBuyStatus.completed: return Icons.verified_rounded;
      case PasaBuyStatus.cancelled: return Icons.cancel_rounded;
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.month}/${dateTime.day}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

class _TimelineItem extends StatelessWidget {
  final String title;
  final String time;
  final bool isCompleted;

  const _TimelineItem({required this.title, required this.time, required this.isCompleted});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: isCompleted ? AppTheme.primaryGreen : Colors.grey.shade200, shape: BoxShape.circle),
                child: Icon(isCompleted ? Icons.check_rounded : Icons.schedule_rounded, color: Colors.white, size: 14),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A))),
                const SizedBox(height: 2),
                Text(time, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
