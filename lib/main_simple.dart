import 'package:flutter/material.dart';

void main() {
  print('🚀 Starting simple app...');
  runApp(const SimpleTestApp());
}

class SimpleTestApp extends StatelessWidget {
  const SimpleTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    print('📱 Building SimpleTestApp...');
    return MaterialApp(
      title: 'Simple Test App',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('App Test'),
          backgroundColor: Colors.blue,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 64, color: Colors.green),
              SizedBox(height: 16),
              Text(
                'App is working!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('The basic Flutter app structure is functional.'),
            ],
          ),
        ),
      ),
    );
  }
}
