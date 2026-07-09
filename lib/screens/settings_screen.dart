import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showDebugPanel = ref.watch(showDebugPanelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: CheckboxListTile(
        value: showDebugPanel,
        onChanged: (value) => ref.read(showDebugPanelProvider.notifier).set(value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Show debug panel during call'),
        subtitle: const Text("Displays the joiner's connection info on the call screen"),
      ),
    );
  }
}
