import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/l10n.dart';
import 'screens/home_screen.dart';
import 'services/deep_link_listener.dart';
import 'services/shared_qr_intent_listener.dart';
import 'state/settings.dart';

/// App-wide messenger key so screens further down the stack (e.g.
/// `InCallScreen`) can show a message that survives popping back to
/// `HomeScreen` - a per-screen `ScaffoldMessenger` would get torn down along
/// with the screen that showed it.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(VCallMeApp(prefs: prefs));
}

class VCallMeApp extends StatelessWidget {
  const VCallMeApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    // `_App` reads providers, so it must sit below this `ProviderScope`.
    // `sharedPreferencesProvider` is overridden with the instance loaded in
    // `main()` so settings notifiers can read/write persisted values.
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const _App(),
    );
  }
}

class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'VCall Me',
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      locale: ref.watch(appLocaleProvider).locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // English first so it's the fallback when the device locale isn't
      // one of the two supported below.
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SharedQrIntentListener(
        child: DeepLinkListener(child: HomeScreen()),
      ),
    );
  }
}
