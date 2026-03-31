import 'package:flutter/material.dart';

class AnimatedMapButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isSmall;
  final String heroTag;

  const AnimatedMapButton({
    super.key,
    required this.onPressed,
    required this.child,
    required this.backgroundColor,
    required this.foregroundColor,
    this.isSmall = false,
    required this.heroTag,
  });

  @override
  State<AnimatedMapButton> createState() => _AnimatedMapButtonState();
}

class _AnimatedMapButtonState extends State<AnimatedMapButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _controller.forward(),
      onTap: () {
        _controller.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.isSmall
            ? FloatingActionButton.small(
                onPressed: null, // Handled by GestureDetector
                backgroundColor: widget.backgroundColor,
                foregroundColor: widget.foregroundColor,
                heroTag: widget.heroTag,
                elevation: 4,
                child: widget.child,
              )
            : FloatingActionButton(
                onPressed: null, // Handled by GestureDetector
                backgroundColor: widget.backgroundColor,
                foregroundColor: widget.foregroundColor,
                heroTag: widget.heroTag,
                elevation: 4,
                child: widget.child,
              ),
      ),
    );
  }
}
