import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// Custom painter for authentic tricycle design
class TricyclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Passenger compartment (sidecar) - left side
    final sidecarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height * 0.2, size.width * 0.4, size.height * 0.6),
      const Radius.circular(4),
    );
    canvas.drawRRect(sidecarRect, paint);

    // Add "TODA" text on sidecar
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'TODA',
        style: TextStyle(
          color: Color(0xFF2D2D2D),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width * 0.05, size.height * 0.45));

    // Motorcycle seat - right side
    final seatRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.55,
        size.height * 0.3,
        size.width * 0.25,
        size.height * 0.2,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(seatRect, paint);

    // Handlebars
    canvas.drawLine(
      Offset(size.width * 0.85, size.height * 0.15),
      Offset(size.width * 0.95, size.height * 0.25),
      strokePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.75, size.height * 0.25),
      Offset(size.width * 0.85, size.height * 0.15),
      strokePaint,
    );

    // Connecting frame
    canvas.drawLine(
      Offset(size.width * 0.4, size.height * 0.5),
      Offset(size.width * 0.55, size.height * 0.4),
      strokePaint,
    );

    // Front wheel (sidecar)
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.85),
      size.width * 0.08,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.85),
      size.width * 0.08,
      strokePaint,
    );

    // Rear wheel (motorcycle)
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.85),
      size.width * 0.08,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.85),
      size.width * 0.08,
      strokePaint,
    );

    // Engine/motor block
    final engineRect = Rect.fromLTWH(
      size.width * 0.6,
      size.height * 0.55,
      size.width * 0.2,
      size.height * 0.25,
    );
    canvas.drawRect(engineRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TricycleLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final bool showShadow;
  final Color? backgroundColor;
  final bool plain;

  const TricycleLogo({
    super.key,
    this.size = 120,
    this.showText = true,
    this.showShadow = true,
    this.backgroundColor,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    if (plain) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'trike_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: CustomPaint(
                size: Size(size * 0.68, size * 0.48),
                painter: TricyclePainter(),
              ),
            );
          },
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Enhanced Tricycle Logo
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: backgroundColor != null
                  ? [backgroundColor!, backgroundColor!.withOpacity(0.85)]
                  : [AppTheme.primaryGreen, AppTheme.primaryGreen.withOpacity(0.85)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: showShadow
                ? [
                    BoxShadow(
                      color: (backgroundColor ?? AppTheme.primaryGreen).withOpacity(0.35),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Container(
              width: size * 0.82,
              height: size * 0.82,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              padding: EdgeInsets.all(size * 0.015),
              child: Image.asset(
                'trike_logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback to custom painted logo if image fails
                  return Center(
                    child: CustomPaint(
                      size: Size(size * 0.68, size * 0.48),
                      painter: TricyclePainter(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        if (showText) ...[
          SizedBox(height: size * 0.2),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: backgroundColor != null
                  ? [backgroundColor!, backgroundColor!.withOpacity(0.8)]
                  : [AppTheme.primaryGreen, AppTheme.primaryGreen.withOpacity(0.8)],
            ).createShader(bounds),
            child: Text(
              'Pasakay',
              style: TextStyle(
                fontSize: size * 0.27,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          SizedBox(height: size * 0.06),
          Text(
            'Tricycle Booking Made Easy',
            style: TextStyle(
              fontSize: size * 0.13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Compact version for app bars and small spaces
class CompactTricycleLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const CompactTricycleLogo({super.key, this.size = 32, this.color});

  @override
  Widget build(BuildContext context) {
    final logoColor = color ?? AppTheme.primaryGreen;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            logoColor,
            logoColor.withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: size * 0.82,
          height: size * 0.82,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          padding: EdgeInsets.all(size * 0.015),
          child: Image.asset(
            'trike_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: CustomPaint(
                  size: Size(size * 0.6, size * 0.42),
                  painter: TricyclePainter(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
