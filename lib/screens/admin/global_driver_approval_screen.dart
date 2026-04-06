import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../models/driver_model.dart';
import '../../widgets/usability_helpers.dart';
import '../../utils/app_theme.dart';

import '../../widgets/full_screen_image_viewer.dart';

class DriverApprovalScreen extends StatefulWidget {
  const DriverApprovalScreen({super.key});

  @override
  State<DriverApprovalScreen> createState() => _DriverApprovalScreenState();
}

class _DriverApprovalScreenState extends State<DriverApprovalScreen> {
  String _filterStatus = 'pending'; // pending, approved
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Driver Approvals'),
        backgroundColor: AppTheme.backgroundWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
      ),
      body: Column(
        children: [
          _buildHeaderAndSearch(),
          _buildFilterTabs(),
          Expanded(
            child: _buildDriversList(firestoreService, authService),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAndSearch() {
    return Container(
      color: AppTheme.backgroundWhite,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search applications...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGreen),
          filled: true,
          fillColor: AppTheme.backgroundLight,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          _StatusTab(
            label: 'Pending',
            icon: Icons.timer_outlined,
            isSelected: _filterStatus == 'pending',
            color: AppTheme.warningOrange,
            onTap: () => setState(() => _filterStatus = 'pending'),
          ),
          const SizedBox(width: 15),
          _StatusTab(
            label: 'Approved',
            icon: Icons.check_circle_outline,
            isSelected: _filterStatus == 'approved',
            color: AppTheme.primaryGreen,
            onTap: () => setState(() => _filterStatus = 'approved'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriversList(FirestoreService firestoreService, AuthService authService) {
    return StreamBuilder<List<DriverModel>>(
      stream: firestoreService.getAllDrivers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen));
        }

        final drivers = snapshot.data ?? [];
        final filteredData = drivers.where((d) {
          final matchesStatus = _filterStatus == 'pending' ? !d.isApproved : d.isApproved;
          final matchesSearch = _searchQuery.isEmpty || 
              d.name.toLowerCase().contains(_searchQuery) || 
              (d.tricyclePlateNumber?.toLowerCase().contains(_searchQuery) ?? false);
          return matchesStatus && matchesSearch;
        }).toList();

        if (filteredData.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_turned_in_outlined, size: 80, color: AppTheme.textHint.withOpacity(0.2)),
                const SizedBox(height: 16),
                Text('No applications found', style: TextStyle(color: AppTheme.textHint, fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: filteredData.length,
          itemBuilder: (context, index) => _ApprovalCard(
            driver: filteredData[index],
            onTap: () => _showDetails(filteredData[index], firestoreService, authService),
          ),
        );
      },
    );
  }

  void _showDetails(DriverModel driver, FirestoreService firestoreService, AuthService authService) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DriverDetailPage(
          driver: driver,
          firestoreService: firestoreService,
          authService: authService,
        ),
      ),
    );
  }
}

class _StatusTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _StatusTab({required this.label, required this.icon, required this.isSelected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : AppTheme.backgroundWhite,
          borderRadius: BorderRadius.circular(15),
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))] : [],
          border: isSelected ? null : Border.all(color: AppTheme.borderLight),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : AppTheme.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textSecondary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final DriverModel driver;
  final VoidCallback onTap;

  const _ApprovalCard({required this.driver, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: AppTheme.backgroundWhite,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreenLight,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.person_outline, color: AppTheme.primaryGreen, size: 30),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Tricycle Plate: ${driver.tricyclePlateNumber ?? driver.plateNumber}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.backgroundLight, borderRadius: BorderRadius.circular(8)),
                      child: Text(driver.barangayName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryGreen)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverDetailPage extends StatefulWidget {
  final DriverModel driver;
  final FirestoreService firestoreService;
  final AuthService authService;

  const DriverDetailPage({
    super.key,
    required this.driver,
    required this.firestoreService,
    required this.authService,
  });

  @override
  State<DriverDetailPage> createState() => _DriverDetailPageState();
}

