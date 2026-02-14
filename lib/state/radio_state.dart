import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../services/radio_api_service.dart';
import 'settings_state.dart';

class RadioState extends ChangeNotifier {
  Country? selectedCountry;
  RadioStation? selectedStation;
  List<RadioStation> stations = [];
  List<RadioStation> _allStations = [];
  bool isLoading = false;
  String? errorMessage;
  bool isPrefetchingCountryCounts = false;
  double prefetchProgress = 0.0;
  final RadioApiService _service = RadioApiService();
  final Set<String> _favoriteStationIds = {};
  bool _dataSaverEnabled = false;
  bool _autoCountryRequested = false;
  static const String _lastCountryKey = 'last_country_code';
  static const String _favoriteStationsKey = 'favorite_station_ids';
  static const String _stationCountsKey = 'station_counts_by_code';
  static const String _countryCountsKey = 'country_counts_cache';
  static const String _countryCountsTimestampKey = 'country_counts_timestamp';
  static const Duration _cacheValidDuration = Duration(hours: 24);
  int _stationsPageSize = 40;
  int _visibleStationCount = 40;

  RadioState() {
    _initFuture = _initAsync();
  }

  late final Future<void> _initFuture;

  /// Completes when initial load is done (favorites + restored country + stations).
  /// Use to coordinate bootstrap: country → stations → combo counts.
  Future<void> ensureInitialized() => _initFuture;

  /// Load favorites first, then restore last country. Ensures favorites appear at top when stations load.
  Future<void> _initAsync() async {
    await _loadFavoriteStations();
    await _restoreLastCountry();
  }

  List<RadioStation> get visibleStations =>
      stations.take(_visibleStationCount).toList();

  List<RadioStation> get allStations => List<RadioStation>.from(_allStations);

  bool get hasMoreStations => stations.length > _visibleStationCount;

  void loadMoreStations() {
    if (!hasMoreStations) return;
    _visibleStationCount =
        min(_visibleStationCount + _stationsPageSize, stations.length);
    notifyListeners();
  }

  void setStationsPageSize(int value) {
    final next = value.clamp(5, SettingsState.maxListPageSize);
    if (_stationsPageSize == next) return;
    _stationsPageSize = next;
    _reconcileVisibleStations();
    notifyListeners();
  }

  void _reconcileVisibleStations() {
    if (_visibleStationCount <= 0) {
      _visibleStationCount = min(_stationsPageSize, stations.length);
      return;
    }
    if (_visibleStationCount > stations.length) {
      _visibleStationCount = stations.length;
    }
    if (_visibleStationCount < _stationsPageSize) {
      _visibleStationCount = min(_stationsPageSize, stations.length);
    }
  }

