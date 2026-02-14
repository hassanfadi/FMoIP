import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ad_consnt.dart';
import '../app_info.dart';
import '../localization.dart';
import '../models.dart';
import '../state/settings_state.dart';
import '../state/subscription_state.dart';
import '../utils.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final settings = context.watch<SettingsState>();
    final subscription = context.watch<SubscriptionState>();
    final settingsTextStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        children: [
          _SettingsLanguageTile(settings: settings, textStyle: settingsTextStyle),
          _SettingsThemeTile(settings: settings, textStyle: settingsTextStyle),
          _SettingsRecordingQualityTile(
            settings: settings,
            textStyle: settingsTextStyle,
          ),
          _SettingsMaxRecordingTile(
            settings: settings,
            textStyle: settingsTextStyle,
          ),
          _SettingsListPageSizeTile(
            settings: settings,
            textStyle: settingsTextStyle,
          ),
          _SettingsAutoOffTile(
            settings: settings,
            textStyle: settingsTextStyle,
            strings: strings,
          ),
          ListTile(
            title: Text(strings.dataSaver, style: settingsTextStyle),
            subtitle: Text(
              strings.dataSaverDescription,
              style: settingsTextStyle?.copyWith(
                fontWeight: FontWeight.normal,
                fontSize: 12,
                color: (settingsTextStyle?.color ?? Colors.black)
                    .withValues(alpha: 0.7),
              ),
            ),
            trailing: SizedBox(
              width: 80,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Switch(
                    value: settings.dataSaver,
                    onChanged: settings.setDataSaver,
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          if (subscription.errorMessage != null)
            _SubscriptionErrorTile(
              subscription: subscription,
              textStyle: settingsTextStyle,
            ),
          _SubscriptionDescriptionTile(
            subscription: subscription,
            textStyle: settingsTextStyle,
            strings: strings,
          ),
          _SubscriptionActionsTile(
            subscription: subscription,
            textStyle: settingsTextStyle,
            strings: strings,
          ),
          ListTile(
            title: Text(strings.privacyPolicy, style: settingsTextStyle),
            trailing: const Icon(Icons.open_in_new, size: 20),
            onTap: () => launchUrl(
              Uri.parse(AppInfo.privacyPolicyUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          if (!subscription.isPro)
            ListTile(
              title: Text(strings.privacyAdChoices, style: settingsTextStyle),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: () async {
                await AdConsentHelper.showPrivacyOptionsForm();
              },
            ),
        ],
      ),
    );
  }
}

class _SettingsLanguageTile extends StatelessWidget {
  const _SettingsLanguageTile({
    required this.settings,
    required this.textStyle,
  });

  final SettingsState settings;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(AppLocalizations.of(context).language, style: textStyle),
      trailing: SizedBox(
        width: 80,
        child: DropdownButton<Locale>(
          value: settings.locale,
          isExpanded: true,
          isDense: true,
            itemHeight: kMinInteractiveDimension,
            style: textStyle,
            onChanged: (value) {
              if (value != null) settings.setLocale(value);
            },
            items: AppLocalizations.supportedLocales
                .map((locale) => DropdownMenuItem(
                  value: locale,
                  child: Text(
                    locale.languageCode.toUpperCase(),
                    style: textStyle,
                  ),
                ))
                .toList(),
        ),
      ),
    );
  }
}

class _SettingsThemeTile extends StatelessWidget {
  const _SettingsThemeTile({
    required this.settings,
    required this.textStyle,
  });

  final SettingsState settings;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListTile(
      title: Text(strings.themeMode, style: textStyle),
      trailing: SizedBox(
        width: 80,
        child: DropdownButton<ThemeMode>(
          value: settings.themeMode,
          isExpanded: true,
          style: textStyle,
        onChanged: (value) {
          if (value != null) settings.setThemeMode(value);
        },
        items: ThemeMode.values
            .map((mode) => DropdownMenuItem(
                  value: mode,
                  child: Text(themeModeLabel(mode, strings), style: textStyle),
                ))
            .toList(),
        ),
      ),
    );
  }
}

class _SettingsRecordingQualityTile extends StatelessWidget {
  const _SettingsRecordingQualityTile({
    required this.settings,
    required this.textStyle,
  });

  final SettingsState settings;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListTile(
      title: Text(strings.recordingQuality, style: textStyle),
      trailing: SizedBox(
        width: 80,
        child: DropdownButton<RecordingQuality>(
          value: settings.recordingQuality,
          isExpanded: true,
          style: textStyle,
        onChanged: (value) {
          if (value != null) settings.setRecordingQuality(value);
        },
        items: RecordingQuality.values
            .map((quality) => DropdownMenuItem(
                  value: quality,
                  child: Text(quality.label(strings), style: textStyle),
                ))
            .toList(),
        ),
      ),
    );
  }
}

