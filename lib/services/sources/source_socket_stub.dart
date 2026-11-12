import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectSourceSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration? pingInterval,
  bool allowBadCertificate = false,
  bool textAsBytes = true,
}) => WebSocketChannel.connect(uri);
