import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../widgets/settings_button.dart';
import 'qr_display_screen.dart';
import 'qr_import_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.appTitle),
        actions: const [SettingsButton()],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => QrDisplayScreen(role: CallRole.host),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text(context.l10n.startCallButton),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QrImportScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Text(context.l10n.joinCallButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum CallRole { host, joiner }
