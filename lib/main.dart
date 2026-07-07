import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const VCallMeApp());
}

class VCallMeApp extends StatelessWidget {
  const VCallMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'v-call-me',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
