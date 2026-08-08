import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  const listUrl =
      'https://api-cencint-public.nowquake.cn/list?pageNo=0&pageSize=3';
  const socketUrl = 'wss://api-cencint-public.nowquake.cn/websocket';

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(listUrl));
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder.bind(response).join();
    stdout.writeln('HTTP ${response.statusCode}: ${_prefix(body)}');
  } catch (error) {
    stdout.writeln('HTTP failed: ${error.runtimeType}: $error');
  } finally {
    client.close(force: true);
  }

  WebSocket? socket;
  try {
    socket = await WebSocket.connect(
      socketUrl,
    ).timeout(const Duration(seconds: 10));
    final message = await socket.first.timeout(const Duration(seconds: 10));
    stdout.writeln('WebSocket: ${_prefix(message.toString())}');
  } catch (error) {
    stdout.writeln('WebSocket failed: ${error.runtimeType}: $error');
  } finally {
    await socket?.close();
  }
}

String _prefix(String value) {
  return value.substring(0, value.length.clamp(0, 300));
}
