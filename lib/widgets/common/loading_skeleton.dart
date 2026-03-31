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
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey.shade100, width: 2),
      ),
      child: Column(
        children: [
          // Header skeleton
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LoadingSkeleton(
                  width: 70,
                  height: 24,
                  borderRadius: BorderRadius.circular(12),
                ),
                const LoadingSkeleton(width: 80, height: 12),
              ],
            ),
          ),
          
          // Route skeleton
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildRouteSkeleton(),
                const Padding(
                  padding: EdgeInsets.only(left: 14, top: 4, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: 20,
                      child: VerticalDivider(width: 2, thickness: 2, color: Color(0xFFF5F5F5)),
                    ),
                  ),
                ),
                _buildRouteSkeleton(),
              ],
            ),
          ),

          // Metrics footer skeleton
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFA),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LoadingSkeleton(width: 60, height: 25),
                LoadingSkeleton(width: 60, height: 25),
                LoadingSkeleton(width: 60, height: 25),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSkeleton() => Row(
    children: [
      LoadingSkeleton(
        width: 30,
        height: 30,
        borderRadius: BorderRadius.circular(15),
      ),
      const SizedBox(width: 16),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LoadingSkeleton(width: 40, height: 8),
            SizedBox(height: 6),
            LoadingSkeleton(width: double.infinity, height: 14),
          ],
        ),
      ),
    ],
  );
}

class StatsCardSkeleton extends StatelessWidget {
  const StatsCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (index) => Expanded(
        child: Container(
          margin: EdgeInsets.only(right: index == 2 ? 0 : 12),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade50, width: 1.5),
          ),
          child: Column(
            children: [
              LoadingSkeleton(
                width: 40,
                height: 40,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(height: 12),
              const LoadingSkeleton(width: 30, height: 20),
              const SizedBox(height: 4),
              const LoadingSkeleton(width: 50, height: 10),
            ],
          ),
        ),
      )),
    );
  }
}
