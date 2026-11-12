import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';
import 'package:flutterrhythmquake/services/sources/source_socket.dart';

// Local transport harness. Captured payloads are sent without rewriting their
// bytes, clocks or fields. Handshake/close cases below are controlled protocol
// cases, not claims about upstream behavior or whole-app performance.
void main() {
  final supported =
      Platform.isWindows &&
      Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY');
  final fixtures = [
    'test/fixtures/jma_cancellation_20261016/wolfx_original.json',
    'test/fixtures/catalog_20260917/whews_all.json',
    'test/fixtures/catalog_20260917/jian_all.json',
    'test/fixtures/emsc_ws_20261008.original.json',
    'test/fixtures/sasmex_firestore_20261006.relay.json',
    'test/fixtures/api_ingress_20261016/weather_alarm_full.original.bytes',
  ];
  test('idle native socket keeps its worker Dart isolate alive until close', () async {
    final baseline = NativeWebSocketChannel.activeWorkers;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    final requests = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request); peers.add(socket);
      await Future<void>.delayed(const Duration(milliseconds: 200)); socket.add('delayed frame');
    });
    final port = ReceivePort();
    final worker = await Isolate.spawn(_idleIsolate, [port.sendPort, 'ws://127.0.0.1:${server.port}/']);
    try {
      expect(await port.first.timeout(const Duration(seconds: 5)), 'delayed frame');
    } finally {
      worker.kill(priority: Isolate.immediate); port.close();
      for (final peer in peers) { await peer.close(); }
      await requests.cancel(); await server.close(force: true);
    }
    await _workers(baseline);
  }, skip: !supported);
  test('ws and wss use protocol default ports, not Uri default zero', () {
    expect(
      NativeWebSocketChannel.connectionPort(
        Uri.parse('wss://api.sismotide.top/all'),
      ),
      443,
    );
    expect(
      NativeWebSocketChannel.connectionPort(Uri.parse('ws://localhost/all')),
      80,
    );
    expect(
      NativeWebSocketChannel.connectionPort(
        Uri.parse('wss://localhost:8443/all'),
      ),
      8443,
    );
  });
  test(
    'source factory delivers original text bytes and retains actual ping transport',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final original = File(fixtures[2]).readAsBytesSync();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final requests = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        peers.add(socket);
        socket.add(utf8.decode(original));
      });
      final native = connectSourceSocket(
        Uri.parse('ws://127.0.0.1:${server.port}/native'),
      );
      final ping = connectSourceSocket(
        Uri.parse('ws://127.0.0.1:${server.port}/ping'),
        pingInterval: const Duration(seconds: 15),
      );
      try {
        expect(native, isA<NativeWebSocketChannel>());
        expect(ping, isNot(isA<NativeWebSocketChannel>()));
        final raw = await native.stream.first.timeout(
          const Duration(seconds: 5),
        );
        expect(raw, isA<List<int>>());
        expect(raw, original);
        expect(
          await ping.stream.first.timeout(const Duration(seconds: 5)),
          utf8.decode(original),
        );
      } finally {
        await native.sink.close();
        await ping.sink.close();
        await Future.wait(peers.map((peer) => peer.close()));
        await requests.cancel();
        await server.close(force: true);
      }
      await _workers(baseline);
    },
    skip: !supported,
  );

  test(
    'original text and binary frames, empty frames and fragments retain exact bytes',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? peer;
      final received = <dynamic>[];
      final allReceived = Completer<void>();
      final expected = [
        for (final path in fixtures)
          File(path).readAsStringSync(encoding: utf8),
        '',
        Uint8List.fromList([0, 128, 255, 1]),
        Uint8List(0),
      ];
      final requests = server.listen((request) async {
        expect(request.uri.toString(), '/all?token=a%2Bb&lang=ja');
        expect(request.headers.value('Authorization'), 'Bearer transport-test');
        peer = await WebSocketTransformer.upgrade(
          request,
          compression: CompressionOptions.compressionOff,
        );
        peer!.listen((frame) {
          received.add(frame);
          if (received.length == expected.length && !allReceived.isCompleted) {
            allReceived.complete();
          }
        });
        for (final frame in expected) {
          peer!.add(frame);
        }
      });
      final channel = NativeWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/all?token=a%2Bb&lang=ja'),
        headers: {'Authorization': 'Bearer transport-test'},
      );
      final inbound = <dynamic>[];
      final got = Completer<void>();
      final sub = channel.stream.listen((frame) {
        inbound.add(frame);
        if (inbound.length == expected.length) got.complete();
      });
      try {
        await channel.ready.timeout(const Duration(seconds: 5));
        for (final frame in expected) {
          channel.sink.add(frame);
        }
        await Future.wait([
          got.future,
          allReceived.future,
        ]).timeout(const Duration(seconds: 15));
        expect(inbound, expected);
        expect(received, expected);
        await channel.sink.close(1000, '完了');
        expect(channel.closeCode, 1000);
        expect(channel.closeReason, '完了');
      } finally {
        await channel.sink.close();
        await sub.cancel();
        await peer?.close();
        await requests.cancel();
        await server.close(force: true);
      }
      await _workers(baseline);
    },
    skip: !supported,
  );

  test(
    'remote 4401 status reaches auth handling before stream completion',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await socket.close(4401, '拒绝');
      });
      final channel = NativeWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/'),
      );
      final done = Completer<void>();
      final subscription = channel.stream.listen(
        (_) {},
        onDone: () {
          expect(channel.closeCode, 4401);
          expect(channel.closeReason, '拒绝');
          done.complete();
        },
      );
      await channel.ready;
      await done.future.timeout(const Duration(seconds: 5));
      await subscription.cancel();
      await requests.cancel();
      await server.close(force: true);
      await _workers(baseline);
    },
    skip: !supported,
  );

  test(
    'cancel during pending handshake releases native request; no late ready or data',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final pending = Completer<HttpRequest>();
      final requests = server.listen((request) {
        if (!pending.isCompleted) pending.complete(request);
      });
      final channel = NativeWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/'),
      );
      final errors = <Object>[];
      final subscription = channel.stream.listen(
        (_) => fail('Cancelled socket emitted data'),
        onError: errors.add,
      );
      final ready = expectLater(channel.ready, throwsA(isA<Exception>()));
      await pending.future.timeout(const Duration(seconds: 5));
      await channel.sink.close().timeout(const Duration(seconds: 3));
      await ready;
      await subscription.cancel();
      await requests.cancel();
      await server.close(force: true);
      await _workers(baseline);
    },
    skip: !supported,
  );

  test(
    'HTTP rejection and timeout fail ready and release all workers',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = server.listen((request) async {
        if (request.uri.path == '/reject') {
          request.response.statusCode = 401;
          await request.response.close();
        }
      });
      for (final path in ['/reject', '/stall']) {
        final channel = NativeWebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:${server.port}$path'),
          connectTimeout: const Duration(milliseconds: 500),
        );
        final errors = <Object>[];
        final subscription = channel.stream.listen(
          (_) => fail('Unexpected frame'),
          onError: errors.add,
        );
        await expectLater(channel.ready, throwsA(isA<Exception>()));
        await channel.sink.done;
        expect(errors, hasLength(1));
        await subscription.cancel();
      }
      await requests.cancel();
      await server.close(force: true);
      await _workers(baseline);
    },
    skip: !supported,
  );

  test(
    'six simultaneous connections do not exchange payloads or connection identity',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final requests = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(
          request,
          compression: CompressionOptions.compressionOff,
        );
        peers.add(socket);
        final original = File(
          fixtures[int.parse(request.uri.path.substring(1))],
        ).readAsStringSync(encoding: utf8);
        socket.listen((_) {
          for (var i = 0; i < 25; i++) {
            socket.add(original);
          }
        });
      });
      final channels = [
        for (var i = 0; i < fixtures.length; i++)
          NativeWebSocketChannel.connect(
            Uri.parse('ws://127.0.0.1:${server.port}/$i'),
          ),
      ];
      final subscriptions = <StreamSubscription<dynamic>>[];
      try {
        final completed = <Future<void>>[];
        for (var i = 0; i < channels.length; i++) {
          final original = File(fixtures[i]).readAsStringSync(encoding: utf8);
          final done = Completer<void>();
          var count = 0;
          subscriptions.add(
            channels[i].stream.listen((frame) {
              expect(frame, original);
              if (++count == 25) done.complete();
            }),
          );
          completed.add(done.future);
        }
        await Future.wait(channels.map((c) => c.ready));
        for (final c in channels) {
          c.sink.add('go');
        }
        await Future.wait(completed).timeout(const Duration(seconds: 20));
      } finally {
        await Future.wait(channels.map((c) => c.sink.close()));
        await Future.wait(subscriptions.map((s) => s.cancel()));
        await Future.wait(peers.map((p) => p.close()));
        await requests.cancel();
        await server.close(force: true);
      }
      await _workers(baseline);
    },
    skip: !supported,
  );
}

Future<void> _workers(int baseline) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (NativeWebSocketChannel.activeWorkers != baseline &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(NativeWebSocketChannel.activeWorkers, baseline);
}

Future<void> _idleIsolate(List<Object> args) async {
  final channel = NativeWebSocketChannel.connect(Uri.parse(args[1] as String));
  await channel.ready;
  final frame = await channel.stream.first;
  await channel.sink.close();
  (args[0] as SendPort).send(frame);
}
