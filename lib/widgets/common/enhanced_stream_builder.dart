import 'package:flutter/material.dart';
import '../../services/error_handling_service.dart';
import 'error_display_widget.dart';

/// Enhanced StreamBuilder with comprehensive error handling
class EnhancedStreamBuilder<T> extends StatefulWidget {
  final Stream<T> stream;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context, dynamic error, VoidCallback onRetry)? errorBuilder;
  final Widget Function(BuildContext context)? emptyBuilder;
  final String? errorContext;
  final bool showErrorDetails;
  final Duration retryDelay;
  final int maxRetries;

  const EnhancedStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.errorContext,
    this.showErrorDetails = false,
    this.retryDelay = const Duration(seconds: 2),
    this.maxRetries = 3,
  });

  @override
  State<EnhancedStreamBuilder<T>> createState() => _EnhancedStreamBuilderState<T>();
}

class _EnhancedStreamBuilderState<T> extends State<EnhancedStreamBuilder<T>> {
  late Stream<T> _stream;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _stream = widget.stream;
  }

  void _retry() {
    if (_retryCount < widget.maxRetries) {
      _retryCount++;
      setState(() {
        _stream = widget.stream;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Max retries reached. Please try again later.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _stream,
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.loadingBuilder?.call(context) ??
              const Center(
                child: CircularProgressIndicator(),
              );
        }

        // Error state
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, snapshot.error, _retry) ??
              ErrorDisplayWidget(
                error: snapshot.error,
                context: widget.errorContext,
                onRetry: _retry,
                showDetails: widget.showErrorDetails,
              );
        }

        // Empty state
        if (!snapshot.hasData || (snapshot.data is List && (snapshot.data as List).isEmpty)) {
          return widget.emptyBuilder?.call(context) ??
              Center(
                child: Text(
                  'No data available',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              );
        }

        // Success state
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}

/// Enhanced FutureBuilder with comprehensive error handling
class EnhancedFutureBuilder<T> extends StatefulWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context, dynamic error, VoidCallback onRetry)? errorBuilder;
  final String? errorContext;
  final bool showErrorDetails;
  final int maxRetries;

  const EnhancedFutureBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.errorContext,
    this.showErrorDetails = false,
    this.maxRetries = 3,
  });

  @override
  State<EnhancedFutureBuilder<T>> createState() => _EnhancedFutureBuilderState<T>();
}

class _EnhancedFutureBuilderState<T> extends State<EnhancedFutureBuilder<T>> {
  late Future<T> _future;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _future = widget.future;
  }

  void _retry() {
    if (_retryCount < widget.maxRetries) {
      _retryCount++;
      setState(() {
        _future = widget.future;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Max retries reached. Please try again later.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.loadingBuilder?.call(context) ??
              const Center(
                child: CircularProgressIndicator(),
              );
        }

        // Error state
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, snapshot.error, _retry) ??
              ErrorDisplayWidget(
                error: snapshot.error,
                context: widget.errorContext,
                onRetry: _retry,
                showDetails: widget.showErrorDetails,
              );
        }

        // Success state
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}