class _DriverDetailPageState extends State<DriverDetailPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Driver Details'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Driver Header Card
                    _buildDriverHeader(),
                    const SizedBox(height: 16),
                    
                    // Rating Summary Card
                    _buildRatingSummary(),
                    const SizedBox(height: 16),
                    
                    // Quick Info Grid
                    _buildQuickInfoGrid(),
                    const SizedBox(height: 16),
                    
                    // License Details Card
                    _buildSectionCard(
                      'License Information',
                      Icons.badge_outlined,
                      [
                        _buildDetailItem('License Number', widget.driver.driverLicenseNumber ?? 'N/A', Icons.confirmation_number_outlined),
                        if (widget.driver.lastName != null && widget.driver.firstName != null)
                          _buildDetailItem('License Name', '${widget.driver.lastName}, ${widget.driver.firstName} ${widget.driver.middleName ?? ''}', Icons.person_outline),
                        if (widget.driver.nationality != null)
                          _buildDetailItem('Nationality', widget.driver.nationality!, Icons.flag_outlined),
                        if (widget.driver.sex != null)
                          _buildDetailItem('Sex', widget.driver.sex!, Icons.people_outline),
                        if (widget.driver.dateOfBirth != null)
                          _buildDetailItem('Date of Birth', widget.driver.dateOfBirth!, Icons.cake_outlined),
                        if (widget.driver.expirationDate != null)
                          _buildDetailItem('Expiration Date', widget.driver.expirationDate!, Icons.event_outlined),
                        if (widget.driver.agencyCode != null)
                          _buildDetailItem('Agency Code', widget.driver.agencyCode!, Icons.business_outlined),
                        if (widget.driver.dlCodes != null)
                          _buildDetailItem('DL Codes', widget.driver.dlCodes!, Icons.category_outlined),
                        if (widget.driver.eyeColor != null)
                          _buildDetailItem('Eye Color', widget.driver.eyeColor!, Icons.visibility_outlined),
                        if (widget.driver.bloodType != null)
                          _buildDetailItem('Blood Type', widget.driver.bloodType!, Icons.water_drop_outlined),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Address Card
                    if (widget.driver.address != null)
                      _buildSectionCard(
                        'Address',
                        Icons.location_on_outlined,
                        [
                          _buildDetailItem('Complete Address', widget.driver.address!, Icons.home_outlined),
                        ],
                      ),
                    
                    // Documents Section
                    const SizedBox(height: 16),
                    _buildDocumentsSection(),
                    
                    // Reviews Section
                    const SizedBox(height: 16),
                    _buildReviewsSection(),
                    
                    const SizedBox(height: 80), // Space for bottom bar
                  ],
                ),
              ),
            ),
            
            // Bottom Action Bar
            if (!widget.driver.isApproved)
              _buildBottomActionBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildRatingSummary() {
    return StreamBuilder<Map<String, dynamic>>(
      stream: Stream.fromFuture(widget.firestoreService.getDriverAggregateRating(widget.driver.id)),
      builder: (context, snapshot) {
        final avgRating = snapshot.data?['averageRating'] as double? ?? 0.0;
        final reviewCount = snapshot.data?['count'] as int? ?? 0;
        
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star,
                    size: 32,
                    color: avgRating > 0 ? Colors.amber : Colors.grey.shade300,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    avgRating > 0 ? avgRating.toStringAsFixed(1) : 'No ratings yet',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: avgRating > 0 ? const Color(0xFF1A1A1A) : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                reviewCount > 0 ? '$reviewCount review${reviewCount == 1 ? '' : 's'}' : 'No reviews yet',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              if (avgRating > 0) ...[
                const SizedBox(height: 12),
                _buildStarRating(avgRating),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStarRating(double rating) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        IconData icon;
        Color color;
        
        if (rating >= starValue) {
          icon = Icons.star;
          color = Colors.amber;
        } else if (rating >= starValue - 0.5) {
          icon = Icons.star_half;
          color = Colors.amber;
        } else {
          icon = Icons.star_outline;
          color = Colors.grey.shade300;
        }
        
        return Icon(icon, color: color, size: 24);
      }),
    );
  }

  Widget _buildReviewsSection() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.firestoreService.getDriverReviews(widget.driver.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        final reviews = snapshot.data ?? [];
        
        if (reviews.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 48,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 12),
                Text(
                  'No reviews yet',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Reviews will appear here after passengers rate this driver',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.rate_review_outlined, size: 20, color: AppTheme.primaryGreen),
                  const SizedBox(width: 8),
                  const Text(
                    'Passenger Reviews',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${reviews.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              ...reviews.map((review) => _buildReviewItem(review)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReviewItem(Map<String, dynamic> review) {
    final rating = (review['rating'] ?? 0.0).toDouble();
    final feedback = review['feedback'] ?? '';
    final passengerName = review['passengerName'] ?? 'Anonymous';
    final isPasabuy = review['isPasabuy'] ?? false;
    final createdAt = review['createdAt'] as DateTime?;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppTheme.primaryGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passengerName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        _formatDate(createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPasabuy ? Colors.orange.withOpacity(0.1) : AppTheme.primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPasabuy ? 'PasaBuy' : 'Ride',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isPasabuy ? Colors.orange : AppTheme.primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ...List.generate(5, (index) {
                return Icon(
                  index < rating ? Icons.star : Icons.star_outline,
                  color: index < rating ? Colors.amber : Colors.grey.shade300,
                  size: 16,
                );
              }),
              const SizedBox(width: 8),
              Text(
                rating.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          if (feedback.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Text(
                feedback,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} min ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  Widget _buildDriverHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: 40,
              color: AppTheme.primaryGreen,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.driver.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.driver.isApproved ? AppTheme.primaryGreen.withOpacity(0.1) : AppTheme.warningOrange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.driver.isApproved ? 'Approved' : 'Pending Approval',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.driver.isApproved ? AppTheme.primaryGreen : AppTheme.warningOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickInfoGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        _buildInfoTile('Plate Number', widget.driver.tricyclePlateNumber ?? widget.driver.plateNumber ?? 'N/A', Icons.pin_outlined),
        _buildInfoTile('Vehicle Type', 'Tricycle', Icons.electric_rickshaw_outlined),
        _buildInfoTile('Barangay', widget.driver.barangayName, Icons.location_city_outlined),
        _buildInfoTile('Area', widget.driver.barangayName, Icons.map_outlined),
      ],
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primaryGreen),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_open_outlined, size: 20, color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              const Text(
                'Submitted Documents',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: _DocumentThumb(
                  label: 'License',
                  imageUrl: widget.driver.licenseNumberImageUrl,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DocumentThumb(
                  label: 'Plate',
                  imageUrl: widget.driver.plateNumberImageUrl,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _handleRejection(context),
                icon: const Icon(Icons.close, size: 18),
                label: const Text(
                  'Reject',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.errorRed,
                  side: const BorderSide(color: AppTheme.errorRed, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _handleApproval(context),
                icon: const Icon(Icons.check, size: 18),
                label: const Text(
                  'Approve',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleApproval(BuildContext context) async {
    try {
      await widget.firestoreService.approveDriver(widget.driver.id, widget.authService.currentUser!.uid);
      Navigator.pop(context);
      SnackbarHelper.showSuccess(context, 'Driver application approved successfully');
    } catch (e) {
      SnackbarHelper.showError(context, e.toString());
    }
  }

  Future<void> _handleRejection(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Rejection'),
        content: const Text('Are you sure you want to reject this driver application?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject', style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await widget.firestoreService.rejectDriver(widget.driver.id, widget.authService.currentUser!.uid);
        Navigator.pop(context);
        SnackbarHelper.showSuccess(context, 'Driver application rejected');
      } catch (e) {
        SnackbarHelper.showError(context, e.toString());
      }
    }
  }
}

class _DocumentThumb extends StatelessWidget {
  final String label;
  final String? imageUrl;

  const _DocumentThumb({required this.label, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.startsWith('data:image');
    final heroTag = 'doc_${label}_${imageUrl?.hashCode}';

    return Expanded(
      child: GestureDetector(
        onTap: hasImage
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FullScreenImageViewer(
                      imageUrl: imageUrl!,
                      tag: heroTag,
                    ),
                  ),
                )
            : null,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.backgroundLight,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: hasImage
              ? Hero(
                  tag: heroTag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.memory(base64Decode(imageUrl!.split(',').last), fit: BoxFit.cover),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.image_not_supported_outlined, color: AppTheme.textHint),
                    const SizedBox(height: 8),
                    Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                  ],
                ),
        ),
      ),
    );
  }
}
