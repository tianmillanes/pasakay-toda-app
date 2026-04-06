import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../services/auth_service.dart';
import '../../services/verification_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/license_scanning_service.dart';
import '../../services/barangay_service.dart';
import '../../models/user_model.dart';
import '../../models/driver_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/usability_helpers.dart';
import '../../widgets/verification_widgets.dart';
import 'terms_and_conditions_screen.dart';
import '../../widgets/barangay_selector.dart';
import '../../models/barangay_model.dart';
import '../../utils/app_theme.dart';
import '../../widgets/tricycle_logo.dart';

enum DriverRegistrationStep {
  userInfo,
  verification,
  licenseInfo, // New step for license upload and scanning
  vehicleInfo,
  complete,
}

class DriverRegisterScreenWithVerification extends StatefulWidget {
  const DriverRegisterScreenWithVerification({super.key});

  @override
  State<DriverRegisterScreenWithVerification> createState() => _DriverRegisterScreenWithVerificationState();
}

class _DriverRegisterScreenWithVerificationState extends State<DriverRegisterScreenWithVerification> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _tricyclePlateController = TextEditingController();

  // License details extracted from OCR - read-only display
  String? _extractedFullName;
  String? _extractedLicenseNumber;
  String? _extractedLastName;
  String? _extractedFirstName;
  String? _extractedMiddleName;
  String? _extractedNationality;
  String? _extractedSex;
  String? _extractedDateOfBirth;
  String? _extractedWeight;
  String? _extractedHeight;
  String? _extractedAddress;
  String? _extractedExpirationDate;
  String? _extractedAgencyCode;
  String? _extractedBloodType;
  String? _extractedEyeColor;
  String? _extractedDLCodes;
  String? _extractedConditions;

  DriverRegistrationStep _currentStep = DriverRegistrationStep.userInfo;
  VerificationType _selectedVerificationType = VerificationType.email;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isVerificationLoading = false;
  bool _isScanningLicense = false;
  String? _verificationError;
  String _verificationCode = '';
  bool _agreedToTerms = false;
  BarangayModel? _selectedBarangay;

  XFile? _plateNumberImage;
  XFile? _licenseNumberImage;

  late VerificationService _verificationService;
  late LicenseScanningService _licenseScanningService;

  @override
  void initState() {
    super.initState();
    _verificationService = VerificationService();
    _licenseScanningService = LicenseScanningService();
    _licenseScanningService.initialize();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _tricyclePlateController.dispose();
    _verificationService.dispose();
    _licenseScanningService.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isPlateNumber) async {
    final ImagePicker picker = ImagePicker();
    try {
      // Show source selection dialog
      final ImageSource? source = await SnackbarHelper.showImageSourceDialog(context);
      
      if (source == null) return; // User cancelled
      
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          if (isPlateNumber) {
            _plateNumberImage = image;
          } else {
            _licenseNumberImage = image;
          }
        });
        
        if (!isPlateNumber) {
          _processLicenseImage(image.path);
        } else {
          _processPlateImage(image.path);
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Failed to capture image');
    }
  }

  Future<void> _processPlateImage(String imagePath) async {
    setState(() => _isScanningLicense = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning plate number...'), duration: Duration(seconds: 2)),
      );
    }

    try {
      final plateNumber = await _licenseScanningService.scanPlateNumber(imagePath);

      if (mounted) {
        if (plateNumber != null && plateNumber.isNotEmpty) {
          setState(() {
            _tricyclePlateController.text = plateNumber;
          });
          SnackbarHelper.showSuccess(context, 'Plate number detected: $plateNumber');
        } else {
          SnackbarHelper.showError(context, 'Could not detect plate number. Please enter manually.');
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Failed to scan plate image: $e');
    } finally {
      if (mounted) setState(() => _isScanningLicense = false);
    }
  }

  Future<void> _processLicenseImage(String imagePath) async {
    setState(() => _isScanningLicense = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanning license details...'), duration: Duration(seconds: 2)),
      );
    }

    try {
      final licenseDetails = await _licenseScanningService.scanLicense(imagePath);

      if (mounted) {
        setState(() {
          _extractedFullName = licenseDetails.formattedFullName;
          _extractedLicenseNumber = licenseDetails.licenseNumber;
          _extractedLastName = licenseDetails.lastName;
          _extractedFirstName = licenseDetails.firstName;
          _extractedMiddleName = licenseDetails.middleName;
          _extractedNationality = licenseDetails.nationality;
          _extractedSex = licenseDetails.sex;
          _extractedDateOfBirth = licenseDetails.dateOfBirth;
          _extractedWeight = licenseDetails.weight;
          _extractedHeight = licenseDetails.height;
          _extractedAddress = licenseDetails.address;
          _extractedExpirationDate = licenseDetails.expirationDate;
          _extractedAgencyCode = licenseDetails.agencyCode;
          _extractedBloodType = licenseDetails.bloodType;
          _extractedEyeColor = licenseDetails.eyeColor;
          _extractedDLCodes = licenseDetails.dlCodes;
          _extractedConditions = licenseDetails.conditions;
        });

        // Auto-detect barangay from license address
        await _detectBarangayFromAddress();

        if (_extractedFullName != null && _extractedFullName!.isNotEmpty) {
          SnackbarHelper.showSuccess(context, 'License scanned successfully! Name: $_extractedFullName');
        } else {
          SnackbarHelper.showError(context, 'Could not detect all license details. Please verify the information.');
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Failed to scan license image: $e');
    } finally {
      if (mounted) setState(() => _isScanningLicense = false);
    }
  }

  Future<void> _detectBarangayFromAddress() async {
    if (_extractedAddress == null || _extractedAddress!.isEmpty) {
      print('No address to detect barangay from');
      return;
    }

    try {
      final barangayService = BarangayService();
      List<BarangayModel> allBarangays = await barangayService.getAllBarangays();

      // Fallback to static barangays if Firestore returns empty (permission issue)
      if (allBarangays.isEmpty) {
        print('Firestore barangays empty, using static list with proper IDs');
        allBarangays = _getStaticBarangaysWithProperIds();
      }

      print('Total barangays loaded: ${allBarangays.length}');
      print('Extracted address: $_extractedAddress');

      if (allBarangays.isEmpty) {
        print('No barangays available');
        return;
      }

      // Sort by name length (longest first) to prioritize specific matches
      // e.g., "San Nicolas Balas" should match before "San Nicolas"
      allBarangays.sort((a, b) => b.name.length.compareTo(a.name.length));
      
      print('Barangays sorted by length (longest first):');
      for (final b in allBarangays.take(5)) {
        print('  - ${b.name} (len=${b.name.length})');
      }

      // Normalize the extracted address
      final addressNormalized = _normalizeAddress(_extractedAddress!);
      print('Normalized address: "$addressNormalized"');

      BarangayModel? matchedBarangay;
      double bestMatchScore = 0.0;
      String bestMatchName = '';
      
      for (final barangay in allBarangays) {
        final matchScore = _calculateBarangayMatchScore(addressNormalized, barangay);
        
        // Log all scores for debugging
        if (matchScore > 0.3) {
          print('  [${barangay.name}] score=${matchScore.toStringAsFixed(3)} (id=${barangay.id})');
        }
        
        if (matchScore > bestMatchScore && matchScore >= 0.6) {
          bestMatchScore = matchScore;
          matchedBarangay = barangay;
          bestMatchName = barangay.name;
        }
      }
      
      print('FINAL SELECTION: $bestMatchName (score=${bestMatchScore.toStringAsFixed(3)})');

      if (mounted) {
        setState(() {
          _selectedBarangay = matchedBarangay;
        });
        
        if (matchedBarangay != null) {
          SnackbarHelper.showSuccess(context, 'Barangay detected: ${matchedBarangay.name}');
        } else {
          print('✗ No barangay matched with sufficient confidence');
        }
      }
    } catch (e) {
      print('Error detecting barangay from address: $e');
    }
  }

  /// Normalize address for better matching
  String _normalizeAddress(String address) {
    return address
        .toUpperCase()
        .replaceAll(RegExp(r',+'), ' ')
        .replaceAll(RegExp(r'\.+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('CONCEPCION', '')
        .replaceAll('TARLAC', '')
        .replaceAll('PHILIPPINES', '')
        .trim();
  }

  /// Calculate match score between address and barangay (0.0 to 1.0)
  double _calculateBarangayMatchScore(String address, BarangayModel barangay) {
    // Check for exact substring match FIRST (without variations)
    final baseName = barangay.name.toUpperCase().trim();
    if (_isExactPhraseMatch(address, baseName)) {
      print('    → EXACT BASE MATCH: "$baseName"');
      return 1.0; // Exact match gets max score, no bonus
    }
    
    // Get barangay name variations for partial matching
    final barangayNames = _getBarangayNameVariations(barangay.name);
    double maxPartialScore = 0.0;
    
    for (final name in barangayNames) {
      final score = _calculateNameMatchScore(address, name);
      if (score > maxPartialScore) {
        maxPartialScore = score;
      }
    }
    
    // Cap partial matches at 0.9 so exact matches always win
    // Add small length bonus for tie-breaking
    final cappedScore = maxPartialScore > 0.9 ? 0.9 : maxPartialScore;
    final lengthBonus = (barangay.name.length / 100.0) * 0.05; // Smaller bonus
    return cappedScore + lengthBonus;
  }

  /// Check if exact phrase exists in address
  bool _isExactPhraseMatch(String address, String phrase) {
    final addr = address.toUpperCase();
    final phr = phrase.toUpperCase();
    
    if (!addr.contains(phr)) return false;
    
    // Find all occurrences and verify word boundaries
    int index = 0;
    while ((index = addr.indexOf(phr, index)) != -1) {
      final before = index > 0 ? addr[index - 1] : ' ';
      final afterIndex = index + phr.length;
      final after = afterIndex < addr.length ? addr[afterIndex] : ' ';
      
      // Valid if preceded by space/start and followed by space/end/comma
      if ((before == ' ' || before == ',') && 
          (after == ' ' || after == ',' || afterIndex >= addr.length)) {
        return true;
      }
      index++;
    }
    return false;
  }

  /// Get all possible name variations for a barangay
  List<String> _getBarangayNameVariations(String originalName) {
    final variations = <String>{originalName.toUpperCase()};
    
    // Base name without parentheses
    var name = originalName.toUpperCase()
        .replaceAll(RegExp(r'\s*\([^)]*\)\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    variations.add(name);
    
    // Common abbreviation mappings
    final abbreviations = {
      'SANTA ': ['STA. ', 'STA ', 'SANTA '],
      'SANTO ': ['STO. ', 'STO ', 'SANTO '],
      'SAINT ': ['ST. ', 'ST ', 'SAINT '],
      'SAN ': ['SN. ', 'SN ', 'SAN '],
      'BARANGAY ': ['BRGY. ', 'BRGY ', 'BRY. ', 'BRY ', 'BARANGAY '],
    };
    
    // Generate variations with abbreviations
    for (final entry in abbreviations.entries) {
      if (name.contains(entry.key)) {
        for (final abbrev in entry.value) {
          variations.add(name.replaceAll(entry.key, abbrev));
        }
      }
    }
    
    // Handle "DE" variations
    if (name.contains(' DE ')) {
      variations.add(name.replaceAll(' DE ', ' '));
      variations.add(name.replaceAll(' DE ', ' DEL '));
    }
    
    // Handle hyphenated vs spaced names
    if (name.contains('-')) {
      variations.add(name.replaceAll('-', ' '));
    }
    if (name.contains(' ')) {
      variations.add(name.replaceAll(' ', '-'));
    }
    
    return variations.toList();
  }

  /// Calculate match score between address and a specific name variation
  double _calculateNameMatchScore(String address, String name) {
    // DIRECT SUBSTRING MATCH = highest priority
    // Check for exact match first with word boundaries
    final nameUpper = name.toUpperCase().trim();
    final addressUpper = address.toUpperCase().trim();
    
    // Check if the full name appears as a complete phrase in the address
    if (addressUpper.contains(nameUpper)) {
      // Verify it's not a partial word match by checking boundaries
      final index = addressUpper.indexOf(nameUpper);
      final before = index > 0 ? addressUpper[index - 1] : ' ';
      final after = (index + nameUpper.length < addressUpper.length) 
          ? addressUpper[index + nameUpper.length] 
          : ' ';
      
      // Accept if preceded/followed by space, comma, or string boundary
      final validBoundary = (before == ' ' || before == ',') && 
                           (after == ' ' || after == ',' || after == '\n' || after == '\r');
      
      if (validBoundary || index == 0 || (index + nameUpper.length) >= addressUpper.length) {
        print('    → EXACT MATCH: "$name" found in address');
        return 1.0;
      }
    }
    
    // Check individual words
    final nameWords = nameUpper.split(' ').where((w) => w.length > 2).toList();
    if (nameWords.isEmpty) return 0.0;
    
    final addressWords = addressUpper.split(' ').where((w) => w.length > 2).toList();
    
    double matchedWords = 0.0;
    int totalWeight = 0;
    
    for (final word in nameWords) {
      final weight = word.length > 4 ? 2 : 1;
      totalWeight += weight;
      
      // Exact word match
      if (addressWords.contains(word)) {
        matchedWords += weight;
      } else {
        // Partial word match (for typos/abbreviations)
        for (final addrWord in addressWords) {
          if (addrWord.length > 3 && 
              (addrWord.startsWith(word.substring(0, (word.length * 0.7).floor())) ||
               word.startsWith(addrWord.substring(0, (addrWord.length * 0.7).floor())))) {
            matchedWords += (weight * 0.5);
            break;
          }
        }
      }
    }
    
    final score = matchedWords / totalWeight;
    if (score > 0.5) {
      print('    → PARTIAL MATCH: "$name" score: ${score.toStringAsFixed(2)}');
    }
    return score;
  }

  /// Get static barangays with proper IDs that match Firestore (barangay_1, barangay_2, etc.)
  List<BarangayModel> _getStaticBarangaysWithProperIds() {
    final now = DateTime.now();
    const baseLatitude = 15.2833;
    const baseLongitude = 121.0167;

    // Create geofence helper
    List<List<double>> createGeofence(double lat, double lng, {double radiusDegrees = 0.01}) {
      return [
        [lat + radiusDegrees, lng - radiusDegrees],
        [lat + radiusDegrees, lng + radiusDegrees],
        [lat - radiusDegrees, lng + radiusDegrees],
        [lat - radiusDegrees, lng - radiusDegrees],
        [lat + radiusDegrees, lng - radiusDegrees],
      ];
    }

    return [
      BarangayModel(id: 'barangay_1', name: 'Alfonso', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude)),
      BarangayModel(id: 'barangay_2', name: 'Balutu', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.01, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.01, baseLongitude)),
      BarangayModel(id: 'barangay_3', name: 'Cafe', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.02, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.02, baseLongitude)),
      BarangayModel(id: 'barangay_4', name: 'Calius Gueco', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.03, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.03, baseLongitude)),
      BarangayModel(id: 'barangay_6', name: 'Caluluan', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.05, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.05, baseLongitude)),
      BarangayModel(id: 'barangay_7', name: 'Castillo', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude + 0.01, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude + 0.01)),
      BarangayModel(id: 'barangay_8', name: 'Corazon de Jesus', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude + 0.02, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude + 0.02)),
      BarangayModel(id: 'barangay_9', name: 'Culatingan', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude + 0.03, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude + 0.03)),
      BarangayModel(id: 'barangay_11', name: 'Dutung-A-Matas (Jefmin)', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude + 0.05, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude + 0.05)),
      BarangayModel(id: 'barangay_12', name: 'Green Village', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude - 0.01, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude - 0.01, baseLongitude)),
      BarangayModel(id: 'barangay_13', name: 'Lilibangan', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude - 0.02, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude - 0.02, baseLongitude)),
      BarangayModel(id: 'barangay_14', name: 'Mabilog', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude - 0.03, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude - 0.03, baseLongitude)),
      BarangayModel(id: 'barangay_15', name: 'Magao', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude - 0.04, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude - 0.04, baseLongitude)),
      BarangayModel(id: 'barangay_16', name: 'Malupa', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude - 0.05, longitude: baseLongitude, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude - 0.05, baseLongitude)),
      BarangayModel(id: 'barangay_17', name: 'Minane', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude - 0.01, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude - 0.01)),
      BarangayModel(id: 'barangay_18', name: 'Panalicsican', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude - 0.02, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude - 0.02)),
      BarangayModel(id: 'barangay_19', name: 'Pando', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude - 0.03, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude - 0.03)),
      BarangayModel(id: 'barangay_20', name: 'Parang', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude - 0.04, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude - 0.04)),
      BarangayModel(id: 'barangay_21', name: 'Parulung', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude, longitude: baseLongitude - 0.05, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude, baseLongitude - 0.05)),
      BarangayModel(id: 'barangay_22', name: 'Pitabunan', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.01, longitude: baseLongitude + 0.01, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.01, baseLongitude + 0.01)),
      BarangayModel(id: 'barangay_23', name: 'San Agustin (Murcia)', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.02, longitude: baseLongitude + 0.01, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.02, baseLongitude + 0.01)),
      BarangayModel(id: 'barangay_24', name: 'San Antonio', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.03, longitude: baseLongitude + 0.01, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.03, baseLongitude + 0.01)),
      BarangayModel(id: 'barangay_25', name: 'San Bartolome', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.04, longitude: baseLongitude + 0.01, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.04, baseLongitude + 0.01)),
      BarangayModel(id: 'barangay_26', name: 'San Francisco', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.05, longitude: baseLongitude + 0.01, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.05, baseLongitude + 0.01)),
      BarangayModel(id: 'barangay_27', name: 'San Isidro (Almendras)', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.01, longitude: baseLongitude + 0.02, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.01, baseLongitude + 0.02)),
      BarangayModel(id: 'barangay_28', name: 'San Jose (Poblacion)', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.02, longitude: baseLongitude + 0.02, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.02, baseLongitude + 0.02)),
      BarangayModel(id: 'barangay_29', name: 'San Juan (Castro)', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.03, longitude: baseLongitude + 0.02, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.03, baseLongitude + 0.02)),
      BarangayModel(id: 'barangay_31', name: 'San Nicolas Balas', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.05, longitude: baseLongitude + 0.02, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.05, baseLongitude + 0.02)),
      BarangayModel(id: 'barangay_32', name: 'San Nicolas (Poblacion)', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.01, longitude: baseLongitude + 0.03, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.01, baseLongitude + 0.03)),
      BarangayModel(id: 'barangay_33', name: 'Sta. Cruz', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.02, longitude: baseLongitude + 0.03, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.02, baseLongitude + 0.03)),
      BarangayModel(id: 'barangay_34', name: 'Sta. Maria', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.03, longitude: baseLongitude + 0.03, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.03, baseLongitude + 0.03)),
      BarangayModel(id: 'barangay_35', name: 'Sta. Monica', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.04, longitude: baseLongitude + 0.03, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.04, baseLongitude + 0.03)),
      BarangayModel(id: 'barangay_36', name: 'Sta. Rita', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.05, longitude: baseLongitude + 0.03, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.05, baseLongitude + 0.03)),
      BarangayModel(id: 'barangay_37', name: 'Santa Rosa', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.01, longitude: baseLongitude + 0.04, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.01, baseLongitude + 0.04)),
      BarangayModel(id: 'barangay_38', name: 'Santiago', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.02, longitude: baseLongitude + 0.04, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.02, baseLongitude + 0.04)),
      BarangayModel(id: 'barangay_39', name: 'Santo Cristo', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.03, longitude: baseLongitude + 0.04, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.03, baseLongitude + 0.04)),
      BarangayModel(id: 'barangay_40', name: 'Santo Niño', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.04, longitude: baseLongitude + 0.04, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.04, baseLongitude + 0.04)),
      BarangayModel(id: 'barangay_41', name: 'Santo Rosario (Magunting)', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.05, longitude: baseLongitude + 0.04, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.05, baseLongitude + 0.04)),
      BarangayModel(id: 'barangay_42', name: 'San Vicente (Calius/Corba)', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.01, longitude: baseLongitude + 0.05, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.01, baseLongitude + 0.05)),
      BarangayModel(id: 'barangay_44', name: 'Talimunduc San Miguel', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.03, longitude: baseLongitude + 0.05, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.03, baseLongitude + 0.05)),
      BarangayModel(id: 'barangay_46', name: 'Tinang', municipality: 'Concepcion', province: 'Tarlac', latitude: baseLatitude + 0.05, longitude: baseLongitude + 0.05, createdAt: now, geofenceCoordinates: createGeofence(baseLatitude + 0.05, baseLongitude + 0.05)),
    ];
  }

  Future<void> _proceedToVerification() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreedToTerms) {
      if (mounted) {
        final agreed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => const TermsAndConditionsScreen(userRole: 'driver'),
          ),
        );
        if (agreed != true) return;
        setState(() => _agreedToTerms = true);
      }
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
      
      // Check connectivity before proceeding
      if (!await connectivityService.checkConnectivity(context)) {
        setState(() => _isLoading = false);
        return;
      }
      
      // Check if email or phone is already registered before proceeding
      await authService.checkIfEmailOrPhoneExists(
        _emailController.text.trim(),
        _phoneController.text.trim(),
      );
      
      setState(() => _currentStep = DriverRegistrationStep.verification);
      await _sendVerification();
    } catch (e) {
      if (mounted) {
        final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
        final errorMessage = connectivityService.getErrorMessage(e);
        SnackbarHelper.showError(context, errorMessage);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendVerification() async {
    setState(() {
      _isVerificationLoading = true;
      _verificationError = null;
    });

    try {
      bool success = false;
      if (_selectedVerificationType == VerificationType.sms) {
        success = await _verificationService.sendSMSVerification(_phoneController.text.trim());
      } else {
        success = await _verificationService.sendEmailVerification(_emailController.text.trim());
      }

      if (success) {
        SnackbarHelper.showSuccess(context, 'Verification code sent!');
      } else {
        throw Exception('Failed to send verification code.');
      }
    } catch (e) {
      setState(() => _verificationError = e.toString());
    } finally {
      setState(() => _isVerificationLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationCode.length != 6) {
      setState(() => _verificationError = 'Enter 6-digit code');
      return;
    }

    setState(() {
      _isVerificationLoading = true;
      _verificationError = null;
    });

    try {
      bool success = false;
      if (_selectedVerificationType == VerificationType.sms) {
        success = await _verificationService.verifySMSCode(_phoneController.text.trim(), _verificationCode);
      } else {
        success = await _verificationService.verifyEmailCode(_emailController.text.trim(), _verificationCode);
      }

      if (success) {
        setState(() => _currentStep = DriverRegistrationStep.licenseInfo);
      } else {
        setState(() => _verificationError = 'Invalid code. Try again.');
      }
    } catch (e) {
      setState(() => _verificationError = 'Verification failed.');
    } finally {
      setState(() => _isVerificationLoading = false);
    }
  }

  Future<void> _completeRegistration() async {
    if (_plateNumberImage == null || _licenseNumberImage == null) {
      SnackbarHelper.showError(context, 'Please capture both Plate and License photos');
      return;
    }

    // Check that license details were extracted
    if (_extractedFullName == null || _extractedFullName!.isEmpty) {
      SnackbarHelper.showError(context, 'Please upload and scan your driver\'s license first');
      return;
    }

    // Check that barangay was detected
    if (_selectedBarangay == null) {
      SnackbarHelper.showError(context, 'Barangay could not be detected from your license address. Please ensure your license has a valid address from Concepcion, Tarlac.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final connectivityService = Provider.of<ConnectivityService>(context, listen: false);

      // Check connectivity before proceeding
      if (!await connectivityService.checkConnectivity(context)) {
        setState(() => _isLoading = false);
        return;
      }

      final firestoreService = FirestoreService();

      // Create auth user with extracted name from license
      await authService.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _extractedFullName!,
        phone: _phoneController.text.trim(),
        role: UserRole.driver,
        barangayId: _selectedBarangay!.id,
        barangayName: _selectedBarangay!.name,
        skipExistsCheck: true,
      );

      // Upload documents
      final plateUrl = await firestoreService.uploadDriverDocument(
        authService.currentUser!.uid, 'plate', _plateNumberImage!
      );
      final licenseUrl = await firestoreService.uploadDriverDocument(
        authService.currentUser!.uid, 'license', _licenseNumberImage!
      );

      // Create driver profile with all extracted license details
      final driverModel = DriverModel(
        id: authService.currentUser!.uid,
        userId: authService.currentUser!.uid,
        name: _extractedFullName!,
        vehicleType: 'Tricycle',
        plateNumber: _tricyclePlateController.text.trim(),
        licenseNumber: _extractedLicenseNumber ?? '',
        plateNumberImageUrl: plateUrl,
        licenseNumberImageUrl: licenseUrl,
        barangayId: _selectedBarangay!.id,
        barangayName: _selectedBarangay!.name,
        tricyclePlateNumber: _tricyclePlateController.text.trim(),
        driverLicenseNumber: _extractedLicenseNumber,
        isApproved: false,
        isActive: false,
        // License details from OCR
        lastName: _extractedLastName,
        firstName: _extractedFirstName,
        middleName: _extractedMiddleName,
        nationality: _extractedNationality,
        sex: _extractedSex,
        dateOfBirth: _extractedDateOfBirth,
        weight: _extractedWeight,
        height: _extractedHeight,
        address: _extractedAddress,
        expirationDate: _extractedExpirationDate,
        agencyCode: _extractedAgencyCode,
        bloodType: _extractedBloodType,
        eyeColor: _extractedEyeColor,
        dlCodes: _extractedDLCodes,
        conditions: _extractedConditions,
      );

      await firestoreService.createDriverProfile(driverModel);

      setState(() => _currentStep = DriverRegistrationStep.complete);

    } catch (e) {
      if (mounted) {
        final connectivityService = Provider.of<ConnectivityService>(context, listen: false);
        final errorMessage = connectivityService.getErrorMessage(e);
        SnackbarHelper.showError(context, 'Registration failed: $errorMessage');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_currentStep == DriverRegistrationStep.complete ? '' : 'Be a Driver'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (_currentStep == DriverRegistrationStep.userInfo) {
              Navigator.pop(context);
            } else if (_currentStep == DriverRegistrationStep.verification) {
              setState(() => _currentStep = DriverRegistrationStep.userInfo);
            } else if (_currentStep == DriverRegistrationStep.licenseInfo) {
              setState(() => _currentStep = DriverRegistrationStep.verification);
            } else if (_currentStep == DriverRegistrationStep.vehicleInfo) {
              setState(() => _currentStep = DriverRegistrationStep.licenseInfo);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _buildCurrentStep(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case DriverRegistrationStep.userInfo:
        return _buildUserInfoStep();
      case DriverRegistrationStep.verification:
        return _buildVerificationStep();
      case DriverRegistrationStep.licenseInfo:
        return _buildLicenseInfoStep();
      case DriverRegistrationStep.vehicleInfo:
        return _buildVehicleInfoStep();
      case DriverRegistrationStep.complete:
        return _buildCompleteStep();
    }
  }

  Widget _buildUserInfoStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),

          // Brand hero
          Center(
            child: Column(
              children: [
                const TricycleLogo(size: 140, showText: false, showShadow: false, plain: true),
                const SizedBox(height: 20),
                const Text(
                  'Become a Pasakay Driver',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drive with confidence and earn more every day',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 36),

          _buildInputField(
            label: 'Email Address',
            controller: _emailController,
            hint: 'juan@driver.com',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || !v.contains('@')) ? 'Valid email is required' : null,
          ),
          const SizedBox(height: 20),
          _buildInputField(
            label: 'Phone Number',
            controller: _phoneController,
            hint: '09xxxxxxxxx',
            icon: Icons.phone_android_rounded,
            keyboardType: TextInputType.phone,
            validator: (v) => (v == null || v.length < 11) ? 'Enter valid PH number' : null,
          ),
          const SizedBox(height: 20),

          _buildInputField(
            label: 'Password',
            controller: _passwordController,
            hint: 'Minimum 8 characters',
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            validator: (v) => (v == null || v.length < 8) ? 'Password too short' : null,
          ),
          const SizedBox(height: 20),
          _buildInputField(
            label: 'Confirm Password',
            controller: _confirmPasswordController,
            hint: 'Repeat your password',
            icon: Icons.lock_reset_rounded,
            isPassword: true,
            validator: (v) => (v != _passwordController.text) ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 32),

          InkWell(
            onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Checkbox(
                  value: _agreedToTerms,
                  onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                  activeColor: AppTheme.primaryGreen,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Color(0xFF4A4A4A)),
                      children: [
                        const TextSpan(text: 'I agree to the '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const TermsAndConditionsScreen(userRole: 'driver')),
                            ),
                            child: const Text(
                              'Driver Terms & Conditions',
                              style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: (_isLoading || !_agreedToTerms) ? null : _proceedToVerification,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 64),
              shape: const StadiumBorder(),
              elevation: 8,
              shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
            ),
            child: _isLoading 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildVerificationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Text(
          'Verification Code 🔐',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ve sent a verification code to\n${_emailController.text}',
          style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.5),
        ),
        const SizedBox(height: 48),

        VerificationCodeInput(
          onCodeChanged: (code) {
            setState(() {
              _verificationCode = code;
              _verificationError = null;
            });
            if (code.length == 6) _verifyCode();
          },
          onResend: _sendVerification,
          isLoading: _isVerificationLoading,
          errorMessage: _verificationError,
          remainingTime: _verificationService.getRemainingTime(_emailController.text.trim()),
        ),

        const SizedBox(height: 40),
        
        ElevatedButton(
          onPressed: (_isVerificationLoading || _verificationCode.length != 6) ? null : _verifyCode,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 64),
            shape: const StadiumBorder(),
            elevation: 8,
            shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
          ),
          child: _isVerificationLoading 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Verify Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
      ],
    );
  }

  Widget _buildLicenseInfoStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Driver\'s License',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload your Philippine Driver\'s License and verify the extracted details',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 30),

          // License Upload Card
          _buildImageUploadCard(
            title: 'Driver\'s License',
            subtitle: 'Tap to capture your license',
            icon: Icons.badge_rounded,
            image: _licenseNumberImage,
            onTap: () => _pickImage(false),
          ),

          if (_isScanningLicense)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: AppTheme.primaryGreen),
                    const SizedBox(height: 12),
                    Text('Scanning license...', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),

          // Editable Extracted License Details
          if (_extractedFullName != null && _extractedFullName!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 30),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.edit_note_rounded, color: AppTheme.primaryGreen),
                      const SizedBox(width: 8),
                      const Text(
                        'Review & Edit Details',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppTheme.primaryGreen),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Please verify and correct if needed',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 16),
                  
                  // Editable Fields
                  _buildEditableField('Last Name', (v) => _extractedLastName = v, _extractedLastName ?? ''),
                  const SizedBox(height: 12),
                  _buildEditableField('First Name', (v) => _extractedFirstName = v, _extractedFirstName ?? ''),
                  const SizedBox(height: 12),
                  _buildEditableField('Middle Name', (v) => _extractedMiddleName = v, _extractedMiddleName ?? '', isOptional: true),
                  const SizedBox(height: 12),
                  _buildEditableField('License Number', (v) => _extractedLicenseNumber = v, _extractedLicenseNumber ?? ''),
                  const SizedBox(height: 12),
                  _buildEditableField('Date of Birth', (v) => _extractedDateOfBirth = v, _extractedDateOfBirth ?? ''),
                  const SizedBox(height: 12),
                  _buildEditableField('Expiration Date', (v) => _extractedExpirationDate = v, _extractedExpirationDate ?? ''),
                  const SizedBox(height: 12),
                  _buildEditableField('Nationality', (v) => _extractedNationality = v, _extractedNationality ?? 'PHL', isOptional: true),
                  const SizedBox(height: 12),
                  _buildEditableField('Sex (M/F)', (v) => _extractedSex = v, _extractedSex ?? '', isOptional: true),
                  const SizedBox(height: 12),
                  _buildEditableField('Agency Code', (v) => _extractedAgencyCode = v, _extractedAgencyCode ?? '', isOptional: true),
                  const SizedBox(height: 12),
                  _buildEditableField('DL Codes', (v) => _extractedDLCodes = v, _extractedDLCodes ?? '', isOptional: true),
                  const SizedBox(height: 12),
                  _buildEditableField('Address', (v) => _extractedAddress = v, _extractedAddress ?? '', isOptional: true, isMultiline: true),
                  const SizedBox(height: 12),
                  // Display detected barangay
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _selectedBarangay != null ? AppTheme.primaryGreen.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedBarangay != null ? AppTheme.primaryGreen.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.location_city,
                              color: _selectedBarangay != null ? AppTheme.primaryGreen : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Detected Barangay',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _selectedBarangay?.name ?? 'No barangay detected from address',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: _selectedBarangay != null ? const Color(0xFF1A1A1A) : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_selectedBarangay != null)
                              const Icon(Icons.check_circle, color: AppTheme.primaryGreen, size: 20),
                          ],
                        ),
                        // Show manual selector button when no barangay detected
                        if (_selectedBarangay == null) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final result = await showDialog<BarangayModel>(
                                  context: context,
                                  builder: (context) => const _BarangaySelectorDialog(),
                                );
                                if (result != null && mounted) {
                                  setState(() {
                                    _selectedBarangay = result;
                                  });
                                  SnackbarHelper.showSuccess(context, 'Barangay selected: ${result.name}');
                                }
                              },
                              icon: const Icon(Icons.location_on_outlined, size: 18),
                              label: const Text('Select Barangay Manually'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange.shade800,
                                side: BorderSide(color: Colors.orange.shade300),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: (_licenseNumberImage == null || _isScanningLicense) ? null : () {
              if (_extractedFirstName == null || _extractedFirstName!.isEmpty ||
                  _extractedLastName == null || _extractedLastName!.isEmpty) {
                SnackbarHelper.showError(context, 'Please enter your name to continue');
                return;
              }
              if (_extractedLicenseNumber == null || _extractedLicenseNumber!.isEmpty) {
                SnackbarHelper.showError(context, 'Please enter your license number to continue');
                return;
              }
              if (_selectedBarangay == null) {
                SnackbarHelper.showError(context, 'Barangay could not be detected from address. Please check your license address.');
                return;
              }
              // Update full name from edited fields
              _extractedFullName = '$_extractedLastName, $_extractedFirstName ${_extractedMiddleName ?? ''}'.trim();
              setState(() => _currentStep = DriverRegistrationStep.vehicleInfo);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 64),
              shape: const StadiumBorder(),
              elevation: 8,
              shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildEditableField(String label, Function(String) onChanged, String initialValue, {bool isOptional = false, bool isMultiline = false}) {
    final controller = TextEditingController(text: initialValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label + (isOptional ? ' (Optional)' : ' *'),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isOptional ? Colors.grey.shade500 : const Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          onChanged: onChanged,
          maxLines: isMultiline ? 2 : 1,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'Enter $label',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: isOptional ? null : (v) => (v == null || v.isEmpty) ? 'Required' : null,
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isMultiline = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
              maxLines: isMultiline ? 3 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfoStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Vehicle Documents',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload your documents for validation',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 32),

          _buildImageUploadCard(
            title: 'Tricycle Plate',
            subtitle: 'Capture your plate number',
            icon: Icons.confirmation_number_rounded,
            image: _plateNumberImage,
            onTap: () => _pickImage(true),
          ),

          const SizedBox(height: 32),

          _buildInputField(
            label: 'Plate Number',
            controller: _tricyclePlateController,
            hint: 'ABC-1234',
            icon: Icons.confirmation_number_rounded,
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),

          if (_extractedLicenseNumber != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.badge_outlined, color: Colors.grey.shade400),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'License Number (Auto-detected)',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                          Text(
                            _extractedLicenseNumber!,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle, color: AppTheme.primaryGreen, size: 20),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 40),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreenLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: AppTheme.primaryGreen, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Approval Notice', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        'Your documents will be reviewed by our team. Activation usually takes 24-48 hours.',
                        style: TextStyle(fontSize: 13, color: AppTheme.primaryGreen.withOpacity(0.8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: _isLoading ? null : _completeRegistration,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 64),
              shape: const StadiumBorder(),
              elevation: 8,
              shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
            ),
            child: _isLoading 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Submit Application', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    return Column(
      children: [
        const SizedBox(height: 100),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.primaryGreenLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.pending_actions_rounded, size: 80, color: AppTheme.primaryGreen),
        ),
        const SizedBox(height: 40),
        const Text(
          'Processing!',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 16),
        Text(
          'Thank you, ${_extractedFullName ?? 'Driver'}!\nYour application is now being reviewed.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600, height: 1.6),
        ),
        const SizedBox(height: 60),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pushReplacementNamed('/driver'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 64),
            shape: const StadiumBorder(),
            elevation: 8,
            shadowColor: AppTheme.primaryGreen.withOpacity(0.3),
          ),
          child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
      ],
    );
  }

  Widget _buildStepProgress(int current) {
    return Row(
      children: List.generate(4, (index) {
        bool isActive = index <= current;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primaryGreen : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A1A1A)),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword && (label.contains('Confirm') ? _obscureConfirmPassword : _obscurePassword),
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w500),
            prefixIcon: Icon(icon, color: Colors.grey.shade400, size: 20),
            suffixIcon: isPassword ? IconButton(
              icon: Icon((label.contains('Confirm') ? _obscureConfirmPassword : _obscurePassword) ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.grey, size: 20),
              onPressed: () => setState(() {
                if (label.contains('Confirm')) {
                  _obscureConfirmPassword = !_obscureConfirmPassword;
                } else {
                  _obscurePassword = !_obscurePassword;
                }
              }),
            ) : null,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFFF1F1F1), width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.red, width: 1.5)),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Colors.red, width: 2)),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildImageUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required XFile? image,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: image != null ? AppTheme.primaryGreen.withOpacity(0.3) : const Color(0xFFF1F1F1), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: image != null ? AppTheme.primaryGreenLight : const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: image != null 
                  ? FutureBuilder<Uint8List>(
                      future: image.readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen),
                            ),
                          );
                        }
                        return const Center(child: CircularProgressIndicator());
                      },
                    )
                  : Icon(icon, color: Colors.grey.shade400, size: 30),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(image != null ? 'Tap to change photo' : subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                  ],
                ),
              ),
              if (image != null)
                const Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 24)
              else
                Icon(Icons.add_a_photo_rounded, color: Colors.grey.shade300, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarangaySelectorDialog extends StatefulWidget {
  const _BarangaySelectorDialog({Key? key}) : super(key: key);

  @override
  State<_BarangaySelectorDialog> createState() => _BarangaySelectorDialogState();
}

class _BarangaySelectorDialogState extends State<_BarangaySelectorDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<BarangayModel> _barangays = [];
  List<BarangayModel> _filteredBarangays = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadBarangays();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBarangays() async {
    try {
      // Try Firestore first
      final barangayService = BarangayService();
      var barangays = await barangayService.getAllBarangays();
      
      // Fallback to static if Firestore is empty
      if (barangays.isEmpty) {
        barangays = _getStaticBarangaysForSelector();
      }
      
      if (mounted) {
        setState(() {
          _barangays = barangays.where((b) => b.isActive).toList();
          _filteredBarangays = _barangays;
          _isLoading = false;
        });
      }
    } catch (e) {
      // On error, use static fallback
      if (mounted) {
        setState(() {
          _barangays = _getStaticBarangaysForSelector();
          _filteredBarangays = _barangays;
          _isLoading = false;
        });
      }
    }
  }

  List<BarangayModel> _getStaticBarangaysForSelector() {
    final now = DateTime.now();
    return [
      BarangayModel(id: 'barangay_1', name: 'Alfonso', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_2', name: 'Balutu', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_3', name: 'Cafe', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_4', name: 'Calius Gueco', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_6', name: 'Caluluan', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_7', name: 'Castillo', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_8', name: 'Corazon de Jesus', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_9', name: 'Culatingan', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_11', name: 'Dutung-A-Matas (Jefmin)', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_12', name: 'Green Village', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_13', name: 'Lilibangan', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_14', name: 'Mabilog', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_15', name: 'Magao', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_16', name: 'Malupa', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_17', name: 'Minane', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_18', name: 'Panalicsican', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_19', name: 'Pando', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_20', name: 'Parang', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_21', name: 'Parulung', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_22', name: 'Pitabunan', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_23', name: 'San Agustin (Murcia)', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_24', name: 'San Antonio', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_25', name: 'San Bartolome', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_26', name: 'San Francisco', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_27', name: 'San Isidro (Almendras)', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_28', name: 'San Jose (Poblacion)', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_29', name: 'San Juan (Castro)', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_31', name: 'San Nicolas Balas', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_32', name: 'San Nicolas (Poblacion)', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_33', name: 'Sta. Cruz', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_34', name: 'Sta. Maria', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_35', name: 'Sta. Monica', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_36', name: 'Sta. Rita', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_37', name: 'Santa Rosa', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_38', name: 'Santiago', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_39', name: 'Santo Cristo', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_40', name: 'Santo Niño', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_41', name: 'Santo Rosario (Magunting)', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_42', name: 'San Vicente (Calius/Corba)', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_44', name: 'Talimunduc San Miguel', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
      BarangayModel(id: 'barangay_46', name: 'Tinang', municipality: 'Concepcion', province: 'Tarlac', isActive: true, createdAt: now),
    ];
  }

  void _filterBarangays(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      _filteredBarangays = _barangays.where((b) {
        final name = b.name.toLowerCase();
        final municipality = b.municipality.toLowerCase();
        return name.contains(_searchQuery) || municipality.contains(_searchQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        padding: const EdgeInsets.all(24),
        height: 600,
        child: Column(
          children: [
            const Text(
              'Select Your Barangay',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the barangay where you live',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              onChanged: _filterBarangays,
              decoration: InputDecoration(
                hintText: 'Search barangay...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterBarangays('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppTheme.primaryGreen),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredBarangays.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? 'No barangays found' : 'No results for "$_searchQuery"',
                            style: TextStyle(color: Colors.grey.shade500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredBarangays.length,
                      itemBuilder: (context, index) {
                        final b = _filteredBarangays[index];
                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.primaryGreen.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.location_on, color: AppTheme.primaryGreen, size: 20),
                          ),
                          title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${b.municipality}, ${b.province}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          onTap: () => Navigator.pop(context, b),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
