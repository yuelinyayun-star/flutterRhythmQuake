import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/collector/jian_collector_feed.dart';
import 'package:flutterrhythmquake/services/jian_auth_service.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';
import 'package:flutterrhythmquake/services/sources/sidesis_socket_io_client.dart';
import 'package:flutterrhythmquake/services/sources/source_socket.dart';

import 'jian_auth_test.dart' show ticket;
import 'jian_integration_test.dart' show FakeChannel;

// Lifecycle faults and local Socket.IO envelopes below are controlled inputs.
// The Jian snapshot is the unchanged captured original, never rewritten.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // Widget binding installs an HTTP test override. These tests use only
    // MockClient auth and loopback servers, so exercise the real factory.
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() {
      HttpOverrides.global = previous;
    });
  });
  final native =
      Platform.isWindows &&
      Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY');
  final raw = File('test/fixtures/jian/all.json').readAsBytesSync();

  testWidgets(
    'collector preserves original byte frames, reconnects once and rejects old callbacks',
    (tester) async {
      var exchanges = 0;
      final channels = <FakeChannel>[];
      final uris = <Uri>[];
      final headersSeen = <Map<String, dynamic>?>[];
      final events = <UnifiedQuakeData>[];
      final statuses = <String>[];
      final feed = JianCollectorFeed(
        credential: 'rt_test',
        now: tester.binding.clock.now,
        auth: JianAuthService(
          client: MockClient((_) async => ticket('at_test${++exchanges}')),
        ),
        onEvent: events.add,
        onStatus: statuses.add,
        socketFactory: (uri, {headers}) {
          uris.add(uri);
          headersSeen.add(headers);
          final socket = FakeChannel();
          channels.add(socket);
          return socket;
        },
      );
      addTearDown(feed.stop);
      feed.start();
      await tester.pump();
      expect(uris.map((uri) => uri.toString()), [
        'wss://api.sismotide.top/all',
      ], reason: statuses.toString());
      expect(statuses.last, 'connected');
      channels.single.frames.add(raw);
      await tester.pump();
      final expected = JianCollectorFeed.decodeFrame(
        jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
        receivedAt: tester.binding.clock.now(),
      ).map((e) => e.toMap()).toList();
      expect(events.map((e) => e.toMap()).toList(), expected);
      expect(events, isNotEmpty);
      channels.single.frames.addError(StateError('offline'));
      unawaited(channels.single.frames.close());
      await tester.pump();
      expect(statuses.where((s) => s == 'retry_in_300s'), hasLength(1));
      await tester.pump(const Duration(minutes: 5));
      expect(exchanges, 2);
      expect(channels, hasLength(2));
      expect(headersSeen.last, {'Authorization': 'Bearer at_test2'});
      expect(statuses.last, 'connected');
      final count = events.length;
      await feed.stop();
      channels.last.frames.add(raw);
      await tester.pump(const Duration(minutes: 10));
      expect(events, hasLength(count));
      expect(exchanges, 2);
    },
  );

  testWidgets(
    'collector stop during pending authentication or handshake prevents revival',
    (tester) async {
      final pendingAuth = Completer<http.Response>();
      final statuses = <String>[];
      var opens = 0;
      final feed = JianCollectorFeed(
        credential: 'rt_test',
        onEvent: (_) {},
        onStatus: statuses.add,
        auth: JianAuthService(client: MockClient((_) => pendingAuth.future)),
        socketFactory: (_, {headers}) {
          opens++;
          return FakeChannel();
        },
      );
      feed.start();
      await tester.pump();
      await feed.stop();
      pendingAuth.complete(ticket('at_test'));
      await tester.pump();
      expect(opens, 0);
      expect(statuses, ['connecting']);

      final ready = Completer<void>();
      final socket = FakeChannel(ready: ready.future);
      final handshaking = JianCollectorFeed(
        credential: 'rt_test',
        onEvent: (_) {},
        onStatus: statuses.add,
        auth: JianAuthService(
          client: MockClient((_) async => ticket('at_test')),
        ),
        socketFactory: (_, {headers}) => socket,
      );
      handshaking.start();
      await tester.pump();
      await handshaking.stop();
      ready.completeError(StateError('old handshake'));
      await tester.pump(const Duration(minutes: 10));
      expect(statuses, ['connecting', 'connecting']);
      await socket.sink.done;
    },
  );

  test('Sidesis old handshake failure cannot schedule a second reconnect', () {
    fakeAsync((clock) {
      final sockets = <FakeChannel>[];
      final ready = Completer<void>();
      final client = SidesisSocketIoClient(
        socketFactory: (_) {
          final socket = FakeChannel(
            ready: sockets.isEmpty ? ready.future : null,
          );
          sockets.add(socket);
          return socket;
        },
      );
      client.start();
      sockets.first.frames.addError(StateError('offline'));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 3));
      clock.flushMicrotasks();
      expect(sockets, hasLength(2));
      ready.completeError(StateError('late ready failure'));
      clock.flushMicrotasks();
      sockets.last.frames.add('40');
      clock.flushMicrotasks();
      expect(client.isConnected, isTrue);
      clock.elapse(const Duration(seconds: 30));
      expect(sockets, hasLength(2));
      client.stop();
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'Sidesis protocol still preserves text callbacks and ignores binary frames',
    () {
      fakeAsync((clock) {
        final socket = FakeChannel();
        final frames = <String>[];
        final events = <String>[];
        final client = SidesisSocketIoClient(
          socketFactory: (_) => socket,
          onRawFrame: frames.add,
          onEvent: (name, _) => events.add(name),
        );
        client.start();
        clock.flushMicrotasks();
        for (final frame in [
          '0{}',
          '2',
          '40',
          '42["message",{"title":"中文・日本語","severity":"Minor"}]',
        ]) {
          socket.frames.add(frame);
        }
        socket.frames.add(utf8.encode('42["binary",{}]'));
        clock.flushMicrotasks();
        expect(socket.sent, ['40', '3']);
        expect(frames, hasLength(4));
        expect(events, ['message']);
        expect(client.sendEvent('confirmed', {'value': '中文'}), isTrue);
        expect(socket.sent.last, '42["confirmed",{"value":"中文"}]');
        client.stop();
        clock.flushMicrotasks();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'collector original snapshot uses actual native socket and releases worker',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final requests = server.listen((request) async {
        expect(request.headers.value('Authorization'), 'Bearer at_test');
        final peer = await WebSocketTransformer.upgrade(request);
        peers.add(peer);
        peer.listen((_) {});
        peer.add(utf8.decode(raw));
      });
      final received = <UnifiedQuakeData>[];
      final got = Completer<void>();
      final feed = JianCollectorFeed(
        credential: 'rt_test',
        onStatus: (_) {},
        auth: JianAuthService(
          client: MockClient((_) async => ticket('at_test')),
        ),
        socketFactory: (_, {headers}) {
          final channel = connectSourceSocket(
            Uri.parse('ws://127.0.0.1:${server.port}/all'),
            headers: headers,
          );
          expect(channel, isA<NativeWebSocketChannel>());
          return channel;
        },
        onEvent: (event) {
          received.add(event);
          if (!got.isCompleted) got.complete();
        },
      );
      try {
        feed.start();
        await got.future.timeout(const Duration(seconds: 10));
        final expected = JianCollectorFeed.decodeFrame(
          jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
        ).toList();
        expect(
          received.map((e) => e.sourcePayload).toList(),
          expected.map((e) => e.sourcePayload).toList(),
        );
      } finally {
        await feed.stop();
        for (final peer in peers) {
          await peer.close();
        }
        await requests.cancel();
        await server.close(force: true);
      }
      await workers(baseline);
    },
    skip: !native,
  );

  test(
    'Sidesis actual native socket completes namespace, ping and reconnect',
    () async {
      final baseline = NativeWebSocketChannel.activeWorkers;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final pongs = <WebSocket>[];
      final messages = <SidesisSocketIoMessage>[];
      final requests = server.listen((request) async {
        expect(request.uri.queryParameters, {
          'EIO': '4',
          'transport': 'websocket',
        });
        final peer = await WebSocketTransformer.upgrade(request);
        peers.add(peer);
        peer.listen((frame) {
          if (frame == '40') {
            peer.add('40{}');
            peer.add('2');
            peer.add(
              '42["message",{"title":"协议测试・日本語","severity":"Moderate"}]',
            );
          }
          if (frame == '3') pongs.add(peer);
        });
        peer.add('0{"sid":"controlled-session"}');
      });
      final client = SidesisSocketIoClient(
        url: 'ws://127.0.0.1:${server.port}/socket.io/',
        onMessage: messages.add,
      );
      try {
        client.start();
        await until(
          () => client.isConnected && messages.length == 1 && pongs.length == 1,
        );
      expect(NativeWebSocketChannel.activeWorkers, baseline + 1);
        expect(messages.single.title, '协议测试・日本語');
        expect(messages.single.rawSeverity, 'Moderate');
        await peers.single.close();
        await until(
          () =>
              peers.length == 2 &&
              client.isConnected &&
              messages.length == 2 &&
              pongs.length == 2,
        );
        client.stop();
      } finally {
        client.stop();
        for (final peer in peers) {
          await peer.close();
        }
        await requests.cancel();
        await server.close(force: true);
      }
      await workers(baseline);
    },
    skip: !native,
  );
}

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for local transport');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> workers(int expected) =>
    until(() => NativeWebSocketChannel.activeWorkers == expected);
