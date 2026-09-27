import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> connectWolfxSocket(String url) async {
  final client = HttpClient()
    ..badCertificateCallback = ((cert, host, port) => true)
    ..connectionTimeout = const Duration(seconds: 8);
  final socket = await WebSocket.connect(
    url,
    customClient: client,
  ).timeout(const Duration(seconds: 10));
  return IOWebSocketChannel(socket);
}
