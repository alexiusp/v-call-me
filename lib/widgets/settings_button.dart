import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../screens/settings_screen.dart';

/// The cog-icon action every screen with an [AppBar] carries in its top
/// right corner, opening [SettingsScreen].
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: context.l10n.settingsTooltip,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
  }
}
