import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Model class to hold extracted license details
class LicenseDetails {
  final String? lastName;
  final String? firstName;
  final String? middleName;
  final String? nationality;
  final String? sex;
  final String? dateOfBirth;
  final String? weight;
  final String? height;
  final String? address;
  final String? licenseNumber;
  final String? expirationDate;
  final String? agencyCode;
  final String? bloodType;
  final String? eyeColor;
  final String? dlCodes;
  final String? conditions;
  final String? fullName;

  LicenseDetails({
    this.lastName,
    this.firstName,
    this.middleName,
    this.nationality,
    this.sex,
    this.dateOfBirth,
    this.weight,
    this.height,
    this.address,
    this.licenseNumber,
    this.expirationDate,
    this.agencyCode,
    this.bloodType,
    this.eyeColor,
    this.dlCodes,
    this.conditions,
    this.fullName,
  });

  /// Get formatted full name from license details
  String get formattedFullName {
    if (lastName != null && firstName != null) {
      if (middleName != null && middleName!.isNotEmpty) {
        return '$lastName, $firstName $middleName';
      }
      return '$lastName, $firstName';
    }
    return fullName ?? '';
  }
}

/// Service to scan Philippines driver's license and extract details using OCR
class LicenseScanningService {
  static final LicenseScanningService _instance = LicenseScanningService._internal();
  factory LicenseScanningService() => _instance;
  LicenseScanningService._internal();

  TextRecognizer? _textRecognizer;
  bool _isWeb = false;

  void initialize() {
    // Check if running on web
    _isWeb = kIsWeb;
    
    if (!_isWeb) {
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    }
  }

  void dispose() {
    _textRecognizer?.close();
  }

  bool get isSupported => !_isWeb;

  /// Process driver's license image and extract all relevant details
  Future<LicenseDetails> scanLicense(String imagePath) async {
    // Check if running on web platform
    if (_isWeb) {
      throw UnsupportedError(
        'License scanning is not supported on web platform. '
        
      );
    }

    // Check if text recognizer is initialized
    if (_textRecognizer == null) {
      initialize();
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer!.processImage(inputImage);

      // DEBUG: Print all extracted text
      debugPrint('========== OCR RAW TEXT ==========');
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          debugPrint('Line: ${line.text}');
        }
      }
      debugPrint('==================================');

      // Extract all license details from recognized text
      final licenseDetails = _extractLicenseDetails(recognizedText);
      
      // DEBUG: Print extracted details
      debugPrint('========== EXTRACTED DETAILS ==========');
      debugPrint('Last Name: ${licenseDetails.lastName}');
      debugPrint('First Name: ${licenseDetails.firstName}');
      debugPrint('Middle Name: ${licenseDetails.middleName}');
      debugPrint('License Number: ${licenseDetails.licenseNumber}');
      debugPrint('DOB: ${licenseDetails.dateOfBirth}');
      debugPrint('Expiration: ${licenseDetails.expirationDate}');
      debugPrint('Nationality: ${licenseDetails.nationality}');
      debugPrint('Sex: ${licenseDetails.sex}');
      debugPrint('Address: ${licenseDetails.address}');
      debugPrint('=======================================');

