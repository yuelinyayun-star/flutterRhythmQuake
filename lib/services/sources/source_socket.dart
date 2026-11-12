import 'package:web_socket_channel/web_socket_channel.dart';
import 'source_socket_stub.dart'
    if (dart.library.io) 'source_socket_io.dart'
    as platform;

/// Source policies (authentication, subscription, retry and event admission)
/// remain with their source service. Windows uses Rust/WinHTTP except sources
/// requiring actual protocol ping/pong deadlines (WinHTTP keepalive is pong).
WebSocketChannel connectSourceSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration? pingInterval,
  bool allowBadCertificate = false,
  bool textAsBytes = true,
}) => platform.connectSourceSocket(
  uri,
  headers: headers,
  connectTimeout: connectTimeout,
  pingInterval: pingInterval,
  allowBadCertificate: allowBadCertificate,
  textAsBytes: textAsBytes,
);
