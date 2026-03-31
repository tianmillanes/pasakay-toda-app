import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class ModernBarangayPicker extends StatefulWidget {
  final List<String> barangayNames;
  final String selectedBarangay;
  final Function(String) onBarangaySelected;
  final bool isLoading;

  const ModernBarangayPicker({
    super.key,
    required this.barangayNames,
    required this.selectedBarangay,
    required this.onBarangaySelected,
    this.isLoading = false,
  });

  @override
  State<ModernBarangayPicker> createState() => _ModernBarangayPickerState();
}

class _ModernBarangayPickerState extends State<ModernBarangayPicker> {
  String _searchQuery = '';

  void _showBarangayPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final filteredBarangays = widget.barangayNames
                .where((b) => b.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder: (_, controller) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.backgroundWhite,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.borderLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                        child: filteredBarangays.isEmpty
                            ? const Center(
                                child: Text('No results found'),
                              )
                            : ListView.builder(
                                controller: controller,
                                itemCount: filteredBarangays.length,
                                itemBuilder: (context, index) {
                                  final barangay = filteredBarangays[index];
                                  final isSelected = (barangay == widget.selectedBarangay) || (barangay == 'All Barangays' && widget.selectedBarangay.isEmpty);
                                  return ListTile(
                                    leading: Icon(Icons.electric_rickshaw_rounded, color: isSelected ? AppTheme.primaryGreen : AppTheme.textHint),
                                    title: Text(
                                      barangay,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? AppTheme.primaryGreen : AppTheme.textPrimary,
                                      ),
                                    ),
                                    trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 20) : null,
                                    onTap: () {
                                      widget.onBarangaySelected(barangay);
                                      Navigator.pop(context);
                                    },
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
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
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showBarangayPicker(context),
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
              child: widget.isLoading
                  ? const Text(
                      'Loading Barangays...',
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      widget.selectedBarangay.isEmpty
                          ? 'All Barangays'
                          : widget.selectedBarangay,
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
