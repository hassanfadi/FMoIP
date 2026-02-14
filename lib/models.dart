import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Country model with ISO code. Load [defaults] via [loadDefaults] at startup.
class Country {
  const Country({required this.name, required this.code});

  final String name;
  final String code;

  static List<Country>? _cachedDefaults;

  static List<Country> get defaults {
    if (_cachedDefaults == null) {
      throw StateError(
        'Country.defaults accessed before Country.loadDefaults() was called. '
        'Call Country.loadDefaults() in main() before using Country.defaults.',
      );
    }
    return _cachedDefaults!;
  }

  static Future<void> loadDefaults() async {
    if (_cachedDefaults != null) return;
    try {
      final jsonString =
          await rootBundle.loadString('assets/l10n/countries.json');
      final jsonList = json.decode(jsonString) as List<dynamic>;
      _cachedDefaults = jsonList.map((item) {
        final map = item as Map<String, dynamic>;
        return Country(name: map['name'] as String, code: map['code'] as String);
      }).toList();
    } catch (e) {
      _cachedDefaults = [];
    }
  }
}

class RadioStation {
  RadioStation({
    required this.name,
    required this.frequency,
    required this.streamUrl,
    required this.country,
    required this.faviconUrl,
    required this.language,
    required this.tags,
    this.bitrateKbps,
  });

  final String name;
  final String frequency;
  final String streamUrl;
  final String country;
  final String faviconUrl;
  final String language;
  final String tags;

  /// Bitrate in kbps from API ( structured) or parsed from cache. Null when unknown.
  final int? bitrateKbps;

  /// Parses bitrate from API/cache raw value (int or string). Returns null if invalid.
  static int? parseBitrateKbps(dynamic raw) {
    if (raw is int && raw > 0) return raw;
    final parsed = int.tryParse((raw?.toString() ?? '').trim());
    return parsed != null && parsed > 0 ? parsed : null;
  }

  /// Display string for bitrate (e.g. "128 kbps").
  String get bitrate =>
      bitrateKbps != null ? '$bitrateKbps kbps' : '';

  @override
  bool operator ==(Object other) {
    return other is RadioStation && other.streamUrl == streamUrl;
  }

  @override
  int get hashCode => streamUrl.hashCode;
}

enum RecordingQuality { low, medium, high }

enum RecordingMode { withBackground, streamOnly }

class RecordingItem {
  RecordingItem({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.createdAt,
    required this.stationName,
    required this.mode,
    required this.durationSeconds,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime createdAt;
  final String stationName;
  final RecordingMode? mode;
  final int? durationSeconds;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sizeBytes B';
  }

  factory RecordingItem.fromFile(
    File file, {
    String? stationName,
    RecordingMode? mode,
    int? durationSeconds,
    String? displayName,
  }) {
    final stat = file.statSync();
    final rawName = file.uri.pathSegments.last;
    final name = rawName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return RecordingItem(
      name: (displayName != null && displayName.isNotEmpty) ? displayName : name,
      path: file.path,
      sizeBytes: stat.size,
      createdAt: stat.modified,
      stationName: stationName ?? '-',
      mode: mode,
      durationSeconds: durationSeconds,
    );
  }
}
