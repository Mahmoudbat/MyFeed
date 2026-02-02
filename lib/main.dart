
import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const OfflineSocialApp());
}

class OfflineSocialApp extends StatelessWidget {
  const OfflineSocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}
