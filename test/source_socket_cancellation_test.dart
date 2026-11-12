import 'package:flutterrhythmquake/services/whews_authorization_policy.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/source_socket.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';

Future<void> until(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (DateTime.now().isAfter(end))
      throw TimeoutException('loopback timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUp(() => WhewsAuthorizationPolicy.storeOverride = MemoryConnectionRetryStore());
  setUp(() => HttpOverrides.global = null);
  for (final status in [401, 403, 404, 429]) {
    test(
      'HTTP $status stops WHEWS retries without an unauthenticated upgrade',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Uri>[];
        final listener = server.listen((request) async {
          requests.add(request.uri);
          request.response.statusCode = status;
          await request.response.close();
        });
        final client = WhewsSocketClient(
          url: 'ws://127.0.0.1:${server.port}/ws/all',
          apiToken: 'wat_controlled',
          onMessage: (_) {},
        );
        try {
          client.start();
          await until(() => client.authorizationRejected);
          await Future<void>.delayed(const Duration(milliseconds: 150));
          client.reconnect();
          expect(requests, hasLength(1));
          expect(requests.single.queryParameters['token'], 'wat_controlled');
        } finally {
          client.dispose();
          await listener.cancel();
          await server.close(force: true);
        }
      },
    );
  }
  for (final cancel in [false, true]) {
    test(
      'pending HTTP handshake is aborted by ${cancel ? 'explicit cancellation' : 'timeout'}',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final peers = <Socket>[];
        var received = false, closed = false;
        final sub = server.listen((peer) {
          peers.add(peer);
          peer.listen(
            (_) {
              received = true;
            },
            onDone: () {
              closed = true;
            },
            onError: (Object _) {
              closed = true;
            },
          );
        });
        final channel = connectSourceSocket(
          Uri.parse('ws://127.0.0.1:${server.port}/slow'),
          connectTimeout: const Duration(milliseconds: 250),
        );
        final errors = <Object>[];
        final stream = channel.stream.listen((_) {}, onError: errors.add);
        final ready = expectLater(channel.ready, throwsA(anything));
        try {
          await until(() => received);
          if (cancel) await channel.sink.close();
          await ready;
          await until(() => closed);
          if (!cancel) expect(errors, isNotEmpty);
        } finally {
          await channel.sink.close();
          await stream.cancel();
          for (final peer in peers) {
            peer.destroy();
          }
          await sub.cancel();
          await server.close();
        }
      },
    );
  }
  test(
    'protocol ping without a pong closes the connection, rather than WinHTTP keepalive',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      final ping = Completer<void>();
      final sub = server.listen((peer) {
        peers.add(peer);
        var upgraded = false;
        final headers = <int>[];
        peer.listen((bytes) {
          if (!upgraded) {
            headers.addAll(bytes);
            final text = utf8.decode(headers);
            if (!text.contains('\r\n\r\n')) return;
            final key = RegExp(
              r'Sec-WebSocket-Key:\s*(.+)\r\n',
              caseSensitive: false,
            ).firstMatch(text)!.group(1)!.trim();
            final accept = base64.encode(
              sha1
                  .convert(
                    utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
                  )
                  .bytes,
            );
            peer.write(
              'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: $accept\r\n\r\n',
            );
            upgraded = true;
          } else if (bytes.isNotEmpty &&
              bytes[0] & 15 == 9 &&
              !ping.isCompleted) {
            ping.complete();
          }
        }, onError: (Object _) {});
      });
      final channel = connectSourceSocket(
        Uri.parse('ws://127.0.0.1:${server.port}/ping'),
        pingInterval: const Duration(milliseconds: 100),
      );
      final done = channel.stream.drain<void>();
      try {
        await channel.ready;
        await ping.future.timeout(const Duration(seconds: 2));
        await done.timeout(const Duration(seconds: 3));
        expect(channel.closeCode, WebSocketStatus.goingAway);
      } finally {
        await channel.sink.close();
        for (final peer in peers) {
          peer.destroy();
        }
        await sub.cancel();
        await server.close();
      }
    },
  );
}
