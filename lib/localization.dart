import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

extension RecordingQualityLabel on RecordingQuality {
  String label(AppLocalizations strings) {
    switch (this) {
      case RecordingQuality.low:
        return strings.low;
      case RecordingQuality.medium:
        return strings.medium;
      case RecordingQuality.high:
        return strings.high;
    }
  }
}

extension RecordingModeLabel on RecordingMode {
  String label(AppLocalizations strings) {
    switch (this) {
      case RecordingMode.withBackground:
        return strings.recordWithBackground;
      case RecordingMode.streamOnly:
        return strings.recordStreamOnly;
    }
  }
}

class AppLocalizations {
  AppLocalizations(this.locale, this._localizedValues, this._countryNames);

  final Locale locale;
  final Map<String, String> _localizedValues;
  final Map<String, String>? _countryNames;

  static const supportedLocales = [
    Locale('en'),
    Locale('ar'),
    Locale('es'),
    Locale('ru'),
    Locale('zh'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static Future<Map<String, String>> _loadStrings(String languageCode) async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/l10n/$languageCode.json');
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      return jsonMap.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      if (languageCode != 'en') {
        try {
          final jsonString =
              await rootBundle.loadString('assets/l10n/en.json');
          final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
          return jsonMap.map((key, value) => MapEntry(key, value.toString()));
        } catch (_) {
          return <String, String>{};
        }
      }
      return <String, String>{};
    }
  }

  static Future<Map<String, String>?> _loadCountryNames(
      String languageCode) async {
    try {
      final jsonString = await rootBundle
          .loadString('assets/l10n/countries_$languageCode.json');
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      return jsonMap.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      return null;
    }
  }

  String _t(String key) => _localizedValues[key] ?? '';