      return licenseDetails;
    } catch (e) {
      throw Exception('Failed to scan license: $e');
    }
  }

  /// Process plate number image and extract the plate number
  Future<String?> scanPlateNumber(String imagePath) async {
    if (_isWeb) {
      throw UnsupportedError(
        'Plate scanning is not supported on web platform. '
        'Please test on Android or iOS device/emulator.'
      );
    }

    if (_textRecognizer == null) {
      initialize();
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer!.processImage(inputImage);

      // Get all text lines
      final List<String> allLines = [];
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          allLines.add(line.text.trim());
        }
      }

      final String allText = allLines.join(' ');
      debugPrint('========== PLATE OCR RAW TEXT ==========');
      for (String line in allLines) {
        debugPrint('Line: $line');
      }
      debugPrint('=======================================');

      // Philippine plate number patterns
      final List<RegExp> platePatterns = [
        // Standard format: ABC-1234 or ABC 1234
        RegExp(r'\b([A-Z]{2,3}[-\s]?\d{3,4})\b'),
        // New format: N12345678
        RegExp(r'\b(N\d{7,8})\b'),
        // Alternative: 123-ABC or 123 ABC (numbers first)
        RegExp(r'\b(\d{3,4}[-\s]?[A-Z]{2,3})\b'),
      ];

      String? plateNumber;

      // Try each pattern
      for (final pattern in platePatterns) {
        final match = pattern.firstMatch(allText);
        if (match != null) {
          plateNumber = match.group(1);
          // Normalize: remove spaces, add dash if missing
          if (plateNumber != null) {
            plateNumber = plateNumber.replaceAll(' ', '');
            if (!plateNumber.contains('-') && plateNumber.length >= 5) {
              // Insert dash between letters and numbers
              final letterPart = plateNumber.replaceAll(RegExp(r'[^A-Z]'), '');
              final numberPart = plateNumber.replaceAll(RegExp(r'[^0-9]'), '');
              if (letterPart.isNotEmpty && numberPart.isNotEmpty) {
                plateNumber = '$letterPart-$numberPart';
              }
            }
          }
          break;
        }
      }

      debugPrint('========== EXTRACTED PLATE ==========');
      debugPrint('Plate Number: $plateNumber');
      debugPrint('=====================================');

      return plateNumber;
    } catch (e) {
      throw Exception('Failed to scan plate: $e');
    }
  }

  /// Extract license details from recognized text
  LicenseDetails _extractLicenseDetails(RecognizedText recognizedText) {
    String? lastName;
    String? firstName;
    String? middleName;
    String? nationality;
    String? sex;
    String? dateOfBirth;
    String? weight;
    String? height;
    String? address;
    String? licenseNumber;
    String? expirationDate;
    String? agencyCode;
    String? bloodType;
    String? eyeColor;
    String? dlCodes;
    String? conditions;
    String? fullName;

    // Get all text lines for processing
    final List<String> allLines = [];
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        allLines.add(line.text.trim());
      }
    }

    final String allText = allLines.join(' ');

    // Extract License Number (Format: C24-21-201302 or N01-12-123456 or similar)
    // Pattern: 1-3 letters followed by digits, then 2 digit year, then 6 digit number
    final List<RegExp> licensePatterns = [
      RegExp(r'\b([A-Z]\d{1,3}-\d{2}-\d{6})\b'),  // Standard format: C24-21-201302
      RegExp(r'\b([A-Z]{1,3}\d{2}-\d{2}-\d{6})\b'), // Alternative: AB12-21-201302
      RegExp(r'\b([A-Z]\d{2,3}\d{2}\d{6})\b'),     // No dashes: C2421201302
    ];
    
    for (final pattern in licensePatterns) {
      final match = pattern.firstMatch(allText);
      if (match != null) {
        licenseNumber = match.group(1);
        // Normalize format: add dashes if missing
        if (licenseNumber != null && !licenseNumber.contains('-')) {
          if (licenseNumber.length >= 9) {
            final agency = licenseNumber.substring(0, licenseNumber.length - 8);
            final year = licenseNumber.substring(licenseNumber.length - 8, licenseNumber.length - 6);
            final number = licenseNumber.substring(licenseNumber.length - 6);
            licenseNumber = '$agency-$year-$number';
          }
        }
        break;
      }
    }

    // Extract all dates (Format: YYYY/MM/DD)
    final RegExp dateRegExp = RegExp(r'(20\d{2}/\d{2}/\d{2})');
    final allDates = dateRegExp.allMatches(allText).map((m) => m.group(1)!).toList();
    
    // Try to distinguish DOB vs Expiration
    // DOB is usually in the 1900s-2000s for drivers
    // Expiration is usually current year + 3-5 years
    final now = DateTime.now();
    final currentYear = now.year;
    
    for (final date in allDates) {
      final parts = date.split('/');
      if (parts.length == 3) {
        final year = int.tryParse(parts[0]) ?? 0;
        
        // If year is reasonable for DOB (16+ years ago), it's likely DOB
        if (year >= 1940 && year <= now.year - 16) {
          if (dateOfBirth == null) dateOfBirth = date;
        }
        // If year is in the future or recent, it's likely expiration
        else if (year >= currentYear) {
          if (expirationDate == null) expirationDate = date;
        }
      }
    }
    
    // If we only found one date, make smart guess based on context
    if (dateOfBirth == null && expirationDate == null && allDates.isNotEmpty) {
      // Look for context clues
      final lowerText = allText.toLowerCase();
      for (final date in allDates) {
        final year = int.tryParse(date.split('/')[0]) ?? 0;
        if (lowerText.contains('birth') && year < currentYear - 16) {
          dateOfBirth = date;
        } else if (lowerText.contains('expir') && year >= currentYear) {
          expirationDate = date;
        }
      }
    }

    // Extract Nationality (usually PHL)
    final RegExp nationalityRegExp = RegExp(r'\bPHL\b|\bFIL\b', caseSensitive: false);
    final nationalityMatch = nationalityRegExp.firstMatch(allText);
    if (nationalityMatch != null) {
      nationality = nationalityMatch.group(0)?.toUpperCase();
    }

    // Extract Sex (M or F)
    final RegExp sexRegExp = RegExp(r'\bSex\b.*?\b([MF])\b', caseSensitive: false);
    final sexMatch = sexRegExp.firstMatch(allText);
    if (sexMatch != null) {
      sex = sexMatch.group(1);
    } else {
      // Try alternative pattern - look for standalone M or F near other fields
      for (int i = 0; i < allLines.length; i++) {
        final line = allLines[i].toUpperCase();
        if (line.contains('SEX') || line.contains('NATIONALITY')) {
          // Check next few lines for M or F
          for (int j = i; j < min(i + 3, allLines.length); j++) {
            final checkLine = allLines[j].trim();
            if (checkLine == 'M' || checkLine == 'F') {
              sex = checkLine;
              break;
            }
            // Check for M or F within the line
            final sexInLine = RegExp(r'\b([MF])\b').firstMatch(checkLine);
            if (sexInLine != null && checkLine.length < 5) {
              sex = sexInLine.group(1);
              break;
            }
          }
          if (sex != null) break;
        }
      }
    }

    // Extract Weight (Format: XX kg or just XX)
    final RegExp weightRegExp = RegExp(r'(\d{2,3})\s*kg', caseSensitive: false);
    final weightMatch = weightRegExp.firstMatch(allText);
    if (weightMatch != null) {
      weight = weightMatch.group(1);
    }

    // Extract Height (Format: X.X m or X.XX m)
    final RegExp heightRegExp = RegExp(r'(\d\.\d{1,2})\s*m', caseSensitive: false);
    final heightMatch = heightRegExp.firstMatch(allText);
    if (heightMatch != null) {
      height = heightMatch.group(1);
    }

    // Extract Agency Code (Format: C24 or similar)
    final RegExp agencyCodeRegExp = RegExp(r'\bAgency\s*Code\b.*?\b([A-Z]\d{2,3})\b', caseSensitive: false);
    final agencyMatch = agencyCodeRegExp.firstMatch(allText);
    if (agencyMatch != null) {
      agencyCode = agencyMatch.group(1);
    } else if (licenseNumber != null && licenseNumber.contains('-')) {
      // Extract from license number (e.g., C24 from C24-21-201302)
      agencyCode = licenseNumber.split('-').first;
    }

    // Extract Blood Type
    final RegExp bloodTypeRegExp = RegExp(r'\bBlood\s*Type\b.*?\b([ABO]\+?-?)\b', caseSensitive: false);
    final bloodTypeMatch = bloodTypeRegExp.firstMatch(allText);
    if (bloodTypeMatch != null) {
      bloodType = bloodTypeMatch.group(1);
    } else {
      // Look for standalone blood type pattern
      final RegExp standaloneBloodRegExp = RegExp(r'\b([ABO][\+\-]?)\b');
      for (String line in allLines) {
        final match = standaloneBloodRegExp.firstMatch(line);
        if (match != null && line.length < 10) {
          bloodType = match.group(1);
          break;
        }
      }
    }

    // Extract Eye Color
    final RegExp eyeColorRegExp = RegExp(r'\bEye\s*Color\b.*?\b([A-Z]{3,10})\b', caseSensitive: false);
    final eyeMatch = eyeColorRegExp.firstMatch(allText);
    if (eyeMatch != null) {
      eyeColor = eyeMatch.group(1);
    } else {
      // Look for common eye colors
      final List<String> commonEyeColors = ['BROWN', 'BLACK', 'BLUE', 'GREEN', 'HAZEL', 'GRAY'];
      for (String line in allLines) {
        final upperLine = line.toUpperCase();
        for (String color in commonEyeColors) {
          if (upperLine.contains(color)) {
            eyeColor = color;
            break;
          }
        }
        if (eyeColor != null) break;
      }
    }

    // Extract DL Codes (Format: A,B or A, B or just A)
    final RegExp dlCodesRegExp = RegExp(r'\bDL\s*Codes?\b.*?\b([A-Z](?:\s*,\s*[A-Z])*)\b', caseSensitive: false);
    final dlCodesMatch = dlCodesRegExp.firstMatch(allText);
    if (dlCodesMatch != null) {
      dlCodes = dlCodesMatch.group(1)?.replaceAll(' ', '');
    }

    // Extract Conditions
    final RegExp conditionsRegExp = RegExp(r'\bConditions?\b.*?\b([A-Z]{3,15})\b', caseSensitive: false);
    final conditionsMatch = conditionsRegExp.firstMatch(allText);
    if (conditionsMatch != null) {
      conditions = conditionsMatch.group(1);
    }

    // Extract Name with improved logic
    // Look for context clues like "Last Name", "First Name" labels
    int nameLineIndex = -1;
    for (int i = 0; i < allLines.length; i++) {
      final lowerLine = allLines[i].toLowerCase();
      if (lowerLine.contains('last name') || 
          lowerLine.contains('first name') ||
          lowerLine.contains('surname') ||
          lowerLine.contains('middle name')) {
        // Name values are usually in the next 1-2 lines
        nameLineIndex = i + 1;
        break;
      }
    }
    
    // Try to extract from the line after the label
    if (nameLineIndex >= 0 && nameLineIndex < allLines.length) {
      final nameLine = allLines[nameLineIndex];
      final nextLine = (nameLineIndex + 1 < allLines.length) ? allLines[nameLineIndex + 1] : null;
      
      // Check if it's comma-separated format
      if (nameLine.contains(',')) {
        final parts = nameLine.split(',');
        if (parts.length >= 2) {
          lastName = parts[0].trim();
          final rest = parts[1].trim();
          final nameParts = rest.split(RegExp(r'\s+'));
          if (nameParts.isNotEmpty) {
            firstName = nameParts[0];
            if (nameParts.length > 1) {
              middleName = nameParts.sublist(1).join(' ');
            }
          }
        }
      }
      // Check if values are split across lines
      else if (nextLine != null && nextLine.contains(',')) {
        final parts = nextLine.split(',');
        if (parts.length >= 2) {
          lastName = parts[0].trim();
          final rest = parts[1].trim();
          final nameParts = rest.split(RegExp(r'\s+'));
          if (nameParts.isNotEmpty) {
            firstName = nameParts[0];
            if (nameParts.length > 1) {
              middleName = nameParts.sublist(1).join(' ');
            }
          }
        }
      }
    }
    
    // Fallback: search all lines for comma-separated names (common format)
    if (lastName == null) {
      for (String line in allLines) {
        // Look for pattern like SORIANO, AUBRIEL NICO PANGILINAN
        final namePattern = RegExp(r'^([A-Z][A-Z\s]*),\s*([A-Z][A-Z\s]*)\s*([A-Z][A-Z\s]*)?$');
        final match = namePattern.firstMatch(line.trim());
        if (match != null) {
          lastName = match.group(1)?.trim();
          firstName = match.group(2)?.trim();
          middleName = match.group(3)?.trim();
          if (lastName != null && firstName != null) {
            break;
          }
        }
      }
    }
    
    // Final fallback: look for any line with comma that looks like a name
    if (lastName == null) {
      for (String line in allLines) {
        if (line.contains(',')) {
          final parts = line.split(',');
          if (parts.length >= 2) {
            final potentialLast = parts[0].trim();
            final potentialFirst = parts[1].trim();
            
            // Validate: should be mostly letters, no numbers, reasonable length
            if (potentialLast.isNotEmpty && 
                potentialFirst.isNotEmpty &&
                !potentialLast.contains(RegExp(r'\d')) &&
                !potentialFirst.contains(RegExp(r'\d')) &&
                potentialLast.length >= 2 && potentialLast.length <= 40 &&
                potentialFirst.length >= 2 && potentialFirst.length <= 40) {
              lastName = potentialLast;
              final firstParts = potentialFirst.split(RegExp(r'\s+'));
              firstName = firstParts[0];
              if (firstParts.length > 1) {
                middleName = firstParts.sublist(1).join(' ');
              }
              break;
            }
          }
        }
      }
    }
    
    if (lastName != null && firstName != null) {
      fullName = '$lastName, $firstName ${middleName ?? ''}'.trim();
    }

    // Extract Address - look for address patterns
    // Usually contains words like Purok, Barangay, City, etc.
    for (int i = 0; i < allLines.length; i++) {
      final line = allLines[i].toUpperCase();
      if (line.contains('PUROK') ||
          line.contains('BARANGAY') ||
          line.contains('ST.') ||
          line.contains('STREET') ||
          line.contains('AVE') ||
          line.contains('ROAD') ||
          line.contains('CONCEPCION') ||
          line.contains('TARLAC')) {
        // This might be an address line
        // Check if it's a number starting line
        if (RegExp(r'^\d+[,\s]').hasMatch(allLines[i]) ||
            allLines[i].contains('PUROK') ||
            allLines[i].contains('BARANGAY')) {
          // Combine multiple lines if they look like address
          address = allLines[i];
          // Check next line for continuation
          if (i + 1 < allLines.length) {
            final nextLine = allLines[i + 1];
            if (!nextLine.contains('License') &&
                !nextLine.contains('Expiration') &&
                !nextLine.contains('Agency') &&
                nextLine.length > 5) {
              address = '$address, $nextLine';
            }
          }
          break;
        }
      }
    }

    return LicenseDetails(
      lastName: lastName,
      firstName: firstName,
      middleName: middleName,
      nationality: nationality,
      sex: sex,
      dateOfBirth: dateOfBirth,
      weight: weight,
      height: height,
      address: address,
      licenseNumber: licenseNumber,
      expirationDate: expirationDate,
      agencyCode: agencyCode,
      bloodType: bloodType,
      eyeColor: eyeColor,
      dlCodes: dlCodes,
      conditions: conditions,
      fullName: fullName,
    );
  }

  // Helper function
  int min(int a, int b) => a < b ? a : b;
}
