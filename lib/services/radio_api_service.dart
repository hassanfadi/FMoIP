import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

class RadioApiService {
  /// Cached mapping of ISO country code -> API's country name.
  /// Populated when fetchCountriesWithCounts runs; used by fetchStations
  /// so the count and station list refer to the same dataset.
  static final Map<String, String> _apiCountryNameByCode = {};

  /// Fallback when cache is empty (e.g. restore at startup). API uses different names.
  static const Map<String, String> _apiNameFallbackByCode = {
    'AE': 'The United Arab Emirates',
    'AG': 'Antigua And Barbuda',
    'BA': 'Bosnia And Herzegovina',
    'BN': 'Brunei Darussalam',
    'BS': 'The Bahamas',
    'CD': 'The Democratic Republic Of The Congo',
    'CF': 'The Central African Republic',
    'CG': 'The Congo',
    'DO': 'The Dominican Republic',
    'FM': 'Federated States Of Micronesia',
    'GB': 'The United Kingdom Of Great Britain And Northern Ireland',
    'GM': 'The Gambia',
    'GW': 'Guinea Bissau',
    'IR': 'Islamic Republic Of Iran',
    'KM': 'The Comoros',
    'KN': 'Saint Kitts And Nevis',
    'KP': 'The Democratic Peoples Republic Of Korea',
    'KR': 'The Republic Of Korea',
    'LA': 'The Lao Peoples Democratic Republic',
    'MD': 'The Republic Of Moldova',
    'MH': 'The Marshall Islands',
    'MK': 'Republic Of North Macedonia',
    'NE': 'The Niger',
    'NL': 'The Netherlands',
    'PH': 'The Philippines',
    'RU': 'The Russian Federation',
    'SD': 'The Sudan',
    'ST': 'Sao Tome And Principe',
    'SY': 'Syrian Arab Republic',
    'TL': 'Timor Leste',
    'TR': 'Türkiye',
    'TT': 'Trinidad And Tobago',
    'TW': 'Taiwan, Republic Of China',
    'TZ': 'United Republic Of Tanzania',
    'US': 'The United States Of America',
    'VA': 'The Holy See',
    'VC': 'Saint Vincent And The Grenadines',
    'VE': 'Bolivarian Republic Of Venezuela',
  };

  /// Returns a map of ISO country code -> station count from the API.
  /// Uses hidebroken=true to exclude broken/unreachable stations, matching
  /// the filters we apply when fetching stations (valid name/url, dedup by streamUrl).
  /// Also caches the API's country name per code for use in fetchStations.
  Future<Map<String, int>> fetchCountriesWithCounts() async {
    final uri = Uri.parse(
      'https://de1.api.radio-browser.info/json/countries?hidebroken=true',
    );
    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Request timed out after 15 seconds');
        },
      );
      if (response.statusCode != 200) {
        throw Exception('Request failed with status ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      final result = <String, int>{};
      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;
        final code = (item['iso_3166_1'] as String?)?.trim().toUpperCase();
        final apiName = (item['name'] as String?)?.trim();
        final count = item['stationcount'];
        if (code != null && code.isNotEmpty) {
          if (apiName != null && apiName.isNotEmpty) {
            _apiCountryNameByCode[code] = apiName;
          }
          if (count != null && count is int && count >= 0) {
            result[code] = count;
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching country counts: $e');
      rethrow;
    }
  }

  /// Returns the API's country name for the given code, or fallback.
  String _apiCountryNameFor(Country country) {
    final code = country.code.toUpperCase();
    return _apiCountryNameByCode[code] ??
        _apiNameFallbackByCode[code] ??
        country.name;
  }

  Future<List<RadioStation>> fetchStations(Country country) async {
    final countryParam = _apiCountryNameFor(country);
    final uri = Uri.parse(
      'https://de1.api.radio-browser.info/json/stations/bycountry/${Uri.encodeComponent(countryParam)}?hidebroken=true&limit=100000',
    );
    debugPrint('Fetching stations from: $uri');
    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw TimeoutException('Request timed out after 30 seconds');
        },
      );
      debugPrint(
        'Response status: ${response.statusCode}, body length: ${response.body.length}',
      );
      if (response.statusCode != 200) {
        throw Exception('Request failed with status ${response.statusCode}');
      }
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      final mapped = data
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final name = (item['name'] as String?)?.trim();
            final url = (item['url_resolved'] as String?)?.trim();
            final frequency = (item['frequency'] as String?)?.trim();
            final rawFavicon = (item['favicon'] as String?)?.trim();
            final favicon = (rawFavicon == null ||
                    rawFavicon.isEmpty ||
                    rawFavicon.toLowerCase() == 'null')
                ? null
                : rawFavicon;
            final language = (item['language'] as String?)?.trim();
            final tags = (item['tags'] as String?)?.trim();
            final bitrateKbps =
                RadioStation.parseBitrateKbps(item['bitrate']);
            if (name == null || name.isEmpty || url == null || url.isEmpty) {
              return null;
            }
            return RadioStation(
              name: name,
              frequency: frequency?.isNotEmpty == true ? frequency! : 'FM',
              streamUrl: url,
              country: country.name,
              faviconUrl: favicon ?? '',
              language: language ?? '',
              tags: tags ?? '',
              bitrateKbps: bitrateKbps,
            );
          })
          .whereType<RadioStation>()
          .toList();
      final seenUrls = <String>{};
      final result = mapped.where((s) => seenUrls.add(s.streamUrl)).toList();
      debugPrint('Parsed ${result.length} stations from response (${mapped.length - result.length} duplicates removed)');
      return result;
    } catch (e) {
      debugPrint('Error fetching stations: $e');
      rethrow;
    }
  }
}
