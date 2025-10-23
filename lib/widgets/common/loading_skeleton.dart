import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class LoadingSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const LoadingSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.grey[300]!,
                Colors.grey[100]!,
                Colors.grey[300]!,
              ],
              stops: [
                0.0,
                _animation.value,
                1.0,
              ],
            ),
          ),
        );
      },
    );
  }
}

class RideCardSkeleton extends StatelessWidget {
  const RideCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.getStandardBorderRadius(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and date row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LoadingSkeleton(
                  width: 80,
                  height: 24,
                  borderRadius: BorderRadius.circular(12),
                ),
                const LoadingSkeleton(width: 100, height: 16),
              ],
            ),
            const SizedBox(height: 12),
            
            // Pickup location
            Row(
              children: [
                LoadingSkeleton(
                  width: 16,
                  height: 16,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: LoadingSkeleton(height: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Dropoff location
            Row(
              children: [
                LoadingSkeleton(
                  width: 16,
                  height: 16,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: LoadingSkeleton(height: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Fare and duration
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LoadingSkeleton(width: 80, height: 20),
                LoadingSkeleton(width: 100, height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StatsCardSkeleton extends StatelessWidget {
  const StatsCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.getStandardBorderRadius(),
      ),
      child: Container(
        padding: AppTheme.getStandardPadding(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                LoadingSkeleton(
                  width: 24,
                  height: 24,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(width: 8),
                const LoadingSkeleton(width: 100, height: 18),
              ],
            ),
            const SizedBox(height: 16),
            
            // Stats row
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      LoadingSkeleton(
                        width: 40,
                        height: 40,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 8),
                      const LoadingSkeleton(width: 30, height: 16),
                      const SizedBox(height: 4),
                      const LoadingSkeleton(width: 50, height: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      LoadingSkeleton(
                        width: 40,
                        height: 40,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 8),
                      const LoadingSkeleton(width: 20, height: 16),
                      const SizedBox(height: 4),
                      const LoadingSkeleton(width: 60, height: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      LoadingSkeleton(
                        width: 40,
                        height: 40,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 8),
                      const LoadingSkeleton(width: 40, height: 16),
                      const SizedBox(height: 4),
                      const LoadingSkeleton(width: 50, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
