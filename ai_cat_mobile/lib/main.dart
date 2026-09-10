import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const AiCatApp());
}

class AiCatApp extends StatelessWidget {
  const AiCatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Kedi Asistani',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF14141C),
      ),
      home: const HomeScreen(),
    );
  }
}