  String get appTitle => _t('appTitle');
  String get country => _t('country');
  String get noStations => _t('noStations');
  String get play => _t('play');
  String get pause => _t('pause');
  String get startRecording => _t('startRecording');
  String get stopRecording => _t('stopRecording');
  String get nowPlaying => _t('nowPlaying');
  String get notPlaying => _t('notPlaying');
  String get lcdIdle => _t('lcdIdle');
  String get settings => _t('settings');
  String get language => _t('language');
  String get dataSaver => _t('dataSaver');
  String get dataSaverDescription => _t('dataSaverDescription');
  String get dataSaverSuggestion => _t('dataSaverSuggestion');
  String get recordingQuality => _t('recordingQuality');
  String get recordingMode => _t('recordingMode');
  String get recordWithBackground => _t('recordWithBackground');
  String get recordStreamOnly => _t('recordStreamOnly');
  String get recordBgShort => _t('recordBgShort');
  String get themeMode => _t('themeMode');
  String get themeSystem => _t('themeSystem');
  String get themeDark => _t('themeDark');
  String get themeLight => _t('themeLight');
  String get stationMetadata => _t('stationMetadata');
  String get stationName => _t('stationName');
  String get stationCountry => _t('stationCountry');
  String get stationFrequency => _t('stationFrequency');
  String get frequencyVerificationNote => _t('frequencyVerificationNote');
  String get stationLanguage => _t('stationLanguage');
  String get stationTags => _t('stationTags');
  String get stationBitrate => _t('stationBitrate');
  String get duration => _t('duration');
  String get stationLink => _t('stationLink');
  String get stationDate => _t('stationDate');
  String get recordings => _t('recordings');
  String get noRecordings => _t('noRecordings');
  String recordingsCount(int count) =>
      _t('recordingsCount').replaceAll('{count}', count.toString());
  String stationsCount(int count, [bool hasMore = false]) =>
      _t('stationsCount')
          .replaceAll('{count}', count.toString() + (hasMore ? '+' : ''));
  String get subscription => _t('subscription');
  String get subscribed => _t('subscribed');
  String get notSubscribed => _t('notSubscribed');
  String get subscriptionUpgradeHint => _t('subscriptionUpgradeHint');
  String get privacyAdChoices => _t('privacyAdChoices');
  String get privacyPolicy => _t('privacyPolicy');
  String get subscribe => _t('subscribe');
  String get manage => _t('manage');
  String get cancelSubscription => _t('cancelSubscription');
  String get adPlaceholder => _t('adPlaceholder');
  String get loadMore => _t('loadMore');
  String get searchStations => _t('searchStations');
  String get searchRecordings => _t('searchRecordings');
  String get editNameTitle => _t('editNameTitle');
  String get renameFileTitle => _t('renameFileTitle');
  String get nameHint => _t('nameHint');
  String get save => _t('save');
  String get favorite => _t('favorite');
  String get deleteRecordingTitle => _t('deleteRecordingTitle');
  String get deleteRecordingBody => _t('deleteRecordingBody');
  String get cancel => _t('cancel');
  String get delete => _t('delete');
  String get listPageSize => _t('listPageSize');
  String get maxRecordingDuration => _t('maxRecordingDuration');
  String get minutes => _t('minutes');
  String get low => _t('low');
  String get medium => _t('medium');
  String get high => _t('high');
  String get castTo => _t('castTo');
  String get castComingSoon => _t('castComingSoon');
  String get castNoSource => _t('castNoSource');
  String get castNoDevices => _t('castNoDevices');
  String get castFailed => _t('castFailed');
  String get castOpenInChrome => _t('castOpenInChrome');
  String get autoOffTimer => _t('autoOffTimer');
  String get autoOffDisabled => _t('autoOffDisabled');
  String autoOffWillCloseIn(int minutes) =>
      _t('autoOffWillCloseIn').replaceAll('{minutes}', minutes.toString());
  String autoOffCountdown(String time) =>
      _t('autoOffCountdown').replaceAll('{time}', time);
  String get aboutTitle => _t('aboutTitle');
  String get aboutDeveloper => _t('aboutDeveloper');
  String aboutDeveloperDescription(String name, String email) =>
      _t('aboutDeveloperDescription')
          .replaceAll('{name}', name)
          .replaceAll('{email}', email);
  String get aboutDataSource => _t('aboutDataSource');
  String aboutDataSourceDescription(String source, String url) =>
      _t('aboutDataSourceDescription')
          .replaceAll('{source}', source)
          .replaceAll('{url}', url);
  String get aboutDisclaimer => _t('aboutDisclaimer');
  String get aboutDisclaimerText => _t('aboutDisclaimerText');
  String get cannotRecordNoStreamUrl => _t('cannotRecordNoStreamUrl');
  String get cannotRecordInvalidUrl => _t('cannotRecordInvalidUrl');
  String get cannotRecordConnectionFailed => _t('cannotRecordConnectionFailed');
  String get cannotRecordStreamError => _t('cannotRecordStreamError');
  String get cannotRecordConnectionTimeout => _t('cannotRecordConnectionTimeout');
  String get cannotRecordNotSupported => _t('cannotRecordNotSupported');
  String get cannotRecordNoDataProxy => _t('cannotRecordNoDataProxy');
  String get recordingTooShort => _t('recordingTooShort');
  String get recordingMaxDuration => _t('recordingMaxDuration');
  String get microphonePermissionRequired => _t('microphonePermissionRequired');
  String get sendFeedback => _t('sendFeedback');
  String get feedbackDescription => _t('feedbackDescription');
  String get feedbackHint => _t('feedbackHint');
  String get feedbackCannotSend => _t('feedbackCannotSend');
  String get send => _t('send');
  String get updatingStationsInfo => _t('updatingStationsInfo');
  String get exit => _t('exit');
  String get tapAgainToLeave => _t('tapAgainToLeave');

  String? recordingErrorMessage(String? key) {
    if (key == null) return null;
    return switch (key) {
      'cannotRecordNoStreamUrl' => cannotRecordNoStreamUrl,
      'cannotRecordInvalidUrl' => cannotRecordInvalidUrl,
      'cannotRecordConnectionFailed' => cannotRecordConnectionFailed,
      'cannotRecordStreamError' => cannotRecordStreamError,
      'cannotRecordConnectionTimeout' => cannotRecordConnectionTimeout,
      'cannotRecordNotSupported' => cannotRecordNotSupported,
      'cannotRecordNoDataProxy' => cannotRecordNoDataProxy,
      'recordingTooShort' => recordingTooShort,
      'recordingMaxDuration' => recordingMaxDuration,
      'microphonePermissionRequired' => microphonePermissionRequired,
      _ => key,
    };
  }

  String countryName(Country country) {
    return _countryNames?[country.code] ?? country.name;
  }

  String countryDisplayName(String apiCountryName) {
    final match =
        Country.defaults.where((c) => c.name == apiCountryName).toList();
    if (match.isNotEmpty) return countryName(match.first);
    return apiCountryName;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.supportedLocales
          .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final strings =
        await AppLocalizations._loadStrings(locale.languageCode);
    final countryNames =
        await AppLocalizations._loadCountryNames(locale.languageCode);
    return AppLocalizations(locale, strings, countryNames);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
