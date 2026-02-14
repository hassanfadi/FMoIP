import '../../models.dart';
import 'data_usage_strategy.dart';

/// Strategy that counts actual bytes from the stream proxy.
/// Uses real byte counts for accurate data usage.
class ProxyDataUsageStrategy extends DataUsageTrackingStrategy {
  ProxyDataUsageStrategy(super.onBytesAdded);

  @override
  void start(RadioStation? station) {
    // Nothing to do - proxy feeds bytes via addBytes
  }

  @override
  void stop() {
    // Nothing to do - no timers
  }

  @override
  void addBytes(int bytes) {
    if (bytes > 0) {
      onBytesAdded(bytes);
    }
  }
}
