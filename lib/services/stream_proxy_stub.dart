/// Optional tee callbacks (stub: no-op; real proxy on io platforms).
typedef OnStreamHeaders = void Function(Map<String, String> headers);
typedef OnStreamChunk = void Function(List<int> chunk);

/// Stub for StreamProxy on web where dart:io is unavailable.
/// Returns the target URL directly (no proxy); byte counting is not supported.
/// Recording tee is not supported (no local proxy).
class StreamProxy {
  final void Function(int bytes) onBytesReceived;
  String? _targetUrl;

  StreamProxy({
    required this.onBytesReceived,
    void Function(Map<String, String> headers)? onStreamHeaders,
    void Function(List<int> chunk)? onStreamChunk,
  });

  /// On web, returns the target URL directly since we can't run a local proxy.
  String? get proxyUrl => _targetUrl;

  Future<void> start(String targetUrl) async {
    await stop();
    _targetUrl = targetUrl;
  }

  Future<void> stop() async {
    _targetUrl = null;
  }
}
