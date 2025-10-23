import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../utils/app_theme.dart';
import '../../services/location_storage_service.dart';
import '../../services/address_search_service.dart';
import '../usability_helpers.dart';

class SavedLocationsSheet extends StatefulWidget {
  final Function(LatLng, String) onLocationSelected;

  const SavedLocationsSheet({
    super.key,
    required this.onLocationSelected,
  });

  @override
  State<SavedLocationsSheet> createState() => _SavedLocationsSheetState();
}

class _SavedLocationsSheetState extends State<SavedLocationsSheet> {

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedLocation>>(
      future: LocationStorageService.getSavedLocations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        final savedLocations = snapshot.data ?? [];
        return _buildSheet(savedLocations);
      },
    );
  }

  Widget _buildSheet(List<SavedLocation> savedLocations) {

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.bookmark,
                  color: AppTheme.primaryBlue,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Saved Locations',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Saved locations list
          if (savedLocations.isNotEmpty)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: savedLocations.length,
                itemBuilder: (context, index) {
                  final location = savedLocations[index];
                  return _buildLocationItem(location);
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No saved locations yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your frequently visited places for quick access',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          // Add new location button
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showAddLocationDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add New Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationItem(SavedLocation location) {
    IconData iconData;
    Color iconColor;
    
    // Map icon names to IconData
    switch (location.iconName) {
      case 'home':
        iconData = Icons.home;
        iconColor = AppTheme.successColor;
        break;
      case 'work':
        iconData = Icons.work;
        iconColor = AppTheme.infoColor;
        break;
      case 'school':
        iconData = Icons.school;
        iconColor = AppTheme.vibrantOrange;
        break;
      case 'local_hospital':
        iconData = Icons.local_hospital;
        iconColor = AppTheme.errorColor;
        break;
      default:
        iconData = Icons.location_on;
        iconColor = AppTheme.primaryBlue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          widget.onLocationSelected(
            location.coordinates,
            location.address,
          );
        },
        onLongPress: () => _showLocationOptions(location),
        borderRadius: AppTheme.getStandardBorderRadius(),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: AppTheme.getStandardBorderRadius(),
          ),
          child: Row(
            children: [
              Icon(
                iconData,
                color: iconColor,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location.address,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLocationOptions(SavedLocation location) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Location'),
              onTap: () {
                Navigator.pop(context);
                _showAddLocationDialog(editLocation: location);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: AppTheme.errorColor),
              title: Text('Delete Location', style: TextStyle(color: AppTheme.errorColor)),
              onTap: () {
                Navigator.pop(context);
                _deleteLocation(location);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddLocationDialog({SavedLocation? editLocation}) {
    final nameController = TextEditingController(text: editLocation?.name ?? '');
    final addressController = TextEditingController(text: editLocation?.address ?? '');
    String selectedIcon = editLocation?.iconName ?? 'location_on';
    LatLng? selectedCoordinates = editLocation?.coordinates;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(editLocation != null ? 'Edit Location' : 'Add New Location'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Location Name',
                    hintText: 'e.g., Home, Work, Gym',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: InputDecoration(
                    labelText: 'Address',
                    hintText: 'Enter address or search',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchAddress(addressController, setDialogState, (coords) {
                        selectedCoordinates = coords;
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Icon selection
                const Text('Choose Icon:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildIconOption('home', Icons.home, selectedIcon, setDialogState, (icon) {
                      selectedIcon = icon;
                    }),
                    _buildIconOption('work', Icons.work, selectedIcon, setDialogState, (icon) {
                      selectedIcon = icon;
                    }),
                    _buildIconOption('school', Icons.school, selectedIcon, setDialogState, (icon) {
                      selectedIcon = icon;
                    }),
                    _buildIconOption('local_hospital', Icons.local_hospital, selectedIcon, setDialogState, (icon) {
                      selectedIcon = icon;
                    }),
                    _buildIconOption('shopping_cart', Icons.shopping_cart, selectedIcon, setDialogState, (icon) {
                      selectedIcon = icon;
                    }),
                    _buildIconOption('restaurant', Icons.restaurant, selectedIcon, setDialogState, (icon) {
                      selectedIcon = icon;
                    }),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty || addressController.text.trim().isEmpty) {
                  SnackbarHelper.showWarning(context, 'Please fill in all fields');
                  return;
                }
                
                // Get coordinates if not already set
                if (selectedCoordinates == null) {
                  selectedCoordinates = await AddressSearchService.getCoordinatesFromAddress(addressController.text);
                }
                
                if (selectedCoordinates == null) {
                  SnackbarHelper.showError(context, 'Could not find location coordinates');
                  return;
                }
                
                final newLocation = SavedLocation(
                  id: editLocation?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  address: addressController.text.trim(),
                  coordinates: selectedCoordinates!,
                  iconName: selectedIcon,
                );
                
                final success = await LocationStorageService.saveLocation(newLocation);
                
                if (success) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close sheet
                  SnackbarHelper.showSuccess(
                    context,
                    editLocation != null ? 'Location updated!' : 'Location saved!',
                  );
                  
                  // Select the newly added/edited location
                  widget.onLocationSelected(newLocation.coordinates, newLocation.address);
                } else {
                  SnackbarHelper.showError(context, 'Failed to save location');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: Text(editLocation != null ? 'Update' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconOption(String iconName, IconData icon, String selectedIcon, 
      StateSetter setDialogState, Function(String) onSelected) {
    final isSelected = selectedIcon == iconName;
    return GestureDetector(
      onTap: () {
        setDialogState(() {
          onSelected(iconName);
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.grey[100],
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : Colors.grey[300]!,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isSelected ? AppTheme.primaryBlue : Colors.grey[600],
          size: 24,
        ),
      ),
    );
  }

  void _searchAddress(TextEditingController controller, StateSetter setDialogState, Function(LatLng?) onCoordinatesFound) async {
    final query = controller.text.trim();
    if (query.isEmpty) return;
    
    try {
      final results = await AddressSearchService.searchAddresses(query);
      if (results.isNotEmpty) {
        // Show search results
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Search Results'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final result = results[index];
                  return ListTile(
                    leading: const Icon(Icons.location_on),
                    title: Text(result.description),
                    subtitle: Text(result.address),
                    onTap: () {
                      controller.text = result.address;
                      onCoordinatesFound(result.coordinates);
                      Navigator.pop(context); // Close search results
                      setDialogState(() {}); // Update dialog
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      } else {
        SnackbarHelper.showInfo(context, 'No results found');
      }
    } catch (e) {
      SnackbarHelper.showError(context, 'Search failed');
    }
  }

  void _deleteLocation(SavedLocation location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text('Are you sure you want to delete "${location.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final success = await LocationStorageService.deleteLocation(location.id);
      if (success) {
        setState(() {}); // Refresh the sheet
        SnackbarHelper.showSuccess(context, '"${location.name}" deleted');
      }
    }
  }
}
