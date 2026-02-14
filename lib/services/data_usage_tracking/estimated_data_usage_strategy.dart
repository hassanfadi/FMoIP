import 'dart:async';

import '../../models.dart';
import 'data_usage_strategy.dart';

/// Strategy that estimates data usage from bitrate and elapsed time.
/// Used when proxy is unavailable (web) or station does not support proxy.
class EstimatedDataUsageStrategy extends DataUsageTrackingStrategy {
  EstimatedDataUsageStrategy(super.onBytesAdded);

  static const int _defaultBitrateKbps = 128;
  /// Bytes per second per kbps: 1 kbps = 1000 bits/sec ÷ 8 = 125 bytes/sec
  static const int _bytesPerSecPerKbps = 125;
  Timer? _estimateTimer;
  DateTime? _lastEstimateTime;

  static int _bitrateKbps(RadioStation? station) =>
      station?.bitrateKbps ?? _defaultBitrateKbps;

  @override
  void start(RadioStation? station) {
    stop();
    final kbps = _bitrateKbps(station);
    _lastEstimateTime = DateTime.now();
    _estimateTimer = Timer.periodic(kDataUsageUpdateInterval, (_) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastEstimateTime!).inSeconds;
      _lastEstimateTime = now;
      final bytes = (kbps * _bytesPerSecPerKbps * elapsed.clamp(1, 3600)).toInt();
      if (bytes > 0) {
        onBytesAdded(bytes);
      }
    });
  }

  @override
  void stop() {
    _estimateTimer?.cancel();
    _estimateTimer = null;
    _lastEstimateTime = null;
  }

  @override
  void addBytes(int bytes) {
    // No-op: estimation uses timer, not proxy callback
  }
}
