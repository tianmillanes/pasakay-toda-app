import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/app_theme.dart';

class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String tag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Hero(
          tag: tag,
          child: InteractiveViewer(
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4,
            child: _buildImage(),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    // Case 1: Base64 with data URI prefix
    if (imageUrl.startsWith('data:image')) {
      try {
        final bytes = base64Decode(imageUrl.split(',').last);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildErrorState(),
        );
      } catch (e) {
        return _buildErrorState();
      }
    } 
    // Case 2: Network URL
    else if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildErrorState(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              color: AppTheme.primaryGreen,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
      );
    }
    // Case 3: Raw Base64 string (no prefix)
    else {
      try {
        // Try to decode as raw base64
        final bytes = base64Decode(imageUrl);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildErrorState(),
        );
      } catch (e) {
        // If decoding fails, it's not a valid image format we handle
        return _buildErrorState();
      }
    }
  }

  Widget _buildErrorState() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image_outlined, color: Colors.white, size: 64),
        SizedBox(height: 16),
        Text(
          'Could not load image',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ],
    );
  }
}
