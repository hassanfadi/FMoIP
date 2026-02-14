import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Optional tee callbacks for recording from the same stream (avoids double fetch).
typedef OnStreamHeaders = void Function(Map<String, String> headers);
typedef OnStreamChunk = void Function(List<int> chunk);

/// Proxies an HTTP(S) stream and counts bytes for data usage tracking.
/// Runs a local server that fetches from the target URL and forwards to the client.
/// Used on mobile/desktop where dart:io is available.
/// When [onStreamHeaders] and [onStreamChunk] are set, chunks are teed to them
/// (single fetch for playback + recording).
class StreamProxy {
  HttpServer? _server;
  final void Function(int bytes) onBytesReceived;
  final OnStreamHeaders? onStreamHeaders;
  final OnStreamChunk? onStreamChunk;
  int _port = 0;

  StreamProxy({
    required this.onBytesReceived,
    this.onStreamHeaders,
    this.onStreamChunk,
  });

  /// The URL the audio player should use to play the stream.
  /// Returns null if the server is not running.
  String? get proxyUrl =>
      _server != null ? 'http://127.0.0.1:$_port/' : null;

  /// Starts the proxy server. Call [stop] when done.
  Future<void> start(String targetUrl) async {
    await stop();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;

    _server!.listen((request) async {
      if (request.method != 'GET' && request.method != 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }
      try {
        final client = HttpClient();
        client.userAgent = 'FMoIP/1.0';
        final req = await client.getUrl(Uri.parse(targetUrl));
        req.followRedirects = true;
        req.maxRedirects = 5;
        // Forward Range header if present (for seeking)
        final range = request.headers[HttpHeaders.rangeHeader];
        if (range != null && range.isNotEmpty) {
          req.headers.set(HttpHeaders.rangeHeader, range.first);
        }
        final response = await req.close();

        request.response.statusCode = response.statusCode;
        request.response.reasonPhrase = response.reasonPhrase;
        response.headers.forEach((name, values) {
          if (_shouldForwardHeader(name)) {
            for (final v in values) {
              request.response.headers.add(name, v);
            }
          }
        });

        if (request.method == 'GET' && response.statusCode == 200) {
          if (onStreamHeaders != null) {
            final headerMap = <String, String>{};
            response.headers.forEach((name, values) {
              if (values.isNotEmpty) {
                headerMap[name.toLowerCase()] = values.first.trim();
              }
            });
            onStreamHeaders!(headerMap);
          }
          await for (final chunk in response) {
            onBytesReceived(chunk.length);
            request.response.add(chunk);
            onStreamChunk?.call(chunk);
          }
        }
        await request.response.close();
        client.close();
      } catch (e) {
        debugPrint('Stream proxy error: $e');
        try {
          request.response.statusCode = HttpStatus.badGateway;
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  bool _shouldForwardHeader(String name) {
    final lower = name.toLowerCase();
    return lower != 'transfer-encoding' && // We handle streaming ourselves
        lower != 'connection' &&
        lower != 'keep-alive';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }
}
