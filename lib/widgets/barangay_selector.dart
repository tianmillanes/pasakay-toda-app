import 'package:flutter/material.dart';
import '../models/barangay_model.dart';
import '../services/barangay_service.dart';
import '../utils/app_theme.dart';

class BarangaySelector extends StatefulWidget {
  final Function(BarangayModel) onBarangaySelected;
  final BarangayModel? selectedBarangay;

  const BarangaySelector({
    super.key,
    required this.onBarangaySelected,
    this.selectedBarangay,
  });

  @override
  State<BarangaySelector> createState() => _BarangaySelectorState();
}

class _BarangaySelectorState extends State<BarangaySelector> {
  final BarangayService _barangayService = BarangayService();
  List<BarangayModel> _allBarangays = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBarangays();
  }

  Future<void> _loadBarangays() async {
    try {
      await _barangayService.initializeBarangays();
      final data = await _barangayService.getAllBarangays();
      
      List<BarangayModel> result = data;
      if (result.isEmpty) {
        final now = DateTime.now();
        result = BarangayService.staticBarangays.map((name) {
          return BarangayModel(
            id: 'barangay_${name.toLowerCase().replaceAll(' ', '_')}',
            name: name,
            municipality: 'Concepcion',
            province: 'Tarlac',
            createdAt: now,
          );
        }).toList();
      }

      // Deduplicate
      final seenIds = <String>{};
      result = result.where((b) => seenIds.add(b.id)).toList();

      if (mounted) {
        setState(() {
          _allBarangays = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showBarangayPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filteredList = _allBarangays
                .where((b) => b.name.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              expand: false,
              builder: (_, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.borderLight,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: TextField(
                          onChanged: (value) {
                            setModalState(() {
                              _searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search Barangay',
                            prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGreen),
                            filled: true,
                            fillColor: AppTheme.backgroundLight,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      Expanded(
                        child: _isLoading 
                        ? const Center(child: CircularProgressIndicator())
                        : filteredList.isEmpty
                          ? const Center(child: Text('No results found'))
                          : ListView.builder(
                              controller: controller,
                              itemCount: filteredList.length,
                              itemBuilder: (context, index) {
                                final barangay = filteredList[index];
                                final isSelected = widget.selectedBarangay?.id == barangay.id;

                                return ListTile(
                                  leading: Icon(
                                    Icons.electric_rickshaw_rounded, 
                                    color: isSelected ? AppTheme.primaryGreen : AppTheme.textHint
                                  ),
                                  title: Text(
                                    barangay.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? AppTheme.primaryGreen : AppTheme.textPrimary,
                                    ),
                                  ),
                                  trailing: isSelected 
                                    ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 20)
                                    : null,
                                  onTap: () {
                                    widget.onBarangaySelected(barangay);
                                    Navigator.pop(context);
                                  },
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  selected: isSelected,
                                  selectedTileColor: AppTheme.primaryGreen.withOpacity(0.05),
                                );
                              },
                            ),
                      ),
                    ],
                  ),
                );
              },
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _showBarangayPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _isLoading
                  ? const Text(
                      'Loading Barangays...',
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      widget.selectedBarangay?.name ?? 'Select Barangay',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }
}
