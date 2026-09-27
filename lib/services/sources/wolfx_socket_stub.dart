import 'package:web_socket_channel/web_socket_channel.dart';

Future<WebSocketChannel> connectWolfxSocket(String url) async {
  final channel = WebSocketChannel.connect(Uri.parse(url));
  await channel.ready.timeout(const Duration(seconds: 10));
  return channel;
}
