import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models.dart';
import '../services/data_usage_tracking/data_usage_tracking.dart';
import '../services/stream_proxy.dart';

/// How session data usage is tracked.
enum DataUsageSource {
  /// Actual bytes counted by the stream proxy.
  proxy,
  /// Estimated from bitrate when proxy is unavailable (web, or station unsupported).
  estimated,
}

class AppPlayerState extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  RadioStation? currentStation;
  String? currentRecordingPath;
  bool isPlaying = false;
  bool isLoading = false;
  String? errorMessage;
  double volume = 1.0;

  /// Bytes consumed this session (actual via proxy or estimated from bitrate).
  int _sessionBytes = 0;
  StreamProxy? _streamProxy;
  DataUsageTrackingStrategy? _dataUsageStrategy;
  /// Station we're tracking data for; ignore bytes if currentStation changed (switched).
  RadioStation? _trackingForStation;
  Timer? _dataUsageNotifyTimer;
  Timer? _proxyFallbackTimer;
  int _proxyBytesSinceStart = 0;
  static const Duration _dataUsageNotifyInterval = kDataUsageUpdateInterval;
  static const Duration _proxyFallbackDelay = Duration(seconds: 5);

  int get sessionBytes => _sessionBytes;

  /// Add bytes from an external source (e.g. recording stream). Use when streaming
  /// happens outside the player (RecordingState) so data usage stays accurate.
  void addSessionBytes(int bytes) {
    if (bytes <= 0) return;
    _sessionBytes += bytes;
    notifyListeners();
  }

  /// Session data usage in MB (for LCD display).
  double get sessionDataMb => _sessionBytes / (1024 * 1024);

  DataUsageSource? get dataUsageSource =>
      _dataUsageStrategy is ProxyDataUsageStrategy
          ? DataUsageSource.proxy
          : _dataUsageStrategy is EstimatedDataUsageStrategy
              ? DataUsageSource.estimated
              : null;

  void _onBytesReceived(int bytes) {
    _proxyBytesSinceStart += bytes;
    _dataUsageStrategy?.addBytes(bytes);
  }

  void _onBytesAdded(int delta) {
    if (currentStation != _trackingForStation) return;
    _sessionBytes += delta;
    notifyListeners();
  }

  void _createStrategies() {
    _dataUsageStrategy = ProxyDataUsageStrategy(_onBytesAdded);
  }

  void _switchToEstimation(RadioStation station) {
    _dataUsageStrategy?.stop();
    _proxyFallbackTimer?.cancel();
    _proxyFallbackTimer = null;
    _trackingForStation = station;
    _dataUsageStrategy = EstimatedDataUsageStrategy(_onBytesAdded);
    _dataUsageStrategy!.start(station);
    debugPrint('Data usage: switched to estimation (proxy unsupported)');
  }

  void Function()? _pendingProxyFallback;

  Future<void> _fallbackToDirectPlayback(RadioStation station) async {
    if (currentStation != station) return;
    debugPrint('Proxy received 0 bytes after ${_proxyFallbackDelay.inSeconds}s, falling back to direct');
    _pendingProxyFallback?.call();
    _pendingProxyFallback = null;
    await _streamProxy?.stop();
    _streamProxy = null;
    _switchToEstimation(station);
    try {
      await _player.stop();
      await _playDirect(station);
      notifyListeners();
    } catch (e) {
      debugPrint('Fallback to direct playback failed: $e');
      _stopDataUsageTracking();
      errorMessage = 'Unable to play this station. $e';
      isPlaying = false;
      notifyListeners();
    }
  }

  /// Start data usage tracking with the current strategy.
  void _startDataUsageTracking(DataUsageSource source, {RadioStation? station}) {
    _stopDataUsageTracking();
    _trackingForStation = station;
    if (source == DataUsageSource.estimated && station != null) {
      _dataUsageStrategy = EstimatedDataUsageStrategy(_onBytesAdded);
      _dataUsageStrategy!.start(station);
    } else {
      _dataUsageStrategy = ProxyDataUsageStrategy(_onBytesAdded);
      _dataUsageStrategy!.start(station);
    }
    _dataUsageNotifyTimer = Timer.periodic(_dataUsageNotifyInterval, (_) {
      notifyListeners();
    });
    notifyListeners();
  }

  void _stopDataUsageTracking() {
    _dataUsageNotifyTimer?.cancel();
    _dataUsageNotifyTimer = null;
    _proxyFallbackTimer?.cancel();
    _proxyFallbackTimer = null;
    _dataUsageStrategy?.stop();
    _dataUsageStrategy = null;
    _trackingForStation = null;
  }

  Future<void> _stopStreamProxy() async {
    _stopDataUsageTracking();
    _pendingProxyFallback = null;
    await _streamProxy?.stop();
    _streamProxy = null;
  }

  AppPlayerState() {
    Future.microtask(() => _player.setLoopMode(LoopMode.off));
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        isPlaying = false;
        currentRecordingPath = null;
        _stopStreamProxy();
        _player.stop();
      } else if (state.processingState == ProcessingState.idle &&
          currentStation != null &&
          _dataUsageStrategy != null) {
        _stopDataUsageTracking();
      }
      isPlaying = state.playing;
      notifyListeners();
    });
    volume = _player.volume;
  }

  /// Play through proxy (optimized: actual byte count). Falls back to direct+estimation
  /// if proxy receives no bytes after [._proxyFallbackDelay] (station unsupported).
  /// When [recordOnHeaders] and [recordOnChunk] are set, stream is teed to them (single fetch).
  /// [onProxyFallback] is called when we fallback (tee stream ends).
  Future<void> _playWithProxy(
    RadioStation station, {
    OnStreamHeaders? recordOnHeaders,
    OnStreamChunk? recordOnChunk,
    void Function()? onProxyFallback,
  }) async {
    _createStrategies();
    _trackingForStation = station;
    _proxyBytesSinceStart = 0;
    _dataUsageStrategy!.start(station);

    _pendingProxyFallback = onProxyFallback;
    _streamProxy = StreamProxy(
      onBytesReceived: _onBytesReceived,
      onStreamHeaders: recordOnHeaders,
      onStreamChunk: recordOnChunk,
    );
    await _streamProxy!.start(station.streamUrl);
    final proxyUrl = _streamProxy!.proxyUrl;
    if (proxyUrl == null || proxyUrl.isEmpty) {
      _switchToEstimation(station);
      await _playDirect(station);
      return;
    }

    _dataUsageNotifyTimer = Timer.periodic(_dataUsageNotifyInterval, (_) {
      notifyListeners();
    });

    _proxyFallbackTimer = Timer(_proxyFallbackDelay, () {
      if (_proxyBytesSinceStart == 0 && _dataUsageStrategy is ProxyDataUsageStrategy) {
        _fallbackToDirectPlayback(station);
      }
    });

    final source = AudioSource.uri(
      Uri.parse(proxyUrl),
      tag: MediaItem(
        id: station.streamUrl,
        album: station.country,
        title: station.name,
        artist: station.frequency,
      ),
    );
    await _player.setAudioSource(source);
    await _player.play();
    errorMessage = null;
  }

  Future<void> _playDirect(RadioStation station) async {
    final source = AudioSource.uri(
      Uri.parse(station.streamUrl),
      tag: MediaItem(
        id: station.streamUrl,
        album: station.country,
        title: station.name,
        artist: station.frequency,
      ),
    );
    await _player.setAudioSource(source);
    await _player.play();
    errorMessage = null;
  }

  /// Play direct with estimation (used on web or as fallback).
  Future<void> _playDirectWithEstimation(RadioStation station) async {
    _startDataUsageTracking(DataUsageSource.estimated, station: station);
    await _playDirect(station);
  }

  /// Plays [station]. Optionally tees stream to [recordOnHeaders]/[recordOnChunk]
  /// for recording (single fetch instead of double).
  /// When proxy fails and we fallback to direct, [onProxyFallback] is called
  /// (e.g. to stop recording since the tee stream ended).
  Future<void> play(
    RadioStation station, {
    OnStreamHeaders? recordOnHeaders,
    OnStreamChunk? recordOnChunk,
    void Function()? onProxyFallback,
  }) async {
    currentStation = station;
    currentRecordingPath = null;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    try {
      await _stopStreamProxy();
      await _player.stop();

      if (kIsWeb) {
        await _playDirectWithEstimation(station);
        debugPrint('Playing: ${station.name} (estimation - web)');
      } else {
        await _playWithProxy(
          station,
          recordOnHeaders: recordOnHeaders,
          recordOnChunk: recordOnChunk,
          onProxyFallback: onProxyFallback,
        );
        final src = dataUsageSource == DataUsageSource.proxy ? 'proxy' : 'estimation';
        debugPrint('Playing: ${station.name} ($src)');
      }
    } catch (error, stack) {
      if (_dataUsageStrategy is ProxyDataUsageStrategy && currentStation == station) {
        _pendingProxyFallback?.call();
        _pendingProxyFallback = null;
        await _streamProxy?.stop();
        _streamProxy = null;
        _switchToEstimation(station);
        try {
          await _playDirect(station);
          debugPrint('Playing: ${station.name} (estimation - proxy failed, retried direct)');
        } catch (retryError, retryStack) {
          errorMessage = 'Unable to play this station. ${retryError.toString()}';
          _stopDataUsageTracking();
          debugPrint('Playback error (after retry): $retryError');
          debugPrint(retryStack.toString());
        }
      } else {
        errorMessage = 'Unable to play this station. ${error.toString()}';
        _stopDataUsageTracking();
        debugPrint('Playback error: $error');
        debugPrint(stack.toString());
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _stopStreamProxy();
    notifyListeners();
    if (currentStation != null) {
      await _player.stop();
    } else {
      await _player.pause();
    }
    isPlaying = false;
    notifyListeners();
  }

  Future<void> resume() async {
    if (currentRecordingPath != null || currentStation != null) {
      await _player.play();
    }
  }

  Future<void> stop() async {
    await _stopStreamProxy();
    notifyListeners();
    await _player.stop();
    isPlaying = false;
    currentRecordingPath = null;
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    volume = value;
    await _player.setVolume(value);
    notifyListeners();
  }

  Future<void> seekRelative(Duration offset) async {
    final position = _player.position;
    final duration = _player.duration;
    if (duration == null) return;
    final next = position + offset;
    final clamped = next < Duration.zero
        ? Duration.zero
        : (next > duration ? duration : next);
    await _player.seek(clamped);
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  Future<void> playRecording(String path) async {
    currentStation = null;
    currentRecordingPath = path;
    errorMessage = null;
    isLoading = true;
    notifyListeners();
    try {
      await _player.stop();
      await _stopStreamProxy();
      final source = AudioSource.uri(
        Uri.file(path),
        tag: MediaItem(
          id: path,
          album: 'Recordings',
          title: path.split('/').last,
          artist: 'FMoIP',
        ),
      );
      await _player.setAudioSource(source);
      await _player.play();
    } catch (error) {
      errorMessage = 'Unable to play this recording. ${error.toString()}';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopDataUsageTracking();
    _stopStreamProxy();
    _player.dispose();
    super.dispose();
  }
}
