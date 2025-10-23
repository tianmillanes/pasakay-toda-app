import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../services/address_search_service.dart';
import '../../services/location_storage_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationSearchBar extends StatefulWidget {
  final String hintText;
  final String? initialValue;
  final Function(String, LatLng?) onLocationSelected;
  final VoidCallback? onTap;
  final VoidCallback? onMapTap;
  final bool readOnly;

  const LocationSearchBar({
    super.key,
    required this.hintText,
    this.initialValue,
    required this.onLocationSelected,
    this.onTap,
    this.onMapTap,
    this.readOnly = false,
  });

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  late TextEditingController _controller;
  List<AddressSearchResult> _searchResults = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  bool _showResults = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _loadRecentSearches();
    
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && !widget.readOnly) {
        setState(() {
          _showResults = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final recent = await LocationStorageService.getRecentSearches();
    setState(() {
      _recentSearches = recent;
    });
  }

  Future<void> _searchAddresses(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await AddressSearchService.searchAddresses(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
    }
  }

  void _selectAddress(String address, LatLng? coordinates) async {
    _controller.text = address;
    setState(() {
      _showResults = false;
    });
    _focusNode.unfocus();
    
    // Add to recent searches
    await LocationStorageService.addRecentSearch(address);
    await _loadRecentSearches();
    
    widget.onLocationSelected(address, coordinates);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppTheme.getStandardBorderRadius(),
            boxShadow: [AppTheme.getSoftShadow()],
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onTap: widget.onTap,
            readOnly: widget.readOnly || widget.onTap != null,
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: Icon(
                Icons.search,
                color: AppTheme.primaryBlue,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onMapTap != null)
                    IconButton(
                      icon: const Icon(Icons.map, size: 20),
                      onPressed: widget.onMapTap,
                      tooltip: 'Choose on map',
                      color: const Color(0xFF2D2D2D),
                    ),
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _controller.clear();
                        setState(() {
                          _searchResults = [];
                          _showResults = false;
                        });
                        widget.onLocationSelected('', null);
                      },
                    ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: AppTheme.getStandardBorderRadius(),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              setState(() {});
              if (!widget.readOnly && widget.onTap == null) {
                _searchAddresses(value);
              }
            },
          ),
        ),
        
        // Search Results Dropdown
        if (_showResults && !widget.readOnly && widget.onTap == null)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppTheme.getStandardBorderRadius(),
              boxShadow: [AppTheme.getSoftShadow()],
            ),
            constraints: const BoxConstraints(maxHeight: 300),
            child: _buildSearchResults(),
          ),
      ],
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final hasSearchResults = _searchResults.isNotEmpty;
    final hasRecentSearches = _recentSearches.isNotEmpty;
    final showRecent = _controller.text.trim().isEmpty && hasRecentSearches;

    if (!hasSearchResults && !showRecent) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No results found',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (showRecent) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.history, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Recent Searches',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          ..._recentSearches.take(5).map((search) => ListTile(
            leading: const Icon(Icons.history, size: 20),
            title: Text(search),
            dense: true,
            onTap: () => _selectAddress(search, null),
          )),
        ],
        
        if (hasSearchResults) ...[
          if (showRecent) const Divider(),
          ..._searchResults.map((result) => ListTile(
            leading: Icon(
              Icons.location_on,
              color: AppTheme.primaryBlue,
              size: 20,
            ),
            title: Text(
              result.description,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              result.address,
              style: const TextStyle(fontSize: 12),
            ),
            dense: true,
            onTap: () => _selectAddress(result.address, result.coordinates),
          )),
        ],
      ],
    );
  }
}
