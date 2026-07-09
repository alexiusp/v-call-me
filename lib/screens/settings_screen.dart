import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../state/settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // Language names are shown in their own language regardless of the
  // current app locale (the usual convention for language pickers), so
  // these aren't routed through AppLocalizations.
  static const _languageNames = {
    AppLocale.en: 'English',
    AppLocale.ru: 'Русский',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showDebugPanel = ref.watch(showDebugPanelProvider);
    final appLocale = ref.watch(appLocaleProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              context.l10n.languageSettingTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          RadioGroup<AppLocale>(
            groupValue: appLocale,
            onChanged: (value) => ref.read(appLocaleProvider.notifier).set(value ?? AppLocale.system),
            child: Column(
              children: [
                for (final locale in AppLocale.values)
                  RadioListTile<AppLocale>(
                    value: locale,
                    title: Text(
                      locale == AppLocale.system
                          ? context.l10n.languageSystemDefault
                          : _languageNames[locale]!,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          CheckboxListTile(
            value: showDebugPanel,
            onChanged: (value) => ref.read(showDebugPanelProvider.notifier).set(value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(context.l10n.showDebugPanelTitle),
            subtitle: Text(context.l10n.showDebugPanelSubtitle),
          ),
        ],
      ),
    );
  }
}
