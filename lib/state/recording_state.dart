import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'settings_state.dart';

/// Formats [dt] as yearmonthdayhourminutesecondmillisecond (e.g. 20250207143025123).
String _formatTimestampForRecording(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  final ms = dt.millisecond.toString().padLeft(3, '0');
  return '$y$m$d$h$min$s$ms';
}

class RecordingState extends ChangeNotifier {
  bool isRecording = false;
  bool isVoiceRecording = false;
  /// Key for localized error message. Resolve with AppLocalizations.recordingErrorMessage.
  String? errorMessageKey;
  final List<RecordingItem> recordings = [];
  final Set<String> _favoriteRecordingPaths = {};
  static const String _favoriteRecordingsKey = 'favorite_recording_paths';
  int _recordingsPageSize = 30;
  int _visibleRecordingCount = 30;
  http.Client? _client;
  StreamSubscription<List<int>>? _subscription;
  IOSink? _fileSink;
  File? _currentFile;
  File? _currentVoiceFile;
  bool _shouldResumePlayback = false;
  RecordingMode? _activeMode;
  DateTime? _recordingStartedAt;
  int _recordingBytes = 0;
  bool showRecordingsList = false;
  String? _recordingStationName;
  RecordingMode? _recordingMode;
  DateTime? _voiceRecordingStartedAt;
  AudioRecorder? _voiceRecorder;
  Timer? _recordingDurationTimer;
  Timer? _recordingFlushTimer;
  int _maxRecordingMinutes = 60;
  bool _stopRecordingInProgress = false;
  // ICY/Shoutcast metadata stripping (null = pass-through)
  int? _icyMetaint;
  int _icyBytesUntilMeta = 0;
  int _icySkipCount = 0;
  final List<int> _icyBuffer = [];

  RecordingState() {
    _loadExistingRecordings();
    _initVoiceRecorder();
    _loadFavoriteRecordings();
  }

  void setMaxRecordingMinutes(int minutes) {
    _maxRecordingMinutes = minutes;
  }

  void _startRecordingDurationTimer() {
    _recordingDurationTimer?.cancel();
    final maxDuration = Duration(minutes: _maxRecordingMinutes);
    _recordingDurationTimer = Timer(maxDuration, () {
      if (isRecording) {
        stopRecording();
        errorMessageKey = 'recordingMaxDuration';
        notifyListeners();
      } else if (isVoiceRecording) {
        stopVoiceRecording();
        errorMessageKey = 'recordingMaxDuration';
        notifyListeners();
      }
    });
  }

