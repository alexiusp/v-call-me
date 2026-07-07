import 'package:flutter/material.dart';

/// Shared regardless of role, since the session is symmetric once connected.
class InCallScreen extends StatelessWidget {
  const InCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call')),
      body: const Center(child: Text('Call UI not implemented yet')),
    );
  }
}
