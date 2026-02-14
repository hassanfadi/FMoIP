import '../../models.dart';

/// Interval for data usage calculation and UI updates (estimation & proxy).
/// Shared by EstimatedDataUsageStrategy and AppPlayerState.
const Duration kDataUsageUpdateInterval = Duration(seconds: 3);

/// Callback invoked when bytes are added to the session total.
typedef DataUsageUpdateCallback = void Function(int delta);

/// Strategy for tracking data usage during stream playback.
/// Implements Strategy pattern: proxy counts actual bytes, estimation uses bitrate.
abstract class DataUsageTrackingStrategy {
  DataUsageTrackingStrategy(this.onBytesAdded);
  final DataUsageUpdateCallback onBytesAdded;

  /// Start tracking. [station] supplies bitrate for estimation mode.
  void start(RadioStation? station);

  /// Stop tracking (cancel timers, release resources).
  void stop();

  /// Add bytes (called by proxy when data received). No-op for estimation.
  void addBytes(int bytes);
}
