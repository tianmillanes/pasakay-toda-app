import 'package:flutter/material.dart';
import '../../models/lat_lng.dart';
import 'package:provider/provider.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../services/location_service.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../models/barangay_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';
import '../../widgets/modern_barangay_picker.dart';
import '../../config/credentials_config.dart';

enum _GeofenceEditTool {
  add,
  move,
  insert,
  delete,
}

class GeofenceManagementScreen extends StatefulWidget {
  const GeofenceManagementScreen({super.key});

  @override
  State<GeofenceManagementScreen> createState() => _GeofenceManagementScreenState();
}

class _GeofenceManagementScreenState extends State<GeofenceManagementScreen> {
  mapbox.MapboxMap? _mapboxMap;
  mapbox.CircleAnnotationManager? _pointAnnotationManager;
  mapbox.PolygonAnnotationManager? _polygonAnnotationManager;

  final GlobalKey _mapGestureKey = GlobalKey();

  String _selectedGeofenceType = 'barangay';
  String? _selectedBarangayId;
  BarangayModel? _selectedBarangay;
  List<BarangayModel> _barangays = [];
  final List<LatLng> _currentPolygon = [];
  
  bool _isEditing = false;
  bool _isLoadingGeofences = false;
  late TextEditingController _barangaySearchController;

  _GeofenceEditTool _editTool = _GeofenceEditTool.add;
  int? _selectedVertexIndex;
  final List<List<LatLng>> _undoStack = [];
  final List<List<LatLng>> _redoStack = [];

