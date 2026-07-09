import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)!`, used throughout the app
/// instead of hardcoded strings so every screen supports the locales listed
/// in [AppLocalizations.supportedLocales] (see `main.dart`).
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
