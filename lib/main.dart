import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/deep_link_listener.dart';
import 'services/shared_qr_intent_listener.dart';

/// App-wide messenger key so screens further down the stack (e.g.
/// `InCallScreen`) can show a message that survives popping back to
/// `HomeScreen` - a per-screen `ScaffoldMessenger` would get torn down along
/// with the screen that showed it.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  runApp(const VCallMeApp());
}

class VCallMeApp extends StatelessWidget {
  const VCallMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'v-call-me',
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const SharedQrIntentListener(
        child: DeepLinkListener(child: HomeScreen()),
      ),
    );
  }
}