  bool _isTracing = false;
  final List<LatLng> _tracePoints = [];
  double _simplifyEpsilon = 0.00012;
  bool _isToolbarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _barangaySearchController = TextEditingController();
    _loadAllBarangaysAndGeofences();
  }

  @override
  void dispose() {
    _barangaySearchController.dispose();
    _pointAnnotationManager = null;
    _polygonAnnotationManager = null;
    super.dispose();
  }

  void _pushHistory() {
    _undoStack.add(List<LatLng>.from(_currentPolygon));
    _redoStack.clear();
  }

  List<LatLng> _dedupe(List<LatLng> pts) {
    if (pts.isEmpty) return pts;
    final out = <LatLng>[pts.first];
    for (int i = 1; i < pts.length; i++) {
      final p = pts[i];
      final last = out.last;
      if ((p.latitude - last.latitude).abs() > 1e-10 || (p.longitude - last.longitude).abs() > 1e-10) {
        out.add(p);
      }
    }
    return out;
  }

  double _perpDist2(LatLng p, LatLng a, LatLng b) {
    return _pointToSegmentDist2(p, a, b);
  }

  List<LatLng> _simplifyRdp(List<LatLng> points, double epsilon) {
    final pts = _dedupe(points);
    if (pts.length < 3) return pts;

    final eps2 = epsilon * epsilon;

    List<LatLng> rdp(List<LatLng> segment) {
      if (segment.length < 3) return segment;
      final a = segment.first;
      final b = segment.last;
      int index = -1;
      double maxDist = 0;

      for (int i = 1; i < segment.length - 1; i++) {
        final d = _perpDist2(segment[i], a, b);
        if (d > maxDist) {
          maxDist = d;
          index = i;
        }
      }

      if (maxDist <= eps2 || index == -1) {
        return [a, b];
      }

      final left = rdp(segment.sublist(0, index + 1));
      final right = rdp(segment.sublist(index));
      return [...left.sublist(0, left.length - 1), ...right];
    }

    final simplified = rdp(pts);
    return _dedupe(simplified);
  }

  void _applyPolygon(List<LatLng> points, {bool pushHistory = true}) {
    final cleaned = _dedupe(points);
    if (pushHistory) _pushHistory();
    setState(() {
      _currentPolygon
        ..clear()
        ..addAll(cleaned);
      _selectedVertexIndex = null;
      _updatePolygonDisplay();
      _updateVertexMarkers();
    });
  }

  Future<LatLng?> _screenToLatLng(Offset localPosition) async {
    if (_mapboxMap == null) return null;
    try {
      final sc = mapbox.ScreenCoordinate(x: localPosition.dx, y: localPosition.dy);
      final coord = await _mapboxMap!.coordinateForPixel(sc);
      final lat = coord.coordinates.lat.toDouble();
      final lng = coord.coordinates.lng.toDouble();
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  void _startTrace() {
    setState(() {
      _isTracing = true;
      _tracePoints.clear();
    });
  }

  void _finishTrace() {
    if (_tracePoints.length < 3) {
      setState(() {
        _isTracing = false;
      });
      return;
    }

    final simplified = _simplifyRdp(_tracePoints, _simplifyEpsilon);
    setState(() {
      _isTracing = false;
    });

    _applyPolygon(simplified);
  }

  void _cancelTrace() {
    setState(() {
      _isTracing = false;
      _tracePoints.clear();
    });
  }

  void _onTracePan(DragUpdateDetails details) {
    if (!_isTracing) return;
    _screenToLatLng(details.localPosition).then((p) {
      if (p == null) return;
      if (!mounted || !_isTracing) return;

      if (_tracePoints.isEmpty) {
        setState(() {
          _tracePoints.add(p);
        });
        return;
      }

      final last = _tracePoints.last;
      final d2 = _dist2(last, p);
      if (d2 < 0.00000003) return;

      setState(() {
        _tracePoints.add(p);
        _currentPolygon
          ..clear()
          ..addAll(_tracePoints);
        _updatePolygonDisplay();
      });
    });
  }

  void _undoEdit() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List<LatLng>.from(_currentPolygon));
    final previous = _undoStack.removeLast();
    setState(() {
      _currentPolygon
        ..clear()
        ..addAll(previous);
      _selectedVertexIndex = null;
      _updatePolygonDisplay();
      _updateVertexMarkers();
    });
  }

  void _redoEdit() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List<LatLng>.from(_currentPolygon));
    final next = _redoStack.removeLast();
    setState(() {
      _currentPolygon
        ..clear()
        ..addAll(next);
      _selectedVertexIndex = null;
      _updatePolygonDisplay();
      _updateVertexMarkers();
    });
  }

  double _dist2(LatLng a, LatLng b) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return dx * dx + dy * dy;
  }

  int? _findNearestVertexIndex(LatLng p, {double maxDist2 = 0.0000002}) {
    if (_currentPolygon.isEmpty) return null;
    int bestIdx = 0;
    double best = _dist2(_currentPolygon[0], p);
    for (int i = 1; i < _currentPolygon.length; i++) {
      final d = _dist2(_currentPolygon[i], p);
      if (d < best) {
        best = d;
        bestIdx = i;
      }
    }
    return best <= maxDist2 ? bestIdx : null;
  }

  double _pointToSegmentDist2(LatLng p, LatLng a, LatLng b) {
    final px = p.longitude;
    final py = p.latitude;
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;

    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;

    final abLen2 = abx * abx + aby * aby;
    if (abLen2 == 0) {
      final dx = px - ax;
      final dy = py - ay;
      return dx * dx + dy * dy;
    }
    double t = (apx * abx + apy * aby) / abLen2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final cx = ax + t * abx;
    final cy = ay + t * aby;
    final dx = px - cx;
    final dy = py - cy;
    return dx * dx + dy * dy;
  }

  int? _findBestInsertIndex(LatLng p) {
    if (_currentPolygon.length < 2) return null;
    int bestIdx = 1;
    double best = _pointToSegmentDist2(p, _currentPolygon[0], _currentPolygon[1]);

    for (int i = 0; i < _currentPolygon.length - 1; i++) {
      final d = _pointToSegmentDist2(p, _currentPolygon[i], _currentPolygon[i + 1]);
      if (d < best) {
        best = d;
        bestIdx = i + 1;
      }
    }

    if (_currentPolygon.length >= 3) {
      final dClose = _pointToSegmentDist2(
        p,
        _currentPolygon.last,
        _currentPolygon.first,
      );
      if (dClose < best) {
        best = dClose;
        bestIdx = _currentPolygon.length;
      }
    }

    return bestIdx;
  }

  Future<void> _loadAllBarangaysAndGeofences() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    try {
      final currentUser = authService.currentUserModel;
      if (currentUser?.role.toString() != 'UserRole.admin') return;

      final barangays = await firestoreService.getAllBarangays();
      setState(() {
        _barangays = barangays;
        if (barangays.isNotEmpty) {
          _selectedBarangayId = barangays[0].id;
          _selectedBarangay = barangays[0];
          
          // Fix map centering race condition: center map if it's already ready
          if (_mapboxMap != null) {
            _centerMapOnBarangay(barangays[0]);
          }
        }
      });
      _loadExistingGeofences();
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Error loading areas: $e');
    }
  }

  Future<void> _loadExistingGeofences() async {
    if (!mounted) return;
    setState(() {
      _isLoadingGeofences = true;
    });

    final locationService = Provider.of<LocationService>(context, listen: false);
    if (_selectedBarangayId != null) {
      await locationService.loadGeofences(barangayId: _selectedBarangayId, forceReload: true);
    } else {
      await locationService.loadGeofences();
    }
    
    // Don't overwrite map display if currently editing
    if (_mapboxMap != null && !_isEditing) {
      _displayExistingGeofences(locationService);
    }

    if (mounted) {
      setState(() {
        _isLoadingGeofences = false;
      });
    }
  }

  void _displayExistingGeofences(LocationService locationService) async {
    if (_polygonAnnotationManager == null) return;
    
    // Clear any existing polygons AND points (dots) to ensure clean state
    await _polygonAnnotationManager!.deleteAll();
    if (_pointAnnotationManager != null) {
      await _pointAnnotationManager!.deleteAll();
    }
    
    if (_selectedGeofenceType == 'barangay') {
      final barangayGeofence = locationService.getBarangayGeofence();
      if (barangayGeofence != null && barangayGeofence.isNotEmpty) {
        final points = barangayGeofence.map((coord) => [coord[1], coord[0]]).toList();
        if (points.first[0] != points.last[0] || points.first[1] != points.last[1]) {
          points.add(points.first);
        }
        
        final positions = points.map((p) => mapbox.Position(p[0], p[1])).toList();
        
        await _polygonAnnotationManager!.create(
          mapbox.PolygonAnnotationOptions(
            geometry: mapbox.Polygon(coordinates: [positions]),
            fillColor: AppTheme.primaryGreen.withOpacity(0.15).value,
            fillOutlineColor: AppTheme.primaryGreen.value,
          ),
        );
      }
    } else {
      final terminalGeofence = locationService.getTerminalGeofence();
      if (terminalGeofence != null && terminalGeofence.isNotEmpty) {
        final points = terminalGeofence.map((coord) => [coord[1], coord[0]]).toList();
        if (points.first[0] != points.last[0] || points.first[1] != points.last[1]) {
          points.add(points.first);
        }
        
        final positions = points.map((p) => mapbox.Position(p[0], p[1])).toList();

        await _polygonAnnotationManager!.create(
          mapbox.PolygonAnnotationOptions(
            geometry: mapbox.Polygon(coordinates: [positions]),
            fillColor: AppTheme.warningOrange.withOpacity(0.15).value,
            fillOutlineColor: AppTheme.warningOrange.value,
          ),
        );
      }
    }
  }

  void _onMapTapped(mapbox.MapContentGestureContext context) {
    if (!_isEditing) return;

    final location = LatLng(
      context.point.coordinates.lat.toDouble(),
      context.point.coordinates.lng.toDouble(),
    );

    if (_editTool == _GeofenceEditTool.add) {
      _pushHistory();
      setState(() {
        _currentPolygon.add(location);
        _selectedVertexIndex = null;
        _updatePolygonDisplay();
        _updateVertexMarkers();
      });
      return;
    }

    if (_editTool == _GeofenceEditTool.delete) {
      final idx = _findNearestVertexIndex(location);
      if (idx == null) return;
      _pushHistory();
      setState(() {
        _currentPolygon.removeAt(idx);
        _selectedVertexIndex = null;
        _updatePolygonDisplay();
        _updateVertexMarkers();
      });
      return;
    }

    if (_editTool == _GeofenceEditTool.move) {
      // Find if user tapped near any vertex
      final nearIdx = _findNearestVertexIndex(location);
      
      // If we already have a selection AND the tap is NOT near a vertex, move it
      if (_selectedVertexIndex != null && nearIdx == null) {
        _pushHistory();
        setState(() {
          _currentPolygon[_selectedVertexIndex!] = location;
          _selectedVertexIndex = null;
          _updatePolygonDisplay();
          _updateVertexMarkers();
        });
        return;
      }
      
      // If tap is near a vertex, select/switch to that vertex
      if (nearIdx != null) {
        setState(() {
          _selectedVertexIndex = nearIdx;
          _updateVertexMarkers();
        });
        return;
      }
      
      return;
    }

    if (_editTool == _GeofenceEditTool.insert) {
      final insertIdx = _findBestInsertIndex(location);
      if (insertIdx == null) return;
      _pushHistory();
      setState(() {
        _currentPolygon.insert(insertIdx, location);
        _selectedVertexIndex = null;
        _updatePolygonDisplay();
        _updateVertexMarkers();
      });
      return;
    }
  }

  void _updateVertexMarkers() async {
    if (_pointAnnotationManager == null) return;
    
    await _pointAnnotationManager!.deleteAll();
    
    for (int i = 0; i < _currentPolygon.length; i++) {
      final isSelected = _selectedVertexIndex == i;
      await _pointAnnotationManager!.create(
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(
              _currentPolygon[i].longitude,
              _currentPolygon[i].latitude,
            ),
          ),
          circleRadius: isSelected ? 8.0 : 6.0,
          circleColor: (isSelected ? AppTheme.warningOrange : AppTheme.primaryGreen).value,
          circleStrokeWidth: 2.0,
          circleStrokeColor: Colors.white.value,
        ),
      );
    }
  }

  void _setupAnnotationListeners() {
  }

  void _centerMapOnBarangay(BarangayModel barangay) {
    if (_mapboxMap == null) return;

    LatLng? target;
    if (barangay.centerLocation != null) {
      target = LatLng(barangay.centerLocation!.latitude, barangay.centerLocation!.longitude);
    } else if (barangay.geofenceCoordinates != null && barangay.geofenceCoordinates!.isNotEmpty) {
      double lat = 0, lng = 0;
      for (var coord in barangay.geofenceCoordinates!) {
        lat += coord[0];
        lng += coord[1];
      }
      target = LatLng(lat / barangay.geofenceCoordinates!.length, lng / barangay.geofenceCoordinates!.length);
    }

    if (target != null) {
      _mapboxMap!.setCamera(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(target.longitude, target.latitude)),
          zoom: 15.5,
        ),
      );
    }
  }

  void _updatePolygonDisplay() async {
    if (_polygonAnnotationManager == null) return;
    
    await _polygonAnnotationManager!.deleteAll();

    if (_currentPolygon.length < 3) return;
    
    final points = _currentPolygon.map((p) => mapbox.Position(p.longitude, p.latitude)).toList();
    final closedPoints = List<mapbox.Position>.from(points);
    closedPoints.add(points.first);
    
    await _polygonAnnotationManager!.create(
      mapbox.PolygonAnnotationOptions(
        geometry: mapbox.Polygon(coordinates: [closedPoints]),
        fillColor: (_selectedGeofenceType == 'barangay' ? AppTheme.primaryGreen : AppTheme.warningOrange).withOpacity(0.3).value,
        fillOutlineColor: (_selectedGeofenceType == 'barangay' ? AppTheme.primaryGreen : AppTheme.warningOrange).value,
      ),
    );
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointAnnotationManager = await mapboxMap.annotations.createCircleAnnotationManager();
    _polygonAnnotationManager = await mapboxMap.annotations.createPolygonAnnotationManager();
    
    _setupAnnotationListeners();
    
    if (_selectedBarangay != null) {
      _centerMapOnBarangay(_selectedBarangay!);
    }
    
    _loadExistingGeofences();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Geofence Management'),
        backgroundColor: AppTheme.backgroundWhite,
        centerTitle: false,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          _buildControlPanel(),
          if (_isEditing) _buildEditingHint(),
          Expanded(
            child: Stack(
              children: [
                mapbox.MapWidget(
                  key: const ValueKey("mapbox_geofence_admin"),
                  onMapCreated: _onMapCreated,
                  onTapListener: _onMapTapped,
                  cameraOptions: mapbox.CameraOptions(
                    center: mapbox.Point(coordinates: mapbox.Position(120.5979, 15.4817)),
                    zoom: 14.0,
                  ),
                ),
                if (_isEditing)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_isTracing,
                      child: GestureDetector(
                        key: _mapGestureKey,
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: _onTracePan,
                        onPanEnd: (_) => _finishTrace(),
                      ),
                    ),
                  ),
                if (_isEditing)
                  IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity(0.1),
                    ),
                  ),
                if (_isLoadingGeofences)
                  Container(
                    color: Colors.white.withOpacity(0.5),
                    child: const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      color: AppTheme.backgroundWhite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            constraints: BoxConstraints(
              maxHeight: _isToolbarCollapsed && _isEditing ? 0 : 500,
            ),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _isToolbarCollapsed && _isEditing ? 0.0 : 1.0,
              curve: Curves.easeInOut,
              child: ClipRect(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Compact Selection Section
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: AbsorbPointer(
                                absorbing: _isEditing,
                                child: ModernBarangayPicker(
                                  barangayNames: _barangays.map((b) => b.name).toList(),
                                  selectedBarangay: _selectedBarangay?.name ?? 'Select Barangay',
                                  onBarangaySelected: (name) {
                                    final selected = _barangays.firstWhere((b) => b.name == name);
                                    setState(() {
                                      _selectedBarangayId = selected.id;
                                      _selectedBarangay = selected;
                                    });
                                    _loadExistingGeofences();
                                    _centerMapOnBarangay(selected);
                                  },
                                  isLoading: _barangays.isEmpty,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: AbsorbPointer(
                                absorbing: _isEditing,
                                child: Opacity(
                                  opacity: _isEditing ? 0.6 : 1.0,
                                  child: _buildTypeToggle(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // Action Buttons
                        _isEditing ? _buildEditingActions() : _buildNormalActions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Drag handle for collapse/expand (at the bottom)
          if (_isEditing)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity! < -300) {
                  // Swiped up fast - collapse
                  setState(() => _isToolbarCollapsed = true);
                } else if (details.primaryVelocity! > 300) {
                  // Swiped down fast - expand
                  setState(() => _isToolbarCollapsed = false);
                }
              },
              onTap: () => setState(() => _isToolbarCollapsed = !_isToolbarCollapsed),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isToolbarCollapsed ? 'TAP TO EXPAND' : 'SWIPE UP TO HIDE',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypeToggle() {
    final isBarangay = _selectedGeofenceType == 'barangay';
    final currentColor = isBarangay ? AppTheme.primaryGreen : AppTheme.warningOrange;
    final currentIcon = isBarangay ? Icons.map_outlined : Icons.electric_rickshaw_rounded;
    final currentLabel = isBarangay ? 'Service Area' : 'Terminal';
    
    return PopupMenuButton<String>(
      initialValue: _selectedGeofenceType,
      onSelected: (value) {
        setState(() {
          _selectedGeofenceType = value;
        });
        // Load and display boundary for the selected geofence type in real-time
        _loadExistingGeofences();
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'barangay',
          child: Row(
            children: [
              Icon(Icons.map_outlined, size: 18, color: AppTheme.primaryGreen),
              const SizedBox(width: 10),
              const Text('Service Area', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'terminal',
          child: Row(
            children: [
              Icon(Icons.electric_rickshaw_rounded, size: 18, color: AppTheme.warningOrange),
              const SizedBox(width: 10),
              const Text('Terminal', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: currentColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: currentColor.withOpacity(0.3)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(currentIcon, size: 16, color: currentColor),
              const SizedBox(width: 8),
              Text(
                currentLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: currentColor,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_drop_down, size: 18, color: currentColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNormalActions() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          setState(() {
            _isEditing = true;
            _currentPolygon.clear();

            final locationService = Provider.of<LocationService>(context, listen: false);
            final existing = _selectedGeofenceType == 'barangay' 
                ? locationService.getBarangayGeofence() 
                : locationService.getTerminalGeofence();
            
            if (existing != null) {
              _currentPolygon.addAll(existing.map((e) => LatLng(e[0], e[1])));
            }

            _editTool = _GeofenceEditTool.add;
            _selectedVertexIndex = null;
            _undoStack.clear();
            _redoStack.clear();
            _isTracing = false;
            _tracePoints.clear();

            _updatePolygonDisplay();
            _updateVertexMarkers();
          });
        },
        icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
        label: const Text(
          'Edit Boundary',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildEditingActions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Editing Tools
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _EditingToolButton(
                  icon: Icons.add_location_alt_rounded,
                  tooltip: 'Add Points',
                  isActive: _editTool == _GeofenceEditTool.add,
                  onPressed: () => setState(() {
                    _editTool = _GeofenceEditTool.add;
                    _selectedVertexIndex = null;
                    _updateVertexMarkers();
                  }),
                ),
                const SizedBox(width: 6),
                _EditingToolButton(
                  icon: Icons.open_with_rounded,
                  tooltip: 'Move Vertex (tap vertex then tap new spot)',
                  isActive: _editTool == _GeofenceEditTool.move,
                  onPressed: () => setState(() {
                    _editTool = _GeofenceEditTool.move;
                    _selectedVertexIndex = null;
                    _updateVertexMarkers();
                  }),
                ),
                const SizedBox(width: 6),
                _EditingToolButton(
                  icon: Icons.add_road_rounded,
                  tooltip: 'Insert Point (tap near an edge)',
                  isActive: _editTool == _GeofenceEditTool.insert,
                  onPressed: () => setState(() {
                    _editTool = _GeofenceEditTool.insert;
                    _selectedVertexIndex = null;
                    _updateVertexMarkers();
                  }),
                ),
                const SizedBox(width: 6),
                _EditingToolButton(
                  icon: Icons.delete_forever_rounded,
                  tooltip: 'Delete Vertex (tap near a vertex)',
                  isActive: _editTool == _GeofenceEditTool.delete,
                  color: AppTheme.errorRed,
                  onPressed: () => setState(() {
                    _editTool = _GeofenceEditTool.delete;
                    _selectedVertexIndex = null;
                    _updateVertexMarkers();
                  }),
                ),
                const SizedBox(width: 6),
                _EditingToolButton(
                  icon: Icons.layers_clear_rounded,
                  tooltip: 'Clear All Points',
                  onPressed: _clearAllPoints,
                  color: AppTheme.errorRed,
                ),
                const SizedBox(width: 6),
                _EditingToolButton(
                  icon: Icons.undo_rounded,
                  tooltip: 'Undo',
                  onPressed: _undoEdit,
                ),
                const SizedBox(width: 6),
                _EditingToolButton(
                  icon: Icons.redo_rounded,
                  tooltip: 'Redo',
                  onPressed: _redoEdit,
                ),
                const SizedBox(width: 6),
                _EditingToolButton(
                  icon: Icons.gesture_rounded,
                  tooltip: _isTracing ? 'Tracing…' : 'Freehand Trace',
                  isActive: _isTracing,
                  onPressed: () {
                    if (!_isTracing) {
                      _pushHistory();
                      _startTrace();
                    } else {
                      _finishTrace();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          
          Row(
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${_currentPolygon.length} pts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() { 
                    _isEditing = false; 
                    _loadExistingGeofences(); 
                  }),
                  icon: const Icon(Icons.close_rounded, size: 14),
                  label: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: AppTheme.errorRed, width: 1.5),
                    foregroundColor: AppTheme.errorRed,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _saveGeofence,
                  icon: const Icon(Icons.save_rounded, size: 14),
                  label: const Text('Save Changes', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditingHint() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        children: [
          const Icon(
            Icons.edit_location_alt_outlined, 
            color: Colors.white, 
            size: 16,
          ),
          const SizedBox(width: 10),
          const Text(
            'EDITING MODE',
            style: TextStyle(
              color: Colors.white, 
              fontWeight: FontWeight.w700, 
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 14,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _editTool == _GeofenceEditTool.add
                  ? 'Tap to add points'
                  : _editTool == _GeofenceEditTool.move
                      ? (_selectedVertexIndex == null
                          ? 'Tap a vertex to select, then tap where to move'
                          : 'Tap new location to move selected vertex')
                      : _editTool == _GeofenceEditTool.insert
                          ? 'Tap near an edge to insert a point'
                          : 'Tap near a vertex to delete',
              style: const TextStyle(
                color: Color.fromARGB(230, 255, 255, 255),
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  

  Future<void> _clearAllPoints() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Points?'),
        content: const Text('This will remove all vertices from the current geofence. This action can be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorRed),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _pushHistory();
      setState(() {
        _currentPolygon.clear();
        _selectedVertexIndex = null;
        _updatePolygonDisplay();
        _updateVertexMarkers();
      });
    }
  }

  Future<void> _saveGeofence() async {
    // Allow saving empty polygon (to clear geofence), but prevent saving invalid polygons (1-2 points)
    if (_currentPolygon.isNotEmpty && _currentPolygon.length < 3) {
      SnackbarHelper.showWarning(context, 'Please add at least 3 points or clear all points to delete the geofence');
      return;
    }
    try {
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final coords = _currentPolygon.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
      
      if (_selectedGeofenceType == 'barangay') {
        await firestoreService.updateBarangayGeofence(_selectedBarangayId!, coords);
      } else {
        await firestoreService.updateBarangayTerminalGeofence(_selectedBarangayId!, coords);
      }
      
      _loadExistingGeofences();
      setState(() { _isEditing = false; });
      SnackbarHelper.showSuccess(context, 'Geofence updated successfully');
    } catch (e) {
      SnackbarHelper.showError(context, 'Save failed: $e');
    }
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label, 
          style: const TextStyle(
            fontSize: 11, 
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _EditingToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? color;

  const _EditingToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? Colors.grey.shade700;
    final bg = isActive
        ? AppTheme.primaryGreen.withOpacity(0.18)
        : baseColor.withOpacity(0.10);
    final fg = isActive ? AppTheme.primaryGreen : baseColor;

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: fg,
          size: 16,
        ),
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          backgroundColor: bg,
          foregroundColor: fg,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
