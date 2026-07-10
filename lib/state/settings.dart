import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the [SharedPreferences] instance loaded in `main()`. Overridden there
/// via `ProviderScope(overrides: …)` so settings notifiers can read and persist
/// values synchronously, without an async gate on the first frame.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  ),
);

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

/// The app's display language, picked manually in [SettingsScreen] rather
/// than always following the device locale - [system] restores that
/// default behavior.
enum AppLocale { system, en, ru }

extension AppLocaleLocale on AppLocale {
  /// The [Locale] to hand `MaterialApp.locale`, or null for [system] to let
  /// Flutter resolve one from the device's locale list itself.
  Locale? get locale => switch (this) {
        AppLocale.system => null,
        AppLocale.en => const Locale('en'),
        AppLocale.ru => const Locale('ru'),
      };
}

class AppLocaleNotifier extends Notifier<AppLocale> {
  static const _prefsKey = 'app_locale';

  @override
  AppLocale build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    return AppLocale.values.firstWhere(
      (value) => value.name == saved,
      orElse: () => AppLocale.system,
    );
  }

  void set(AppLocale value) {
    state = value;
    ref.read(sharedPreferencesProvider).setString(_prefsKey, value.name);
  }
}

final appLocaleProvider = NotifierProvider<AppLocaleNotifier, AppLocale>(
  AppLocaleNotifier.new,
);
