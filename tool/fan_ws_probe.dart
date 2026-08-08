import 'dart:async';
import 'dart:io';

const _defaultUrls = <String>[
  'wss://ws.fanstudio.tech/all',
  'wss://ws.fanstudio.hk/all',
];

Future<void> main(List<String> args) async {
  final urls = args.isEmpty ? _defaultUrls : args;
  for (final url in urls) {
    await _probe(url);
  }
}

Future<void> _probe(String url) async {
  final uri = Uri.parse(url);
  stdout.writeln('FAN probe: $url');

  try {
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 10));
    stdout.writeln(
      'DNS: ${addresses.map((address) => address.address).join(', ')}',
    );
  } catch (error) {
    stdout.writeln('DNS failed: $error');
    return;
  }

  WebSocket? socket;
  try {
    socket = await WebSocket.connect(url).timeout(const Duration(seconds: 10));
    stdout.writeln('WebSocket open');
    socket.add('query');
    final message = await socket.first.timeout(const Duration(seconds: 10));
    final text = message.toString();
    stdout.writeln(
      'First message: ${text.substring(0, text.length.clamp(0, 300))}',
    );
  } catch (error, stackTrace) {
    stdout.writeln('WebSocket failed: ${error.runtimeType}: $error');
    stdout.writeln(stackTrace.toString().split('\n').take(6).join('\n'));
  } finally {
    await socket?.close();
    stdout.writeln('');
  }
}
