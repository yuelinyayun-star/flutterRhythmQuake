import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_tcp_socket.dart';
import 'package:flutterrhythmquake/services/sources/source_tcp_socket.dart';

// Controlled loopback transport/proxy tests. Captured binary inputs are sent
// unchanged. Repetition is a transport pressure load, not new observations.
void main() {
  final native =
      Platform.isWindows &&
      Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY');
  final raw = File(
    'test/fixtures/global_quake/stream_20260921.bin',
  ).readAsBytesSync();
  tearDown(() async {
    if (native) {
      await until(
        () =>
            NativeTcpSocket.activeSessions == 0 &&
            NativeTcpSocket.activeSockets == 0,
      );
    }
  });

  test(
    'source factory sends and receives unchanged bytes; flush preserves order',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      final received = <int>[];
      final requests = server.listen((peer) {
        peers.add(peer);
        peer.listen((bytes) {
          received.addAll(bytes);
          peer.add(bytes);
        }, onError: (_) {});
      });
      final socket = await connectSourceTcpSocket('localhost', server.port);
      final echoed = <int>[];
      final got = Completer<void>();
      final sub = socket.listen((bytes) {
        echoed.addAll(bytes);
        if (echoed.length == raw.length && !got.isCompleted) got.complete();
      });
      try {
        expect(
          socket,
          native ? isA<NativeTcpSocket>() : isA<DartSourceTcpSocket>(),
        );
        for (var i = 0; i < raw.length; i += 7) {
          socket.add(
            Uint8List.sublistView(raw, i, (i + 7).clamp(0, raw.length)),
          );
        }
        await socket.flush().timeout(const Duration(seconds: 5));
        await got.future.timeout(const Duration(seconds: 5));
        expect(received, raw);
        expect(echoed, raw);
      } finally {
        socket.destroy();
        await sub.cancel();
        for (final peer in peers) {
          peer.destroy();
        }
        await requests.cancel();
        await server.close();
      }
    },
  );

  group('actual native TCP', () {
    test(
      'owned frame views survive later reads and connection release',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final peers = <Socket>[];
        final requests = server.listen((peer) {
          peers.add(peer);
          peer.listen(peer.add, onError: (_) {});
        });
        final socket = await connectSourceTcpSocket('127.0.0.1', server.port);
        final views = <Uint8List>[];
        var bytes = 0;
        final got = Completer<void>();
        final sub = socket.listen((chunk) {
          // Retain a view, not the original list object. Its buffer must keep the
          // external allocation alive even after the connection owner is freed.
          views.add(Uint8List.sublistView(chunk));
          bytes += chunk.length;
          if (bytes == raw.length * 100 && !got.isCompleted) got.complete();
        });
        try {
          for (var i = 0; i < 100; i++) {
            socket.add(raw);
          }
          await got.future.timeout(const Duration(seconds: 5));
          socket.destroy();
          await sub.cancel();
          await until(
            () =>
                NativeTcpSocket.activeSessions == 0 &&
                NativeTcpSocket.activeSockets == 0,
          );
          expect(
            [for (final view in views) ...view],
            [for (var i = 0; i < 100; i++) ...raw],
          );
        } finally {
          socket.destroy();
          await sub.cancel();
          for (final peer in peers) {
            peer.destroy();
          }
          await requests.cancel();
          await server.close();
        }
      },
    );
    test(
      '100 concurrent sockets share one reactor and retain byte ownership',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final peers = <Socket>[];
        final requests = server.listen((peer) {
          peers.add(peer);
          peer.listen(peer.add, onError: (_) {});
        });
        final sockets = <SourceTcpSocket>[];
        final subs = <StreamSubscription<Uint8List>>[];
        try {
          sockets.addAll(
            await Future.wait(
              List.generate(
                100,
                (_) => connectSourceTcpSocket('127.0.0.1', server.port),
              ),
            ),
          );
          expect(NativeTcpSocket.activeSockets, 100);
          expect(NativeTcpSocket.reactorThreads, 1);
          final results = <Future<void>>[];
          for (var i = 0; i < sockets.length; i++) {
            final expected = raw.sublist(i, raw.length - i);
            final received = <int>[];
            final done = Completer<void>();
            subs.add(
              sockets[i].listen((bytes) {
                received.addAll(bytes);
                if (received.length == expected.length && !done.isCompleted) {
                  expect(received, expected);
                  done.complete();
                }
              }),
            );
            sockets[i].add(expected);
            results.add(done.future);
          }
          await Future.wait(results).timeout(const Duration(seconds: 10));
        } finally {
          for (final socket in sockets) {
            socket.destroy();
          }
          await Future.wait(subs.map((sub) => sub.cancel()));
          for (final peer in peers) {
            peer.destroy();
          }
          await requests.cancel();
          await server.close();
        }
      },
    );

    test(
      'fragmented proxy header and coalesced original body retain every byte',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final peers = <Socket>[];
        final lines = <String>[];
        final requests = server.listen((peer) {
          peers.add(peer);
          final header = <int>[];
          peer.listen((bytes) async {
            header.addAll(bytes);
            if (!latin1.decode(header).endsWith('\r\n\r\n')) return;
            lines.add(latin1.decode(header).split('\r\n').first);
            peer.add(ascii.encode('HTTP/1.1 200 Connection'));
            await peer.flush();
            peer.add([...ascii.encode(' established\r\n\r\n'), ...raw]);
          }, onError: (_) {});
        });
        final socket = await connectNativeTcpSocket(
          '127.0.0.1',
          server.port,
          authority: '[::1]:18000',
        );
        final received = <int>[];
        final got = Completer<void>();
        final sub = socket.listen((bytes) {
          received.addAll(bytes);
          if (received.length == raw.length && !got.isCompleted) got.complete();
        });
        try {
          await got.future.timeout(const Duration(seconds: 5));
          expect(received, raw);
          expect(lines, ['CONNECT [::1]:18000 HTTP/1.1']);
        } finally {
          socket.destroy();
          await sub.cancel();
          for (final peer in peers) {
            peer.destroy();
          }
          await requests.cancel();
          await server.close();
        }
      },
    );

    test('pause and resume preserve all queued original bytes', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      final accepted = Completer<Socket>();
      final requests = server.listen((peer) {
        peers.add(peer);
        peer.listen((_) {}, onError: (_) {});
        accepted.complete(peer);
      });
      final socket = await connectSourceTcpSocket('127.0.0.1', server.port);
      final peer = await accepted.future;
      final received = <int>[];
      final got = Completer<void>();
      final sub = socket.listen((bytes) {
        received.addAll(bytes);
          if (received.length == raw.length * 200 && !got.isCompleted) {
          got.complete();
          }
      });
      try {
        sub.pause();
        for (var i = 0; i < 200; i++) {
          peer.add(raw);
        }
        await peer.flush();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(received, isEmpty);
        sub.resume();
        await got.future.timeout(const Duration(seconds: 5));
        expect(received, [for (var i = 0; i < 200; i++) ...raw]);
      } finally {
        socket.destroy();
        await sub.cancel();
        for (final peer in peers) {
          peer.destroy();
        }
        await requests.cancel();
        await server.close();
      }
    });

    test(
      'cancel during proxy handshake cannot deliver late ready or bytes',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final peers = <Socket>[];
        final accepted = Completer<void>();
        final requests = server.listen((peer) {
          peers.add(peer);
          peer.listen((_) {
            if (!accepted.isCompleted) accepted.complete();
          }, onError: (_) {});
        });
        final socket = NativeTcpSocket.open(
          InternetAddress.loopbackIPv4,
          server.port,
          authority: 'example.invalid:18000',
        );
        final readyCheck = expectLater(
          socket.ready,
          throwsA(isA<SocketException>()),
        );
        final received = <int>[];
        final sub = socket.listen(received.addAll, onError: (_) {});
        try {
          await accepted.future.timeout(const Duration(seconds: 5));
          socket.destroy();
          await readyCheck;
          peers.single.add([
            ...ascii.encode('HTTP/1.1 200 OK\r\n\r\n'),
            ...raw,
          ]);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(received, isEmpty);
        } finally {
          socket.destroy();
          await sub.cancel();
          for (final peer in peers) {
            peer.destroy();
          }
          await requests.cancel();
          await server.close();
        }
      },
    );

    test('destroy rejects pending flush without retaining buffers', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      final requests = server.listen(peers.add);
      final socket = await connectSourceTcpSocket('127.0.0.1', server.port);
      final sub = socket.listen((_) {}, onError: (_) {});
      try {
        final block = Uint8List.fromList([
          for (var i = 0; i < 100; i++) ...raw,
        ]);
        for (var i = 0; i < 50; i++) {
          socket.add(block);
        }
        final checked = expectLater(
          socket.flush(),
          throwsA(isA<SocketException>()),
        );
        socket.destroy();
        await checked;
        await socket.done;
        expect(() => socket.add(raw), throwsStateError);
      } finally {
        socket.destroy();
        await sub.cancel();
        for (final peer in peers) {
          peer.destroy();
        }
        await requests.cancel();
        await server.close();
      }
    });

    test(
      'refused connection fails ready and releases the native owner',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = server.port;
        await server.close();
        await expectLater(
          connectSourceTcpSocket(
            '127.0.0.1',
            port,
            timeout: const Duration(seconds: 1),
          ),
          throwsA(anyOf(isA<SocketException>(), isA<TimeoutException>())),
        );
      },
    );

    test(
      'oversized or malformed CONNECT headers fail without exposing body data',
      () async {
        for (final header in [
          List<int>.filled(17000, 65),
          ascii.encode('NOTHTTP 200 OK\r\n\r\n'),
        ]) {
          final server = await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          final peers = <Socket>[];
          final requests = server.listen((peer) {
            peers.add(peer);
            peer.listen((_) => peer.add(header), onError: (_) {});
          });
          try {
            await expectLater(
              connectNativeTcpSocket(
                '127.0.0.1',
                server.port,
                authority: 'example.invalid:18000',
              ),
              throwsA(isA<HttpException>()),
            );
          } finally {
            for (final peer in peers) {
              peer.destroy();
            }
            await requests.cancel();
            await server.close();
          }
        }
      },
    );
  }, skip: !native);
}

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Native TCP did not release sessions/sockets');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
