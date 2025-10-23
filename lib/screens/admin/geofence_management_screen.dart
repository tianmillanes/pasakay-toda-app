import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../services/location_service.dart';
import '../../widgets/usability_helpers.dart';

class GeofenceManagementScreen extends StatefulWidget {
  const GeofenceManagementScreen({super.key});

  @override
  State<GeofenceManagementScreen> createState() =>
      _GeofenceManagementScreenState();
}

class _GeofenceManagementScreenState extends State<GeofenceManagementScreen> {
  GoogleMapController? _mapController;
  String _selectedGeofenceType = 'barangay';
  final List<LatLng> _currentPolygon = [];
  final Set<Polygon> _polygons = {};
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadExistingGeofences();
  }

  Future<void> _loadExistingGeofences() async {
    final locationService = Provider.of<LocationService>(
      context,
      listen: false,
    );
    await locationService.loadGeofences();
    _displayExistingGeofences(locationService);
  }

  void _displayExistingGeofences(LocationService locationService) {
    setState(() {
      _polygons.clear();
      
      // Display both geofences with different colors, but highlight the selected one
      final barangayGeofence = locationService.getBarangayGeofence();
      if (barangayGeofence != null && barangayGeofence.isNotEmpty) {
        _polygons.add(
          Polygon(
            polygonId: const PolygonId('barangay'),
            points: barangayGeofence.map((coord) => LatLng(coord[0], coord[1])).toList(),
            strokeColor: _selectedGeofenceType == 'barangay' ? Colors.blue : Colors.blue.withOpacity(0.5),
            strokeWidth: _selectedGeofenceType == 'barangay' ? 3 : 1,
            fillColor: Colors.blue.withOpacity(_selectedGeofenceType == 'barangay' ? 0.3 : 0.1),
          ),
        );
      }
      
      // Display terminal geofence if it exists
      final terminalGeofence = locationService.getTerminalGeofence();
      if (terminalGeofence != null && terminalGeofence.isNotEmpty) {
        _polygons.add(
          Polygon(
            polygonId: const PolygonId('terminal'),
            points: terminalGeofence.map((coord) => LatLng(coord[0], coord[1])).toList(),
            strokeColor: _selectedGeofenceType == 'terminal' ? Colors.red : Colors.red.withOpacity(0.5),
            strokeWidth: _selectedGeofenceType == 'terminal' ? 3 : 1,
            fillColor: Colors.red.withOpacity(_selectedGeofenceType == 'terminal' ? 0.3 : 0.1),
          ),
        );
      }
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onMapTapped(LatLng location) {
    if (!_isEditing) return;

    setState(() {
      _currentPolygon.add(location);
      _updatePolygonDisplay();
    });
  }

  void _updatePolygonDisplay() {
    if (_currentPolygon.length < 3) return;

    setState(() {
      _polygons.clear();
      _polygons.add(
        Polygon(
          polygonId: PolygonId(_selectedGeofenceType),
          points: _currentPolygon,
          strokeColor: _selectedGeofenceType == 'barangay'
              ? Colors.blue
              : Colors.red,
          strokeWidth: 2,
          fillColor:
              (_selectedGeofenceType == 'barangay' ? Colors.blue : Colors.red)
                  .withOpacity(0.3),
        ),
      );
    });
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _currentPolygon.clear();
      _polygons.clear();
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _currentPolygon.clear();
      _polygons.clear();
    });
  }

  Future<void> _saveGeofence() async {
    if (_currentPolygon.length < 3) {
      SnackbarHelper.showWarning(context, 'Please draw a polygon with at least 3 points');
      return;
    }

    try {
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      final coordinates = _currentPolygon
          .map((point) => [point.latitude, point.longitude])
          .toList();

      await locationService.updateGeofence(_selectedGeofenceType, coordinates);

      // Reload and display all geofences after saving
      _displayExistingGeofences(locationService);
      
      setState(() {
        _isEditing = false;
        _currentPolygon.clear();
      });

      if (mounted) {
        SnackbarHelper.showSuccess(
          context,
          '${_selectedGeofenceType == 'barangay' ? 'Barangay' : 'TODA Terminal'} geofence updated successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error updating geofence: $e');
      }
    }
  }

  void _undoLastPoint() {
    if (_currentPolygon.isNotEmpty) {
      setState(() {
        _currentPolygon.removeLast();
        _updatePolygonDisplay();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Controls header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.map, color: Color(0xFF34C759), size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Geofence Management',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Geofence type selector
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedGeofenceType,
                        decoration: const InputDecoration(
                          labelText: 'Geofence Type',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'barangay',
                            child: Text('Barangay Service Area'),
                          ),
                          DropdownMenuItem(
                            value: 'terminal',
                            child: Text('TODA Terminal'),
                          ),
                        ],
                        onChanged: _isEditing
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedGeofenceType = value!;
                                });
                                // Refresh display to show the selected geofence type
                                final locationService = Provider.of<LocationService>(
                                  context,
                                  listen: false,
                                );
                                _displayExistingGeofences(locationService);
                              },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Action buttons
                if (!_isEditing) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _startEditing,
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Edit Geofence'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D7CFF),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showGeofenceInfo(context),
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('View Info'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF34C759),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _cancelEditing,
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Cancel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF3B30),
                            side: const BorderSide(color: Color(0xFFFF3B30)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _currentPolygon.isNotEmpty
                              ? _undoLastPoint
                              : null,
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Undo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF9500),
                            side: const BorderSide(color: Color(0xFFFF9500)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveGeofence,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Save'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF34C759),
                            foregroundColor: Colors.white,
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Consumer<LocationService>(
                    builder: (context, locationService, child) {
                      final currentGeofence = _selectedGeofenceType == 'barangay' 
                          ? locationService.getBarangayGeofence()
                          : locationService.getTerminalGeofence();
                      
                      return Column(
                        children: [
                          Text(
                            'Drawing Points: ${_currentPolygon.length}',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          Text(
                            'Saved ${_selectedGeofenceType == 'barangay' ? 'Barangay' : 'Terminal'} Points: ${currentGeofence?.length ?? 0}',
                            style: const TextStyle(color: Colors.green, fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),

          // Instructions
          if (_isEditing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D7CFF).withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF0D7CFF).withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF0D7CFF), size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tap on the map to add points for the geofence boundary. You need at least 3 points to create a valid polygon.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2D2D2D),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Map
          Expanded(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              onTap: _onMapTapped,
              polygons: _polygons,
              initialCameraPosition: const CameraPosition(
                target: LatLng(15.4817, 120.5979), // Tarlac City coordinates
                zoom: 13,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),
        ],
      ),
    );
  }

  void _showGeofenceInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geofence Information'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Barangay Service Area',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Defines the area where passengers can book rides\n'
                '• Passengers outside this area cannot request rides\n'
                '• Covers: Sto. Cristo, Concepcion, and parts of Tarlac City',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'TODA Terminal Geofence',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Defines the TODA terminal boundary\n'
                '• Drivers must be inside this area to check in to queue\n'
                '• Drivers must return here after completing rides',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: const Text(
                  'Note: Changes to geofences will affect all users immediately. Make sure the boundaries are accurate before saving.',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
