import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization.dart';
import '../models.dart';

class SettingsState extends ChangeNotifier {
  static const String _keyLocale = 'settings_locale';
  static const String _keyThemeMode = 'settings_theme_mode';
  static const String _keyListPageSize = 'settings_list_page_size';

  /// Allowed values for list page size (rows per list).
  static const List<int> listPageSizeOptions = [10, 20, 30, 50, 100, 200, 1000];
  static int get maxListPageSize => listPageSizeOptions.last;
  static const String _keyDataSaver = 'settings_data_saver';
  static const String _keyRecordingQuality = 'settings_recording_quality';
  static const String _keyRecordingMode = 'settings_recording_mode';
  static const String _keyMaxRecordingMinutes = 'settings_max_recording_minutes';

  /// Auto off timer options: 0 = disabled, others = minutes until auto pause.
  static const List<int> autoOffOptions = [0, 15, 30, 60, 120, 180];

  Locale _locale = const Locale('en');
  bool dataSaver = false;
  RecordingQuality recordingQuality = RecordingQuality.high;
  RecordingMode recordingMode = RecordingMode.streamOnly;
  ThemeMode themeMode = ThemeMode.system;
  int listPageSize = 200;
  int maxRecordingMinutes = 60;
  int autoOffMinutes = 0;

  Locale get locale => _locale;

  SettingsState() {
    Future.microtask(() => _loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localeCode = prefs.getString(_keyLocale);
      if (localeCode != null && localeCode.isNotEmpty) {
        _locale = Locale(localeCode);
      } else {
        final systemLocale = PlatformDispatcher.instance.locale;
        final match = AppLocalizations.supportedLocales
            .where((l) => l.languageCode == systemLocale.languageCode)
            .toList();
        if (match.isNotEmpty) {
          _locale = match.first;
        }
      }
      final themeIndex = prefs.getInt(_keyThemeMode);
      if (themeIndex != null &&
          themeIndex >= 0 &&
          themeIndex < ThemeMode.values.length) {
        themeMode = ThemeMode.values[themeIndex];
      }
      final pageSize = prefs.getInt(_keyListPageSize);
      if (pageSize != null && listPageSizeOptions.contains(pageSize)) {
        listPageSize = pageSize;
      }
      final dataSaverValue = prefs.getBool(_keyDataSaver);
      if (dataSaverValue != null) dataSaver = dataSaverValue;
      final qualityIndex = prefs.getInt(_keyRecordingQuality);
      if (qualityIndex != null &&
          qualityIndex >= 0 &&
          qualityIndex < RecordingQuality.values.length) {
        recordingQuality = RecordingQuality.values[qualityIndex];
      }
      final modeIndex = prefs.getInt(_keyRecordingMode);
      if (modeIndex != null &&
          modeIndex >= 0 &&
          modeIndex < RecordingMode.values.length) {
        recordingMode = RecordingMode.values[modeIndex];
      }
      final maxMinutes = prefs.getInt(_keyMaxRecordingMinutes);
      if (maxMinutes != null && maxMinutes >= 1 && maxMinutes <= 1440) {
        maxRecordingMinutes = maxMinutes;
      }
      notifyListeners();
    } catch (_) {}
  }

  void setLocale(Locale value) {
    _locale = value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_keyLocale, value.languageCode);
    });
  }

  void setDataSaver(bool value) {
    dataSaver = value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_keyDataSaver, value);
    });
  }

  void setRecordingQuality(RecordingQuality value) {
    recordingQuality = value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_keyRecordingQuality, value.index);
    });
  }

  void setRecordingMode(RecordingMode value) {
    recordingMode = value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_keyRecordingMode, value.index);
    });
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_keyThemeMode, value.index);
    });
  }

  void setListPageSize(int value) {
    listPageSize = value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_keyListPageSize, value);
    });
  }

  void setMaxRecordingMinutes(int value) {
    maxRecordingMinutes = value;
    notifyListeners();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_keyMaxRecordingMinutes, value);
    });
  }

  void setAutoOffMinutes(int value) {
    autoOffMinutes = value;
    notifyListeners();
    // Session-only: not persisted. Resets to Off when app restarts.
  }
}
