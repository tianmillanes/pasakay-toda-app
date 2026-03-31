import 'package:flutter/material.dart';
import '../models/barangay_model.dart';
import '../services/barangay_service.dart';

class BarangaySelectionDialog extends StatefulWidget {
  final BarangayModel? selectedBarangay;
  final Function(BarangayModel?) onBarangaySelected;

  const BarangaySelectionDialog({
    super.key,
    this.selectedBarangay,
    required this.onBarangaySelected,
  });

  @override
  State<BarangaySelectionDialog> createState() =>
      _BarangaySelectionDialogState();
}

class _BarangaySelectionDialogState extends State<BarangaySelectionDialog> {
  final BarangayService _barangayService = BarangayService();
  late Future<List<BarangayModel>> _barangaysFuture;
  String _searchQuery = '';
  BarangayModel? _selectedBarangay;

  @override
  void initState() {
    super.initState();
    _selectedBarangay = widget.selectedBarangay;
    _barangaysFuture = _barangayService.initializeBarangays().then((_) {
      return _barangayService.getAllBarangays();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Barangay',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Search field
                TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search barangay...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2196F3)),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Barangay list
          Expanded(
            child: FutureBuilder<List<BarangayModel>>(
              future: _barangaysFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading barangays: ${snapshot.error}'),
                  );
                }

                final barangays = snapshot.data ?? [];
                
                // Filter barangays based on search query
                final filteredBarangays = _searchQuery.isEmpty
                    ? barangays
                    : barangays
                        .where((b) =>
                            b.name.toLowerCase().contains(_searchQuery) ||
                            b.municipality.toLowerCase().contains(_searchQuery))
                        .toList();

                if (filteredBarangays.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'No results found for "$_searchQuery"',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: filteredBarangays.length,
                  itemBuilder: (context, index) {
                    final barangay = filteredBarangays[index];
                    final isSelected = _selectedBarangay?.id == barangay.id;

                    return ListTile(
                      title: Text(
                        barangay.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        barangay.municipality,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Color(0xFF2196F3),
                            )
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedBarangay = barangay;
                        });
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      tileColor: isSelected
                          ? const Color(0xFFE3F2FD)
                          : Colors.transparent,
                    );
                  },
                );
              },
            ),
          ),
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _selectedBarangay != null
                      ? () {
                          widget.onBarangaySelected(_selectedBarangay);
                          Navigator.pop(context);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Select'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}