class _SettingsMaxRecordingTile extends StatelessWidget {
  const _SettingsMaxRecordingTile({
    required this.settings,
    required this.textStyle,
  });

  final SettingsState settings;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListTile(
      title: Text(strings.maxRecordingDuration, style: textStyle),
      trailing: SizedBox(
        width: 80,
        child: DropdownButton<int>(
          value: settings.maxRecordingMinutes,
          isExpanded: true,
          style: textStyle,
        onChanged: (value) {
          if (value != null) settings.setMaxRecordingMinutes(value);
        },
        items: const [15, 30, 60, 120, 180, 240]
            .map((value) => DropdownMenuItem(
                  value: value,
                  child: Text('$value ${strings.minutes}', style: textStyle),
                ))
            .toList(),
        ),
      ),
    );
  }
}

class _SettingsListPageSizeTile extends StatelessWidget {
  const _SettingsListPageSizeTile({
    required this.settings,
    required this.textStyle,
  });

  final SettingsState settings;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListTile(
      title: Text(strings.listPageSize, style: textStyle),
      trailing: SizedBox(
        width: 80,
        child: DropdownButton<int>(
          value: settings.listPageSize,
          isExpanded: true,
          style: textStyle,
        onChanged: (value) {
          if (value != null) settings.setListPageSize(value);
        },
        items: SettingsState.listPageSizeOptions
            .map((value) => DropdownMenuItem(
                  value: value,
                  child: Text(value.toString(), style: textStyle),
                ))
            .toList(),
        ),
      ),
    );
  }
}

class _SettingsAutoOffTile extends StatelessWidget {
  const _SettingsAutoOffTile({
    required this.settings,
    required this.textStyle,
    required this.strings,
  });

  final SettingsState settings;
  final TextStyle? textStyle;
  final AppLocalizations strings;

  String _label(int minutes) {
    if (minutes == 0) return strings.autoOffDisabled;
    return '$minutes ${strings.minutes}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(strings.autoOffTimer, style: textStyle),
      trailing: SizedBox(
        width: 80,
        child: DropdownButton<int>(
          value: settings.autoOffMinutes,
          isExpanded: true,
          style: textStyle,
        onChanged: (value) {
          if (value != null) {
            settings.setAutoOffMinutes(value);
            if (value > 0 && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.autoOffWillCloseIn(value))),
              );
            }
          }
        },
        items: SettingsState.autoOffOptions
            .map((value) => DropdownMenuItem(
                  value: value,
                  child: Text(_label(value), style: textStyle),
                ))
            .toList(),
        ),
      ),
    );
  }
}

class _SubscriptionErrorTile extends StatelessWidget {
  const _SubscriptionErrorTile({
    required this.subscription,
    required this.textStyle,
  });

  final SubscriptionState subscription;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              subscription.errorMessage!,
              style: textStyle?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          TextButton(
            onPressed: subscription.clearError,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}

/// Shows the current plan (Free with ads / Ad-free) and upgrade hint.
/// No action buttons — purely informational.
class _SubscriptionDescriptionTile extends StatelessWidget {
  const _SubscriptionDescriptionTile({
    required this.subscription,
    required this.textStyle,
    required this.strings,
  });

  final SubscriptionState subscription;
  final TextStyle? textStyle;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(strings.subscription, style: textStyle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            subscription.isPro ? strings.subscribed : strings.notSubscribed,
            style: textStyle,
          ),
          if (!subscription.isPro) ...[
            const SizedBox(height: 4),
            Text(
              strings.subscriptionUpgradeHint,
              style: textStyle?.copyWith(
                fontWeight: FontWeight.normal,
                color: (textStyle?.color ?? Colors.black)
                    .withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows the Subscribe / Manage / Cancel buttons only.
/// Keeps actions clearly separated from the plan description.
class _SubscriptionActionsTile extends StatelessWidget {
  const _SubscriptionActionsTile({
    required this.subscription,
    required this.textStyle,
    required this.strings,
  });

  final SubscriptionState subscription;
  final TextStyle? textStyle;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (subscription.isPro)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: subscription.isLoading
                    ? null
                    : () async {
                        await subscription.openSubscriptionManagement();
                      },
                child: Text(strings.cancelSubscription),
              ),
            ),
          if (subscription.isLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            ElevatedButton(
              onPressed: () async {
                if (subscription.isPro) {
                  await subscription.openSubscriptionManagement();
                } else {
                  await subscription.purchaseSubscription();
                }
              },
              style: ElevatedButton.styleFrom(textStyle: textStyle),
              child: Text(
                subscription.isPro ? strings.manage : strings.subscribe,
              ),
            ),
        ],
      ),
    );
  }
}