  Future<void> _loadFavoriteRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_favoriteRecordingsKey) ?? [];
      _favoriteRecordingPaths
        ..clear()
        ..addAll(values);
      _applyFavoriteRecordingsOrdering();
    } catch (_) {
      // Ignore restore errors.
    }
  }

  Future<void> _persistFavoriteRecordings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _favoriteRecordingsKey,
        _favoriteRecordingPaths.toList(),
      );
    } catch (_) {
      // Ignore persistence errors.
    }
  }

  void _applyFavoriteRecordingsOrdering() {
    if (recordings.isEmpty || _favoriteRecordingPaths.isEmpty) {
      return;
    }
    final favs = <RecordingItem>[];
    final rest = <RecordingItem>[];
    for (final item in recordings) {
      if (_favoriteRecordingPaths.contains(item.path)) {
        favs.add(item);
      } else {
        rest.add(item);
      }
    }
    recordings
      ..clear()
      ..addAll([...favs, ...rest]);
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  bool isFavoriteRecording(RecordingItem item) {
    return _favoriteRecordingPaths.contains(item.path);
  }

  List<RecordingItem> sortRecordingsByFavorite(List<RecordingItem> list) {
    if (_favoriteRecordingPaths.isEmpty) {
      return List<RecordingItem>.from(list);
    }
    final favs = <RecordingItem>[];
    final rest = <RecordingItem>[];
    for (final item in list) {
      if (_favoriteRecordingPaths.contains(item.path)) {
        favs.add(item);
      } else {
        rest.add(item);
      }
    }
    return [...favs, ...rest];
  }

  Future<void> toggleFavoriteRecording(RecordingItem item) async {
    if (_favoriteRecordingPaths.contains(item.path)) {
      _favoriteRecordingPaths.remove(item.path);
    } else {
      _favoriteRecordingPaths.add(item.path);
      recordings.removeWhere((recording) => recording.path == item.path);
      recordings.insert(0, item);
      _reconcileVisibleRecordings();
    }
    notifyListeners();
    await _persistFavoriteRecordings();
  }

  List<RecordingItem> get visibleRecordings =>
      recordings.take(_visibleRecordingCount).toList();

  bool get hasMoreRecordings => recordings.length > _visibleRecordingCount;

  void loadMoreRecordings() {
    if (!hasMoreRecordings) {
      return;
    }
    _visibleRecordingCount =
        min(_visibleRecordingCount + _recordingsPageSize, recordings.length);
    notifyListeners();
  }

  void setRecordingsPageSize(int value) {
    final next = value.clamp(5, SettingsState.maxListPageSize);
    if (_recordingsPageSize == next) {
      return;
    }
    _recordingsPageSize = next;
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  void _reconcileVisibleRecordings() {
    if (_visibleRecordingCount <= 0) {
      _visibleRecordingCount = min(_recordingsPageSize, recordings.length);
      return;
    }
    if (_visibleRecordingCount > recordings.length) {
      _visibleRecordingCount = recordings.length;
    }
    if (_visibleRecordingCount < _recordingsPageSize) {
      _visibleRecordingCount = min(_recordingsPageSize, recordings.length);
    }
  }

  Future<void> _initVoiceRecorder() async {
    _voiceRecorder ??= AudioRecorder();
  }

  Future<File> _metadataFileForRecording(File file) async {
    final base = file.path.replaceAll(RegExp(r'\.[^.]+$'), '');
    return File('$base.json');
  }

  Future<Map<String, dynamic>?> _loadRecordingMetadata(File file) async {
    try {
      final metaFile = await _metadataFileForRecording(file);
      if (!await metaFile.exists()) {
        return null;
      }
      final contents = await metaFile.readAsString();
      final data = jsonDecode(contents);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRecordingMetadata(
    File file, {
    required String stationName,
    RecordingMode? mode,
    DateTime? createdAt,
    int? durationSeconds,
    String? displayName,
  }) async {
    try {
      final metaFile = await _metadataFileForRecording(file);
      final data = <String, dynamic>{
        'stationName': stationName,
        'mode': mode?.name,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
      };
      await metaFile.writeAsString(jsonEncode(data));
    } catch (_) {
      // Ignore metadata write errors.
    }
  }

  RecordingMode? _modeFromString(String? value) {
    switch (value) {
      case 'withBackground':
        return RecordingMode.withBackground;
      case 'streamOnly':
        return RecordingMode.streamOnly;
      default:
        return null;
    }
  }

  Future<void> _loadExistingRecordings() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory
        .listSync()
        .whereType<File>()
        .where(_isRecordingFile)
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    recordings.clear();
    for (final file in files) {
      final meta = await _loadRecordingMetadata(file);
      final stationName = meta?['stationName']?.toString();
      final mode = _modeFromString(meta?['mode']?.toString());
      final durationSeconds = int.tryParse(meta?['durationSeconds']?.toString() ?? '');
      final displayName = meta?['displayName']?.toString();
      recordings.add(
        RecordingItem.fromFile(
          file,
          stationName: stationName,
          mode: mode,
          durationSeconds: durationSeconds,
          displayName: displayName,
        ),
      );
    }
    _reconcileVisibleRecordings();
    _applyFavoriteRecordingsOrdering();
    notifyListeners();
  }

  bool _isRecordingFile(File file) {
    final lower = file.path.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav');
  }

  static const int _maxRedirects = 5;

  Future<http.StreamedResponse?> _sendWithRedirects(
    http.Client client,
    String url,
  ) async {
    var currentUrl = url;
    for (var i = 0; i < _maxRedirects; i++) {
      final uri = Uri.tryParse(currentUrl);
      if (uri == null || !uri.hasScheme) return null;
      final request = http.Request('GET', uri);
      request.headers['Icy-MetaData'] = '1';
      request.headers['User-Agent'] =
          'Mozilla/5.0 (compatible; FMoIP/1.0; +https://github.com/fmoip)';
      request.headers['Accept'] = '*/*';
      final response = await client.send(request).timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException('Connection timeout'),
          );
      final code = response.statusCode;
      if (code >= 200 && code < 300) return response;
      if (code != 301 && code != 302 && code != 307 && code != 308) return null;
      final location = response.headers['location']?.trim();
      if (location == null || location.isEmpty) return null;
      await response.stream.drain<void>();
      currentUrl = uri.resolveUri(Uri.parse(location)).toString();
    }
    return null;
  }

  /// Uses player's stream (single fetch) for withBackground recording.
  Future<void> _startRecordingFromTee(
    RadioStation station,
    String streamUrl,
    Directory directory,
    DateTime timestamp,
    Future<void> Function(
      void Function(Map<String, String> headers) onHeaders,
      void Function(List<int> chunk) onChunk,
    ) playWithRecordingTee,
  ) async {
    void Function(Map<String, String> headers) onHeaders = (headers) {
      final contentType = headers['content-type']?.toLowerCase() ?? '';
      final extension = _extensionFromContentType(contentType) ??
          _extensionFromUrl(streamUrl) ??
          'mp3';
      final filePath =
          '${directory.path}/rec_${_formatTimestampForRecording(timestamp)}.$extension';
      _currentFile = File(filePath);
      _fileSink = _currentFile!.openWrite();
      _recordingStartedAt = DateTime.now();
      _recordingBytes = 0;
      _icyMetaint = int.tryParse(headers['icy-metaint']?.trim() ?? '');
      _icyBytesUntilMeta = _icyMetaint ?? 0;
      _icySkipCount = 0;
      _icyBuffer.clear();
      _startRecordingDurationTimer();
      _recordingFlushTimer?.cancel();
      _recordingFlushTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        _fileSink?.flush();
      });
      notifyListeners();
    };
    void Function(List<int> chunk) onChunk = (chunk) {
      if (!isRecording) return;
      final sink = _fileSink;
      if (sink == null) return;
      if (chunk.isNotEmpty) {
        _writeAudioOnly(chunk, sink);
      }
    };
    await playWithRecordingTee(onHeaders, onChunk);
  }

  /// Writes only audio bytes to [sink], stripping ICY/Shoutcast metadata blocks
  /// when [ _icyMetaint] is set. Updates [_recordingBytes].
  void _writeAudioOnly(List<int> chunk, IOSink sink) {
    if (_icyMetaint == null || _icyMetaint! <= 0) {
      _recordingBytes += chunk.length;
      sink.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
      return;
    }
    final metaint = _icyMetaint!;
    List<int> data = chunk;
    while (data.isNotEmpty) {
      if (_icySkipCount > 0) {
        final toSkip = _icySkipCount < data.length ? _icySkipCount : data.length;
        data = data.sublist(toSkip);
        _icySkipCount -= toSkip;
        continue;
      }
      if (_icyBytesUntilMeta <= 0) {
        _icyBytesUntilMeta = metaint;
      }
      final toWrite = _icyBytesUntilMeta < data.length ? _icyBytesUntilMeta : data.length;
      if (toWrite > 0) {
        final audio = data.sublist(0, toWrite);
        sink.add(audio is Uint8List ? audio : Uint8List.fromList(audio));
        _recordingBytes += toWrite;
        data = data.sublist(toWrite);
        _icyBytesUntilMeta -= toWrite;
      }
      if (_icyBytesUntilMeta > 0) {
        break;
      }
      if (data.isEmpty) break;
      final metaLen = (data[0] & 0xFF) * 16;
      data = data.sublist(1);
      if (metaLen > 0) {
        if (data.length >= metaLen) {
          data = data.sublist(metaLen);
        } else {
          _icySkipCount = metaLen - data.length;
          data = [];
        }
      }
      _icyBytesUntilMeta = metaint;
    }
  }

  Future<void> startRecording(
    RadioStation station, {
    required RecordingMode mode,
    void Function(int bytes)? onDataUsage,
    Future<void> Function(
      void Function(Map<String, String> headers) onHeaders,
      void Function(List<int> chunk) onChunk,
    )? playWithRecordingTee,
  }) async {
    if (isRecording) {
      return;
    }
    final streamUrl = station.streamUrl.trim();
    if (streamUrl.isEmpty) {
      errorMessageKey = 'cannotRecordNoStreamUrl';
      notifyListeners();
      return;
    }
    final uri = Uri.tryParse(streamUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      errorMessageKey = 'cannotRecordInvalidUrl';
      notifyListeners();
      return;
    }
    errorMessageKey = null;
    _activeMode = mode;
    _recordingMode = mode;
    _recordingStationName = station.name;
    isRecording = true;
    notifyListeners();
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now();

    if (mode == RecordingMode.withBackground && playWithRecordingTee != null) {
      await _startRecordingFromTee(
        station,
        streamUrl,
        directory,
        timestamp,
        playWithRecordingTee,
      );
      return;
    }

    _client = http.Client();
    try {
      final response = await _sendWithRedirects(_client!, streamUrl);
      if (response == null) {
        errorMessageKey = 'cannotRecordConnectionFailed';
        _client!.close();
        _client = null;
        _activeMode = null;
        isRecording = false;
        notifyListeners();
        return;
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final extension = _extensionFromContentType(contentType) ??
          _extensionFromUrl(streamUrl) ??
          'mp3';
      final filePath =
          '${directory.path}/rec_${_formatTimestampForRecording(timestamp)}.$extension';
      _currentFile = File(filePath);
      _fileSink = _currentFile!.openWrite();
      _recordingStartedAt = DateTime.now();
      _recordingBytes = 0;
      _icyMetaint = int.tryParse(response.headers['icy-metaint']?.trim() ?? '');
      _icyBytesUntilMeta = _icyMetaint ?? 0;
      _icySkipCount = 0;
      _icyBuffer.clear();
      _startRecordingDurationTimer();
      _recordingFlushTimer?.cancel();
      _recordingFlushTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        _fileSink?.flush();
      });
      notifyListeners();
      _subscription = response.stream.listen(
        (data) {
          if (!isRecording) return;
          final sink = _fileSink;
          if (sink == null) return;
          if (data.isNotEmpty) {
            final bytes = data is Uint8List ? data.length : data.length;
            onDataUsage?.call(bytes);
            _writeAudioOnly(data is Uint8List ? data : data as List<int>, sink);
          }
        },
        onError: (e) async {
          debugPrint('Station recording stream error: $e');
          await stopRecording();
          errorMessageKey = 'cannotRecordStreamError';
          notifyListeners();
        },
        onDone: () async {
          await stopRecording();
        },
        cancelOnError: true,
      );
    } catch (e, st) {
      debugPrint('Station recording failed: $e\n$st');
      _client?.close();
      _client = null;
      _activeMode = null;
      isRecording = false;
      errorMessageKey = e is TimeoutException
          ? 'cannotRecordConnectionTimeout'
          : 'cannotRecordConnectionFailed';
      notifyListeners();
    }
  }

  Future<void> startVoiceRecording() async {
    if (isVoiceRecording || isRecording) {
      return;
    }
    await _initVoiceRecorder();
    final hasPermission = await _voiceRecorder!.hasPermission();
    if (!hasPermission) {
      errorMessageKey = 'microphonePermissionRequired';
      notifyListeners();
      return;
    }
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now();
    final filePath = '${directory.path}/voice_${_formatTimestampForRecording(timestamp)}.m4a';
    _currentVoiceFile = File(filePath);
    _voiceRecordingStartedAt = timestamp;
    errorMessageKey = null;
    await _voiceRecorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        androidConfig: AndroidRecordConfig(muteAudio: false),
        audioInterruption: AudioInterruptionMode.none,
      ),
      path: filePath,
    );
    isVoiceRecording = true;
    _startRecordingDurationTimer();
    notifyListeners();
  }

  Future<void> stopVoiceRecording() async {
    if (!isVoiceRecording) {
      return;
    }
    _recordingDurationTimer?.cancel();
    final durationSeconds = _voiceRecordingStartedAt == null
        ? null
        : DateTime.now().difference(_voiceRecordingStartedAt!).inSeconds;
    await _voiceRecorder?.stop();
    isVoiceRecording = false;
    if (_currentVoiceFile != null && await _currentVoiceFile!.exists()) {
      await _saveRecordingMetadata(
        _currentVoiceFile!,
        stationName: 'Voice note',
        mode: null,
        createdAt: _voiceRecordingStartedAt,
        durationSeconds: durationSeconds,
      );
      recordings.insert(
        0,
        RecordingItem.fromFile(
          _currentVoiceFile!,
          stationName: 'Voice note',
          mode: null,
        ),
      );
      if (recordings.length > 50) {
        recordings.removeRange(50, recordings.length);
      }
    }
    _currentVoiceFile = null;
    _voiceRecordingStartedAt = null;
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  Future<void> stopRecording() async {
    if (!isRecording || _stopRecordingInProgress) {
      return;
    }
    _stopRecordingInProgress = true;
    try {
      _recordingDurationTimer?.cancel();
      _recordingFlushTimer?.cancel();
      isRecording = false;
      _icyMetaint = null;
      _icyBytesUntilMeta = 0;
      _icySkipCount = 0;
      _icyBuffer.clear();
      notifyListeners();
      final startedAt = _recordingStartedAt ?? DateTime.now();
      final durationSeconds = DateTime.now().difference(startedAt).inSeconds;
      final subscription = _subscription;
      final sink = _fileSink;
      final client = _client;
      _subscription = null;
      _fileSink = null;
      _client = null;
      try {
        await subscription?.cancel();
        await sink?.flush();
        await sink?.close();
      } finally {
        client?.close();
      }
      _activeMode = null;
      _shouldResumePlayback = false;
      var discardRecording = false;
      if (_recordingStartedAt != null) {
        final elapsed = DateTime.now().difference(_recordingStartedAt!);
        if (elapsed < const Duration(seconds: 1)) {
          discardRecording = true;
          errorMessageKey = _recordingBytes == 0
              ? 'cannotRecordNotSupported'
              : 'recordingTooShort';
        } else if (_recordingBytes == 0) {
          discardRecording = true;
          errorMessageKey = 'cannotRecordNoDataProxy';
        }
      }
      if (_currentFile != null && await _currentFile!.exists()) {
        if (discardRecording) {
          await _currentFile!.delete();
        } else {
          await _saveRecordingMetadata(
            _currentFile!,
            stationName: _recordingStationName ?? '-',
            mode: _recordingMode,
            createdAt: _recordingStartedAt,
            durationSeconds: durationSeconds,
          );
          recordings.insert(
            0,
            RecordingItem.fromFile(
              _currentFile!,
              stationName: _recordingStationName,
              mode: _recordingMode,
            ),
          );
          if (recordings.length > 50) {
            recordings.removeRange(50, recordings.length);
          }
        }
      }
      _currentFile = null;
      _recordingStartedAt = null;
      _recordingBytes = 0;
      _recordingStationName = null;
      _recordingMode = null;
      _reconcileVisibleRecordings();
      notifyListeners();
    } finally {
      _stopRecordingInProgress = false;
    }
  }

  Future<void> deleteRecording(RecordingItem item) async {
    final file = File(item.path);
    if (await file.exists()) {
      await file.delete();
    }
    try {
      final metaFile = await _metadataFileForRecording(file);
      if (await metaFile.exists()) {
        await metaFile.delete();
      }
    } catch (_) {
      // Ignore metadata delete errors.
    }
    recordings.removeWhere((recording) => recording.path == item.path);
    _favoriteRecordingPaths.remove(item.path);
    await _persistFavoriteRecordings();
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  Future<void> reloadRecordings() async {
    await _loadExistingRecordings();
  }

  Future<void> updateRecordingDisplayName(RecordingItem item, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final file = File(item.path);
    if (!await file.exists()) {
      return;
    }
    await _saveRecordingMetadata(
      file,
      stationName: item.stationName,
      mode: item.mode,
      createdAt: item.createdAt,
      durationSeconds: item.durationSeconds,
      displayName: trimmed,
    );
    final updated = RecordingItem.fromFile(
      file,
      stationName: item.stationName,
      mode: item.mode,
      durationSeconds: item.durationSeconds,
      displayName: trimmed,
    );
    _replaceRecording(item.path, updated);
  }

  Future<void> renameRecordingFile(RecordingItem item, String newBaseName) async {
    final sanitized = _sanitizeFileBaseName(newBaseName);
    if (sanitized.isEmpty) {
      return;
    }
    final file = File(item.path);
    if (!await file.exists()) {
      return;
    }
    final extMatch = RegExp(r'\.([^.]+)$').firstMatch(file.path);
    final ext = extMatch != null ? extMatch.group(1) : null;
    if (ext == null) {
      return;
    }
    final dir = file.parent.path;
    var candidate = '$dir/$sanitized.$ext';
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate = '$dir/${sanitized}_$counter.$ext';
      counter++;
    }
    final renamedFile = await file.rename(candidate);
    try {
      final oldMeta = await _metadataFileForRecording(file);
      final newMeta = await _metadataFileForRecording(renamedFile);
      if (await oldMeta.exists()) {
        await oldMeta.rename(newMeta.path);
      }
    } catch (_) {
      // Ignore metadata rename errors.
    }
    await _saveRecordingMetadata(
      renamedFile,
      stationName: item.stationName,
      mode: item.mode,
      createdAt: item.createdAt,
      durationSeconds: item.durationSeconds,
      displayName: sanitized,
    );
    if (_favoriteRecordingPaths.remove(item.path)) {
      _favoriteRecordingPaths.add(renamedFile.path);
    }
    await _persistFavoriteRecordings();
    final updated = RecordingItem.fromFile(
      renamedFile,
      stationName: item.stationName,
      mode: item.mode,
      durationSeconds: item.durationSeconds,
      displayName: sanitized,
    );
    _replaceRecording(item.path, updated);
  }

  void _replaceRecording(String oldPath, RecordingItem updated) {
    final index = recordings.indexWhere((recording) => recording.path == oldPath);
    if (index == -1) {
      return;
    }
    recordings[index] = updated;
    _reconcileVisibleRecordings();
    notifyListeners();
  }

  String _sanitizeFileBaseName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceAll(RegExp(r'[\\/]+'), '-');
  }

  void setShouldResumePlayback(bool value) {
    _shouldResumePlayback = value;
  }

  bool get shouldResumePlayback => _shouldResumePlayback;

  RecordingMode? get activeMode => _activeMode;

  DateTime? get recordingStartedAt => _recordingStartedAt;

  DateTime? get voiceRecordingStartedAt => _voiceRecordingStartedAt;

  void toggleRecordingsList() {
    showRecordingsList = !showRecordingsList;
    notifyListeners();
  }

  void setShowRecordingsList(bool value) {
    if (showRecordingsList == value) return;
    showRecordingsList = value;
    notifyListeners();
  }

  String? _extensionFromContentType(String contentType) {
    if (contentType.contains('aac') || contentType.contains('aacp') || contentType.contains('adts')) {
      return 'aac';
    }
    if (contentType.contains('ogg')) {
      return 'ogg';
    }
    if (contentType.contains('flac')) {
      return 'flac';
    }
    if (contentType.contains('wav')) {
      return 'wav';
    }
    if (contentType.contains('mpeg') || contentType.contains('mp3')) {
      return 'mp3';
    }
    return null;
  }

  String? _extensionFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.mp3')) return 'mp3';
    if (lower.contains('.aac')) return 'aac';
    if (lower.contains('.m4a')) return 'm4a';
    if (lower.contains('.ogg')) return 'ogg';
    if (lower.contains('.flac')) return 'flac';
    if (lower.contains('.wav')) return 'wav';
    return null;
  }

  @override
  void dispose() {
    _recordingDurationTimer?.cancel();
    _recordingFlushTimer?.cancel();
    _subscription?.cancel();
    _fileSink?.close();
    _client?.close();
    _voiceRecorder?.dispose();
    super.dispose();
  }
}
