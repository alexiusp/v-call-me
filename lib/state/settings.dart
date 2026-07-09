import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether [InCallScreen] shows the connection-info debug panel.
///
/// A single global setting rather than something threaded through the
/// host/joiner navigation flow, so it lives in [SettingsScreen] and applies
/// to both roles.
class ShowDebugPanelNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final showDebugPanelProvider = NotifierProvider<ShowDebugPanelNotifier, bool>(
  ShowDebugPanelNotifier.new,
);
