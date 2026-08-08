import 'package:web_socket_channel/web_socket_channel.dart';

import 'fan_browser_socket_stub.dart'
    if (dart.library.io) 'fan_browser_socket_io.dart'
    as browser;
import 'fan_socket_connection.dart';

bool get fanBrowserSocketSupported => browser.fanBrowserSocketSupported;

Future<FanSocketConnection> createFanSocket(
  Uri uri, {
  bool forceNative = false,
}) async {
  if (!forceNative &&
      browser.fanBrowserSocketSupported &&
      await browser.shouldUseFanBrowserSocket(uri)) {
    return browser.createFanBrowserSocket(uri);
  }
  return _NativeFanSocket(uri);
}

class _NativeFanSocket implements FanSocketConnection {
  _NativeFanSocket(Uri uri) : _channel = WebSocketChannel.connect(uri);

  final WebSocketChannel _channel;

  @override
  String get transportName => 'Dart';

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<Object?> get stream => _channel.stream;

  @override
  Future<void> send(String message) async {
    _channel.sink.add(message);
  }

  @override
  Future<void> close() => _channel.sink.close();
}
