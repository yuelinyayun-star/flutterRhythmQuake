import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';

// Deliberately silent control-protocol peer. It acknowledges HTTP upgrade and
// close frames, but never replies to protocol ping. No earthquake data used.
Future<Map<String, Object?>> verify(bool native) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final peers = <Socket>[];
  final controls = <Map<String, Object?>>[];
  final watch = Stopwatch()..start();
  final requests = server.listen((request) async {
    final key = request.headers.value('sec-websocket-key')!;
    final socket = await request.response.detachSocket(writeHeaders: false);
    peers.add(socket);
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: ${WebSocketChannel.signKey(key)}\r\n\r\n',
    );
    final pending = <int>[];
    socket.listen((bytes) {
      pending.addAll(bytes);
      while (pending.length >= 2) {
        final masked = pending[1] & 128 != 0;
        final length = pending[1] & 127;
        if (length >= 126) throw StateError('Expected control frames only');
        final prefix = masked ? 6 : 2;
        if (pending.length < prefix + length) return;
        final opcode = pending[0] & 15;
        final payload = [
          for (var i = 0; i < length; i++)
            pending[prefix + i] ^ (masked ? pending[2 + i % 4] : 0),
        ];
        pending.removeRange(0, prefix + length);
        controls.add({
          'opcode': opcode,
          'elapsedMs': watch.elapsedMilliseconds,
        });
        if (opcode == 8) {
          socket.add([0x88, payload.length, ...payload]);
        }
      }
    }, onError: (Object _) {});
  });
  final uri = Uri.parse('ws://127.0.0.1:${server.port}/');
  final WebSocketChannel channel = native
      ? NativeWebSocketChannel.connect(
          uri,
          keepaliveInterval: const Duration(seconds: 15),
        )
      : IOWebSocketChannel.connect(
          uri,
          pingInterval: const Duration(seconds: 15),
        );
  final done = Completer<void>();
  final errors = <String>[];
  final sub = channel.stream.listen(
    (_) {},
    onError: (Object e) {
      errors.add(e.toString());
    },
    onDone: done.complete,
  );
  await channel.ready;
  var timedOut = false;
  await done.future.timeout(
    const Duration(seconds: 48),
    onTimeout: () {
      timedOut = true;
    },
  );
  final elapsedMs = watch.elapsedMilliseconds;
  await channel.sink.close().timeout(
    const Duration(seconds: 3),
    onTimeout: () {},
  );
  await sub.cancel();
  for (final peer in peers) {
    peer.destroy();
  }
  await requests.cancel();
  await server.close(force: true);
  return {
    'native': native,
    'closedWithoutPong': !timedOut,
    'elapsedMs': elapsedMs,
    'controls': controls,
    'errors': errors,
  };
}

Future<void> main() async {
  stdout.writeln(jsonEncode(await Future.wait([verify(false), verify(true)])));
}
