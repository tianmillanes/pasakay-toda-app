import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/app_theme.dart';

class LocationHelpers {
  static Future<Uint8List> getWazeMarkerImage({double size = 120}) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final double radius = size / 2;

    // Draw shadow
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(radius, radius + 2), radius - 4, shadowPaint);

    // Draw Waze indigo circle
    final Paint circlePaint = Paint()
      ..color = AppTheme.primaryGreen // Use Theme Primary (Indigo)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(radius, radius), radius - 4, circlePaint);

    // Draw white border
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(Offset(radius, radius), radius - 4, borderPaint);

    // Draw white arrow (triangle)
    final Paint arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final Path path = Path();
    path.moveTo(radius, radius - (radius * 0.6)); // Top
    path.lineTo(radius + (radius * 0.4), radius + (radius * 0.4)); // Bottom right
    path.lineTo(radius, radius + (radius * 0.2)); // Bottom center indent
    path.lineTo(radius - (radius * 0.4), radius + (radius * 0.4)); // Bottom left
    path.close();
    
    canvas.drawPath(path, arrowPaint);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return byteData!.buffer.asUint8List();
  }

  static Future<Uint8List> get3DUserMarkerImage({double size = 120}) async {
    try {
      // Load the motorcycle/tricycle icon asset
      final ByteData data = await rootBundle.load('assets/icon/tricycle_icon.png');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: size.toInt(),
        targetHeight: size.toInt(),
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData = await fi.image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } catch (e) {
      print('Error loading 3D marker image from asset: $e. Falling back to drawn circle.');
      
      // Fallback: Draw orange circle if asset fails to load
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final double radius = size / 2;

      // Draw shadow
      final Paint shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(radius, radius + 4), radius - 4, shadowPaint);

      // Draw orange circle for default effect
      final Paint circlePaint = Paint()
        ..color = const Color(0xFFFF9800) // Orange
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(radius, radius), radius - 4, circlePaint);

      // Draw white border
      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(radius, radius), radius - 4, borderPaint);

      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(size.toInt(), size.toInt());
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      return byteData!.buffer.asUint8List();
    }
  }

  static Future<Uint8List> getProfilePuckMarkerImage({
    String? photoUrl,
    String? initial,
    double size = 150,
    Color pinColor = const Color(0xFFE53935),
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    
    // Dimensions (Increased scale)
    final double w = size;
    final double h = size * 1.3; // Taller pin
    final double cx = w / 2;
    final double cy = w / 2;
    final double radius = w / 2;

    // 1. Enhanced Drop Shadow
    final Path shadowPath = Path()
      ..addOval(Rect.fromLTWH(cx - radius * 0.5, h - 8, radius, 6));
    canvas.drawPath(
      shadowPath, 
      Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
    );

    // 2. Pin Body with subtle Gradient
    final Paint pinPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(cx, 0),
        Offset(cx, h),
        [
          pinColor.withOpacity(0.9),
          pinColor,
          Color.lerp(pinColor, Colors.black, 0.2)!,
        ],
        [0.0, 0.6, 1.0],
      );

    // Draw Pin Tail (Triangle at bottom)
    final Path tailPath = Path();
    tailPath.moveTo(cx, h); // Tip at bottom
    tailPath.lineTo(cx - radius * 0.55, cy + radius * 0.4); // Left connect
    tailPath.lineTo(cx + radius * 0.55, cy + radius * 0.4); // Right connect
    tailPath.close();
    canvas.drawPath(tailPath, pinPaint);

    // Draw Main Circle Body
    canvas.drawCircle(Offset(cx, cy), radius, pinPaint);

    // 3. Thicker White Border Ring with Shadow
    final double borderWidth = size * 0.08;
    
    // Inner Shadow for Border
    canvas.drawCircle(Offset(cx, cy), radius - borderWidth / 2 + 1, Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth + 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
    );

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawCircle(Offset(cx, cy), radius - borderWidth / 2, borderPaint);

    // 4. Inner Content (Profile Image or Fallback)
    final double innerRadius = radius - borderWidth;
    
    canvas.save();
    final Path clipPath = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: innerRadius));
    canvas.clipPath(clipPath);
    
    // Background for transparent images
    canvas.drawColor(Colors.grey.shade100, BlendMode.srcATop);

    ui.Image? avatarImage;
    try {
      if (photoUrl != null && photoUrl.isNotEmpty) {
        if (photoUrl.startsWith('data:image')) {
          final dataPart = photoUrl.split(',').last;
          final bytes = Uint8List.fromList(base64Decode(dataPart));
          final ui.Codec codec = await ui.instantiateImageCodec(
            bytes, 
            targetWidth: (innerRadius * 2).toInt(), 
            targetHeight: (innerRadius * 2).toInt()
          );
          final ui.FrameInfo fi = await codec.getNextFrame();
          avatarImage = fi.image;
        } else if (photoUrl.startsWith('http')) {
          final bundle = NetworkAssetBundle(Uri.parse(photoUrl));
          final ByteData bd = await bundle.load(photoUrl);
          final ui.Codec codec = await ui.instantiateImageCodec(
            bd.buffer.asUint8List(), 
            targetWidth: (innerRadius * 2).toInt(), 
            targetHeight: (innerRadius * 2).toInt()
          );
          final ui.FrameInfo fi = await codec.getNextFrame();
          avatarImage = fi.image;
        }
      }
    } catch (_) {
      avatarImage = null;
    }

    if (avatarImage != null) {
      final src = Rect.fromLTWH(0, 0, avatarImage.width.toDouble(), avatarImage.height.toDouble());
      final dst = Rect.fromCircle(center: Offset(cx, cy), radius: innerRadius);
      canvas.drawImageRect(avatarImage, src, dst, Paint()..isAntiAlias = true);
    } else {
      // Fallback: Default Profile Icon
      final IconData icon = Icons.person;
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: innerRadius * 1.5,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      textPainter.paint(
        canvas, 
        Offset(cx - textPainter.width / 2, cy - textPainter.height / 2)
      );
    }
    
    canvas.restore();

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(w.toInt(), h.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  static Future<void> showLocationDisabledDialog(BuildContext context) async {
    // Prevent multiple dialogs
    if (ModalRoute.of(context)?.isCurrent == false) return;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _LocationDisabledDialog();
      },
    );
  }
}

class _LocationDisabledDialog extends StatefulWidget {
  @override
  State<_LocationDisabledDialog> createState() => _LocationDisabledDialogState();
}

class _LocationDisabledDialogState extends State<_LocationDisabledDialog> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationService();
    }
  }

  Future<void> _checkLocationService() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (serviceEnabled && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: AppTheme.errorRed,
                size: 32,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Location Services Disabled',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Location services are disabled. Please enable GPS/location services.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Enable Location',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
