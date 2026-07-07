import 'package:flutter/material.dart';

import 'qr_display_screen.dart';
import 'qr_import_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('v-call-me')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const QrDisplayScreen(role: CallRole.host),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('Start a call'),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QrImportScreen()),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text('Join a call'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum CallRole { host, joiner }
