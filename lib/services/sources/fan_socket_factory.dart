import 'package:web_socket_channel/web_socket_channel.dart';

import 'source_socket.dart';
import 'fan_socket_connection.dart';

Future<FanSocketConnection> createFanSocket(
  Uri uri,
) async => _NativeFanSocket(uri);

class _NativeFanSocket implements FanSocketConnection, FanSocketCloseDetails {
  _NativeFanSocket(Uri uri) : _channel = connectSourceSocket(uri);

  final WebSocketChannel _channel;

  @override
  String get transportName => _channel.runtimeType.toString();

  @override
  int? get closeCode => _channel.closeCode;

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
