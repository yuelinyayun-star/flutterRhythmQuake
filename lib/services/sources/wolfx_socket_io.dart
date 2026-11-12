import '../debug/network_diagnostic.dart';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'native_station_core_library_io.dart';
import 'source_socket.dart';

Future<WebSocketChannel> connectWolfxSocket(String url) async {
  if (StationCoreLibrary.supported &&
      !NetworkDiagnostic.hasTransportOverrides) {
    final channel = connectSourceSocket(
      Uri.parse(url),
      connectTimeout: const Duration(seconds: 10),
      allowBadCertificate: true,
      textAsBytes: false,
    );
    await channel.ready;
    return channel;
  }
  final client = HttpClient()
    ..badCertificateCallback = ((cert, host, port) => true)
    ..connectionTimeout = const Duration(seconds: 8);
  final socket = await WebSocket.connect(
    url,
    customClient: client,
  ).timeout(const Duration(seconds: 10));
  return IOWebSocketChannel(socket);
}