  Future<void> _restoreLastCountry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_lastCountryKey);
      if (code == null || code.isEmpty) return;
      final match = Country.defaults.firstWhere(
        (country) => country.code.toUpperCase() == code.toUpperCase(),
        orElse: () => Country.defaults.first,
      );
      await selectCountry(match);
    } catch (_) {}
  }

  Future<void> _persistSelectedCountry(Country country) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastCountryKey, country.code);
    } catch (_) {}
  }

  Future<void> _loadFavoriteStations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_favoriteStationsKey) ?? [];
      _favoriteStationIds..clear()..addAll(values);
      _applyFavoritesOrdering();
    } catch (_) {}
  }

  Future<void> _persistFavoriteStations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoriteStationsKey, _favoriteStationIds.toList());
    } catch (_) {}
  }

  /// Persists both full and data-saver-filtered counts. Combo uses these
  /// pre-calculated values so no filtering runs when opening the dropdown.
  Future<void> _persistStationCount(
    Country country, {
    required int fullCount,
    required int filteredCount,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_stationCountsKey);
      final map = existing != null
          ? Map<String, dynamic>.from(jsonDecode(existing) as Map)
          : <String, dynamic>{};
      map[country.code.toUpperCase()] = {
        'f': fullCount,
        'd': filteredCount,
      };
      await prefs.setString(_stationCountsKey, jsonEncode(map));
    } catch (_) {}
  }

  /// Returns country counts for the dropdown. No filtering runs.
  /// Uses our pre-calculated counts when available; API counts as fallback for unloaded countries.
  Future<Map<String, int>> getCountryCountsForDropdown() async {
    final cached = await getCachedStationCounts();
    final apiCounts = await _getCountryCountsWithCache();
    final merged = Map<String, int>.from(apiCounts);
    for (final e in cached.entries) {
      merged[e.key] = e.value;
    }
    return merged;
  }

  /// Prefetches API country counts only (~50KB). Does NOT fetch station lists to save data.
  /// Selected country is already loaded at app start. Dropdown uses API counts for others.
  void prefetchCountryCountsForDropdown() {
    isPrefetchingCountryCounts = true;
    prefetchProgress = 0.0;
    notifyListeners();
    _getCountryCountsWithCache().whenComplete(() {
      isPrefetchingCountryCounts = false;
      prefetchProgress = 0.0;
      notifyListeners();
    });
  }

  /// Fetches or loads from cache, then persists count. Uses centralized
  /// _loadStationsForCountry so counts match displayed stations. Does not modify
  /// selectedCountry, stations, or _favoriteStationIds.
  Future<void> _fetchAndPersistCountryCount(Country country) async {
    try {
      await _loadStationsForCountry(
        country,
        forceRefresh: false,
        restoreFavoritesFromCache: false,
      );
    } catch (_) {}
  }

  Future<void> _persistApiCountryCounts(Map<String, int> counts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_countryCountsKey, jsonEncode(counts));
      await prefs.setInt(
        _countryCountsTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<Map<String, int>> _getCountryCountsWithCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_countryCountsTimestampKey);
      if (ts != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(ts),
        );
        if (age < _cacheValidDuration) {
          final json = prefs.getString(_countryCountsKey);
          if (json != null && json.isNotEmpty) {
            final decoded = jsonDecode(json);
            if (decoded is Map) {
              return decoded.map((k, v) =>
                  MapEntry((k as String).toUpperCase(), (v as num).toInt()));
            }
          }
        }
      }
    } catch (_) {}
    try {
      final counts = await _service.fetchCountriesWithCounts();
      await _persistApiCountryCounts(counts);
      return counts;
    } catch (e) {
      debugPrint('Error fetching country counts: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString(_countryCountsKey);
        if (json != null && json.isNotEmpty) {
          final decoded = jsonDecode(json);
          if (decoded is Map) {
            return decoded.map((k, v) =>
                MapEntry((k as String).toUpperCase(), (v as num).toInt()));
          }
        }
      } catch (_) {}
      return {};
    }
  }

  /// Returns pre-calculated station counts per country. Uses full or data-saver
  /// count based on current setting. No filtering; just reads persisted values.
  Future<Map<String, int>> getCachedStationCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_stationCountsKey);
      if (json == null || json.isEmpty) return {};
      final decoded = jsonDecode(json);
      if (decoded is! Map) return {};
      final result = <String, int>{};
      for (final e in decoded.entries) {
        final key = (e.key as String).toUpperCase();
        final v = e.value;
        if (v is Map && v['f'] != null && v['d'] != null) {
          final val = _dataSaverEnabled ? v['d'] : v['f'];
          result[key] = (val as num).toInt();
        } else if (v is num) {
          result[key] = v.toInt(); // legacy format
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<File> _stationsCacheFile(Country country) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/stations_${country.code.toLowerCase()}.json');
  }

  Future<File> _stationsMetaFile(Country country) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/stations_${country.code.toLowerCase()}_meta.json');
  }

  Future<DateTime?> _getCachedStationsTimestamp(Country country) async {
    try {
      final file = await _stationsMetaFile(country);
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return null;
      final ms = data['fetchedAt'];
      if (ms is int && ms > 0) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isStationsCacheFresh(Country country) async {
    final ts = await _getCachedStationsTimestamp(country);
    if (ts == null) return false;
    return DateTime.now().difference(ts) < _cacheValidDuration;
  }

  Future<void> _saveStationsCacheMeta(Country country) async {
    try {
      final file = await _stationsMetaFile(country);
      await file.writeAsString(
        jsonEncode({'fetchedAt': DateTime.now().millisecondsSinceEpoch}),
      );
    } catch (_) {}
  }

  /// Loads cached stations from disk. When [restoreFavoritesFromCache] is true
  /// (e.g. for selectCountry), favorited stations in the cache are added to
  /// _favoriteStationIds. Pass false for prefetch/count-only loads.
  Future<List<RadioStation>?> _loadCachedStations(
    Country country, {
    bool restoreFavoritesFromCache = true,
  }) async {
    try {
      final file = await _stationsCacheFile(country);
      if (!await file.exists()) return null;
      final contents = await file.readAsString();
      final data = jsonDecode(contents);
      if (data is! List) return null;
      final list = data
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final streamUrl = item['streamUrl']?.toString() ?? '';
            final isFavorite = item['favorite'] == true;
            if (restoreFavoritesFromCache && isFavorite && streamUrl.isNotEmpty) {
              _favoriteStationIds.add(streamUrl);
            }
            final rawFavicon = (item['faviconUrl']?.toString() ?? '').trim();
            final faviconUrl = (rawFavicon == null ||
                    rawFavicon.isEmpty ||
                    rawFavicon.toLowerCase() == 'null')
                ? ''
                : rawFavicon;
            final bitrateKbps = RadioStation.parseBitrateKbps(
                item['bitrateKbps'] ?? item['bitrate']);
            return RadioStation(
              name: item['name']?.toString() ?? '',
              frequency: item['frequency']?.toString() ?? 'FM',
              streamUrl: streamUrl,
              country: item['country']?.toString() ?? country.name,
              faviconUrl: faviconUrl,
              language: item['language']?.toString() ?? '',
              tags: item['tags']?.toString() ?? '',
              bitrateKbps: bitrateKbps,
            );
          })
          .where((s) => s.name.isNotEmpty && s.streamUrl.isNotEmpty)
          .toList();
      final seenUrls = <String>{};
      return list.where((s) => seenUrls.add(s.streamUrl)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCachedStations(
      Country country, List<RadioStation> list) async {
    try {
      final file = await _stationsCacheFile(country);
      final data = list
          .map((s) => {
                'name': s.name,
                'frequency': s.frequency,
                'streamUrl': s.streamUrl,
                'country': s.country,
                'faviconUrl': s.faviconUrl,
                'language': s.language,
                'tags': s.tags,
                'bitrateKbps': s.bitrateKbps,
                'favorite': _favoriteStationIds.contains(s.streamUrl),
              })
          .toList();
      await file.writeAsString(jsonEncode(data));
      await _saveStationsCacheMeta(country);
    } catch (_) {}
  }

  void setDataSaverEnabled(bool value) {
    if (_dataSaverEnabled == value) return;
    _dataSaverEnabled = value;
    _applyDataSaverFilter();
    final country = selectedCountry;
    if (country != null && _allStations.isNotEmpty) {
      _persistStationCount(
        country,
        fullCount: _allStations.length,
        filteredCount: stations.length,
      );
    }
    notifyListeners();
  }

  /// Data saver threshold in kbps. 128 is a common internet radio bitrate.
  static const int _dataSaverMaxBitrateKbps = 128;

  /// Applies data saver filter to a list. Returns filtered list or full list if filter would be empty.
  List<RadioStation> _applyDataSaverFilterToList(List<RadioStation> list) {
    if (list.isEmpty) return list;
    if (!_dataSaverEnabled) return List.from(list);
    final filtered = list.where((s) {
      final kbps = s.bitrateKbps;
      return kbps == null || kbps <= _dataSaverMaxBitrateKbps;
    }).toList();
    return filtered.isNotEmpty ? filtered : List.from(list);
  }

  /// Sorts by favorites first, then stations with icons, then the rest.
  List<RadioStation> _sortStationsByFavoritesAndIcon(List<RadioStation> list) {
    if (list.isEmpty) return list;
    final favs =
        list.where((s) => _favoriteStationIds.contains(s.streamUrl)).toList();
    final nonFavs =
        list.where((s) => !_favoriteStationIds.contains(s.streamUrl)).toList();
    final withIcon = nonFavs.where(_hasFavicon).toList();
    final withoutIcon = nonFavs.where((s) => !_hasFavicon(s)).toList();
    return [...favs, ...withIcon, ...withoutIcon];
  }

  /// Result of loading stations: [filtered] is shown in UI, [raw] is full list for _allStations.
  List<RadioStation> _filterAndSort(List<RadioStation> raw) =>
      _sortStationsByFavoritesAndIcon(_applyDataSaverFilterToList(raw));

  /// Single source of truth for loading stations: cache (if fresh) or API.
  /// Applies data saver filter and favorites ordering. Persists count and saves cache.
  /// Does not modify [stations] or [_allStations]; caller must set state.
  /// Returns (filtered, raw) – raw is the full unfiltered list for _allStations.
  Future<({List<RadioStation> filtered, List<RadioStation> raw})> _loadStationsForCountry(
    Country country, {
    bool forceRefresh = false,
    bool restoreFavoritesFromCache = true,
  }) async {
    if (!forceRefresh) {
      final cached = await _loadCachedStations(
        country,
        restoreFavoritesFromCache: restoreFavoritesFromCache,
      );
      final cacheFresh = await _isStationsCacheFresh(country);
      if (cached != null && cached.isNotEmpty && cacheFresh) {
        final filtered = _filterAndSort(cached);
        await _persistStationCount(
          country,
          fullCount: cached.length,
          filteredCount: filtered.length,
        );
        return (filtered: filtered, raw: cached);
      }
    }
    final raw = await _service.fetchStations(country);
    final filtered = _filterAndSort(raw);
    await _persistStationCount(
      country,
      fullCount: raw.length,
      filteredCount: filtered.length,
    );
    await _saveCachedStations(country, raw);
    return (filtered: filtered, raw: raw);
  }

  void _applyDataSaverFilter() {
    if (_allStations.isEmpty) return;
    stations = _filterAndSort(_allStations);
    _reconcileVisibleStations();
  }

  static bool _hasFavicon(RadioStation s) {
    final url = s.faviconUrl.trim();
    return url.isNotEmpty && url.toLowerCase() != 'null';
  }

  void _applyFavoritesOrdering() {
    if (stations.isEmpty) return;
    stations = _sortStationsByFavoritesAndIcon(stations);
    _reconcileVisibleStations();
    notifyListeners();
  }

  Future<void> selectCountry(Country country) async {
    selectedCountry = country;
    selectedStation = null;
    errorMessage = null;
    notifyListeners();
    await _persistSelectedCountry(country);
    List<RadioStation>? staleCached;
    try {
      final cached = await _loadCachedStations(
        country,
        restoreFavoritesFromCache: true,
      );
      final cacheFresh = await _isStationsCacheFresh(country);
      if (cached != null && cached.isNotEmpty && cacheFresh) {
        final list = _filterAndSort(cached);
        stations = list;
        _allStations = List.from(cached);
        await _persistStationCount(
          country,
          fullCount: cached.length,
          filteredCount: list.length,
        );
        _reconcileVisibleStations();
        notifyListeners();
        debugPrint('Loaded ${stations.length} stations for ${country.name} from cache (< 24h)');
        return;
      }
      if (cached != null && cached.isNotEmpty && !cacheFresh) {
        staleCached = _filterAndSort(cached);
        stations = staleCached;
        _allStations = List.from(cached);
        await _persistStationCount(
          country,
          fullCount: cached.length,
          filteredCount: staleCached.length,
        );
        _reconcileVisibleStations();
        notifyListeners();
      }
      isLoading = true;
      notifyListeners();
      try {
        final result = await _loadStationsForCountry(country, forceRefresh: true);
        stations = result.filtered;
        _allStations = result.raw;
        _reconcileVisibleStations();
        debugPrint('Loaded ${stations.length} stations for ${country.name} from API');
      } catch (e) {
        if (staleCached == null) rethrow;
        debugPrint('Failed to refresh ${country.name}: $e (using cached)');
      }
    } catch (e) {
      if (staleCached == null) {
        debugPrint('Failed to load stations for ${country.name}: $e');
        errorMessage = 'Failed to load stations. Please try again.';
        stations = [];
        _allStations = [];
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStations() async {
    final country = selectedCountry;
    if (country == null) return;
    final selectedStreamUrl = selectedStation?.streamUrl;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _loadStationsForCountry(
        country,
        forceRefresh: true,
        restoreFavoritesFromCache: true,
      );
      stations = result.filtered;
      _allStations = result.raw;
      if (selectedStreamUrl != null) {
        final match = _allStations.firstWhere(
          (s) => s.streamUrl == selectedStreamUrl,
          orElse: () => selectedStation!,
        );
        selectedStation = match;
      }
      _reconcileVisibleStations();
    } catch (_) {
      errorMessage = 'Failed to refresh stations. Please try again.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Uses location only once on first launch when no country is saved.
  /// After the country is determined (or user picks one), location is never used again.
  Future<void> ensureAutoCountrySelected() async {
    if (_autoCountryRequested || selectedCountry != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_lastCountryKey) != null) return;
    } catch (_) {}
    _autoCountryRequested = true;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );
      final placemarks = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return;
      final countryCode = placemarks.first.isoCountryCode;
      if (countryCode == null) return;
      final match = Country.defaults.firstWhere(
        (c) => c.code.toUpperCase() == countryCode.toUpperCase(),
        orElse: () => Country.defaults.first,
      );
      await selectCountry(match);
    } catch (_) {}
  }

  void selectStation(RadioStation station) {
    selectedStation = station;
    notifyListeners();
  }

  bool isFavoriteStation(RadioStation station) =>
      _favoriteStationIds.contains(station.streamUrl);

  List<RadioStation> sortStationsByFavorite(List<RadioStation> list) {
    return _sortStationsByIconAndFavorite(list);
  }

  /// Sorts stations: favorites first, then with icons, then the rest.
  List<RadioStation> _sortStationsByIconAndFavorite(List<RadioStation> list) {
    final favs =
        list.where((s) => _favoriteStationIds.contains(s.streamUrl)).toList();
    final nonFavs =
        list.where((s) => !_favoriteStationIds.contains(s.streamUrl)).toList();
    final withIcon = nonFavs.where(_hasFavicon).toList();
    final withoutIcon = nonFavs.where((s) => !_hasFavicon(s)).toList();
    return [...favs, ...withIcon, ...withoutIcon];
  }

  Future<void> toggleFavoriteStation(RadioStation station) async {
    if (_favoriteStationIds.contains(station.streamUrl)) {
      _favoriteStationIds.remove(station.streamUrl);
    } else {
      _favoriteStationIds.add(station.streamUrl);
    }
    _applyFavoritesOrdering();
    await _persistFavoriteStations();
    final country = selectedCountry;
    if (country != null) {
      await _saveCachedStations(
        country,
        _allStations.isNotEmpty ? _allStations : stations,
      );
    }
  }
}
