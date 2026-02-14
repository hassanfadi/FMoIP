// Conditional export: use real proxy on platforms with dart:io, stub on web.
export 'stream_proxy_stub.dart' if (dart.library.io) 'stream_proxy_io.dart';
