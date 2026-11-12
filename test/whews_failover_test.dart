// Controlled transport failures only; observation payloads are original files.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutterrhythmquake/services/native_whews_connection.dart';
import 'package:flutterrhythmquake/services/whews_authorization_policy.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';
import 'package:flutterrhythmquake/services/sources/whews_service.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';
import 'jian_auth_retry_policy_test.dart' show PeerSink;
import 'whews_authorization_policy_test.dart' show WhewsPeer;

class _Harness {
  WhewsPeer Function(int)? peerFactory;
  final peers = <WhewsPeer>[];
  final requests = <Uri>[];
  final messages = <dynamic>[];
  WebSocketChannel open(Uri uri) {
    requests.add(uri);
    final peer = peerFactory?.call(requests.length) ?? WhewsPeer();
    peers.add(peer);
    return peer;
  }

  WhewsSocketClient client([String url = WhewsService.aggregateUrl]) =>
      WhewsSocketClient(
        url: url,
        apiToken: 'wat_controlled',
        socketFactory: open,
        onMessage: messages.add,
      );
  Future<void> ready(WidgetTester tester) async {
    await tester.pump();
    peers.last.frames.add('{"type":"pong"}');
    await tester.pump();
  }

  Future<void> fail(WidgetTester tester, int delay) async {
    peers.last.closeCode = 1006;
    await peers.last.frames.close();
    await tester.pump();
    await tester.pump(Duration(seconds: delay));
    await ready(tester);
  }
}

class _HeldSink extends PeerSink {
  final releaseClose = Completer<void>();
  @override
  Future<void> close([int? code, String? reason]) => releaseClose.future;
}

class _HeldPeer extends WhewsPeer {
  final closeControl = _HeldSink();
  @override
  _HeldSink get sink => closeControl;
}

void main() {
  setUp(
    () => WhewsAuthorizationPolicy.storeOverride = MemoryConnectionRetryStore(),
  );
  testWidgets(
    'replacement waits for the failed primary socket to finish closing',
    (tester) async {
      final held = _HeldPeer();
      final h = _Harness()
        ..peerFactory = (attempt) => attempt == 5 ? held : WhewsPeer();
      final client = h.client();
      client.start();
      await h.ready(tester);
      for (final delay in [3, 6, 12, 24]) {
        await h.fail(tester, delay);
      }
      held.closeCode = 1006;
      await held.frames.close();
      await tester.pump();
      await tester.pump(const Duration(seconds: 48));
      expect(h.requests, hasLength(5));
      held.sink.releaseClose.complete();
      await h.ready(tester);
      expect(h.requests, hasLength(6));
      expect(h.requests.last.host, 'api.2v8.cn');
      client.dispose();
      await tester.pump();
      await client.closed;
    },
  );

  testWidgets(
    'failed primary switches to a real local WebSocket using Rust transport and delivers original payload',
    (tester) async {
      late HttpServer server;
      StreamSubscription<HttpRequest>? listener;
      final sockets = <WebSocket>[];
      final received = Completer<dynamic>();
      final requests = <Uri>[];
      final raw = File(
        'test/fixtures/cwa_catalog_20261028/whews_cwa.original.json',
      ).readAsStringSync();
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        listener = server.listen((request) async {
          expectSync(request.uri.queryParameters['token'], 'wat_local_only');
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          socket.listen((_) {});
          socket.add(raw);
        });
      });
      final client = WhewsSocketClient(
        url: WhewsService.aggregateUrl,
        apiToken: 'wat_local_only',
        onMessage: (message) {
          if (!received.isCompleted) received.complete(message);
        },
        socketFactory: (uri) {
          requests.add(uri);
          if (uri.host == 'api.beecld.com') {
            throw const SocketException('controlled primary unavailable');
          }
          // Keep the native transport, remapping only the upstream address to
          // loopback; no test credential ever leaves this machine.
          final channel = NativeWebSocketChannel.connect(
            uri.replace(scheme: 'ws', host: '127.0.0.1', port: server.port),
          );
          expectSync(channel, isA<NativeWebSocketChannel>());
          return channel;
        },
      );
      try {
        client.start();
        await tester.pump();
        for (final delay in [3, 6, 12, 24, 48]) {
          await tester.pump(Duration(seconds: delay));
        }
        // Native port delivery and the widget binding's microtask queue must
        // both run; a single runAsync wait would leave UI ingress queued.
        for (var i = 0; i < 100 && !received.isCompleted; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(
          received.isCompleted,
          isTrue,
          reason:
              'attempts=$requests peers=${sockets.length} active=${client.activeUrl} alive=${client.aliveConfirmed}',
        );
        expect(jsonEncode(await received.future), jsonEncode(jsonDecode(raw)));
        expect(requests.last.host, 'api.2v8.cn');
        expect(client.aliveConfirmed, isTrue);
        expect(NativeWhewsConnection.outputs, 0);
      } finally {
        client.stop();
        await tester.pump();
        var transportClosed = false;
        unawaited(client.closed.then((_) => transportClosed = true));
        for (var i = 0; i < 100 && !transportClosed; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(
          transportClosed,
          isTrue,
          reason: 'native close must finish before replacing the connection',
        );
        await tester.runAsync(() async {
          for (final socket in sockets) {
            await socket.close();
          }
          await listener?.cancel();
          await server.close(force: true);
        });
      }
    },
  );
  test(
    'native routing limits backups to documented shared feeds and releases output',
    () {
      expect(
        NativeWhewsConnection.supported,
        isTrue,
        reason: 'Run against the actual Release DLL',
      );
      for (final path in ['all', 'nied', 'snet', 'kma_station']) {
        expect(
          NativeWhewsConnection.prepare({
            'op': 'endpoints',
            'url': 'wss://api.beecld.com/ws/$path',
          }),
          ['wss://api.beecld.com/ws/$path', 'wss://api.2v8.cn/ws/$path'],
        );
      }
      expect(
        NativeWhewsConnection.prepare({
          'op': 'endpoints',
          'url': WhewsService.ceaAggregateUrl,
        }),
        [WhewsService.ceaAggregateUrl],
      );
      expect(NativeWhewsConnection.outputs, 0);
    },
  );
  test(
    'aggregate failover retains deduplication while the CEA connection stays live',
    () => fakeAsync((clock) {
      final h = _Harness();
      final service = WhewsService(
        apiToken: 'wat_controlled',
        socketFactory: h.open,
      );
      final events = <UnifiedQuakeData>[];
      final subscription = service.onUnifiedEvent.listen(events.add);
      service.connect();
      clock.flushMicrotasks();
      expect(h.requests.map((u) => u.path), ['/ws/all', '/ws/cea_all']);
      final ceaPeer = h.peers[1];
      var aggregate = h.peers.first;
      aggregate.frames.add('{"type":"pong"}');
      ceaPeer.frames.add('{"type":"pong"}');
      clock.flushMicrotasks();
      final original = File(
        'test/fixtures/cwa_catalog_20261028/whews_cwa.original.json',
      ).readAsStringSync();
      aggregate.frames.add(original);
      clock.flushMicrotasks();
      expect(events, hasLength(1));
      for (final delay in [3, 6, 12, 24, 48]) {
        aggregate.closeCode = 1006;
        unawaited(aggregate.frames.close());
        clock.flushMicrotasks();
        clock.elapse(Duration(seconds: delay));
        clock.flushMicrotasks();
        aggregate = h.peers.last;
        aggregate.frames.add('{"type":"pong"}');
        clock.flushMicrotasks();
      }
      expect(h.requests.last.host, 'api.2v8.cn');
      expect(h.requests.last.path, '/ws/all');
      expect(h.requests.where((u) => u.path == '/ws/cea_all'), hasLength(1));
      expect(ceaPeer.frames.isClosed, isFalse);
      aggregate.frames.add(original);
      clock.flushMicrotasks();
      expect(events, hasLength(1));
      service.dispose();
      clock.flushMicrotasks();
      unawaited(subscription.cancel());
      clock.flushMicrotasks();
      expect(NativeWhewsConnection.outputs, 0);
    }),
  );

  testWidgets(
    'FAN backoff switches only after repeated failure; stable backup stays; restart prefers primary',
    (tester) async {
      final h = _Harness();
      final client = h.client();
      client.start();
      await h.ready(tester);
      for (final delay in [3, 6, 12, 24, 48]) {
        await h.fail(tester, delay);
      }
      expect(h.requests.map((u) => u.host), [
        for (var i = 0; i < 5; i++) 'api.beecld.com',
        'api.2v8.cn',
      ]);
      expect(client.activeUrl, 'wss://api.2v8.cn/ws/all');
      expect(
        h.requests.every(
          (u) =>
              u.path == '/ws/all' &&
              u.queryParameters['token'] == 'wat_controlled',
        ),
        isTrue,
      );
      final original = File(
        'test/fixtures/cwa_catalog_20261028/whews_cwa.original.json',
      ).readAsStringSync();
      h.peers.last.frames.add(original);
      await tester.pump();
      expect(jsonEncode(h.messages.single), jsonEncode(jsonDecode(original)));
      await tester.pump(const Duration(seconds: 61));
      await h.fail(tester, 3);
      expect(h.requests.last.host, 'api.2v8.cn');
      client.stop();
      await tester.pump();
      await client.closed;
      client.start();
      await h.ready(tester);
      expect(h.requests.last.host, 'api.beecld.com');
      client.dispose();
      await tester.pump();
      await client.closed;
      expect(NativeWhewsConnection.outputs, 0);
    },
  );

  for (final code in [4401, 4403, 4008, 404]) {
    testWidgets(
      '$code rejection stays stopped instead of switching endpoints',
      (tester) async {
        final h = _Harness();
        final client = h.client();
        client.start();
        await h.ready(tester);
        h.peers.last.closeCode = code;
        await h.peers.last.frames.close();
        await tester.pump();
        await client.closed;
        await tester.pump(const Duration(minutes: 10));
        expect(client.authorizationRejected, isTrue);
        expect(h.requests, hasLength(1));
        client.dispose();
        await tester.pump();
      },
    );
  }

  testWidgets(
    'backup rejection is persisted for its actual host and does not trigger another connection',
    (tester) async {
      final h = _Harness();
      final client = h.client();
      client.start();
      await h.ready(tester);
      for (final delay in [3, 6, 12, 24, 48]) {
        await h.fail(tester, delay);
      }
      h.peers.last.closeCode = 4403;
      await h.peers.last.frames.close();
      await tester.pump();
      await client.closed;
      expect(
        await WhewsAuthorizationPolicy().blockedCode(
          'wss://api.2v8.cn/ws/all',
          'wat_controlled',
        ),
        4403,
      );
      expect(
        await WhewsAuthorizationPolicy().blockedCode(
          WhewsService.aggregateUrl,
          'wat_controlled',
        ),
        isNull,
      );
      await tester.pump(const Duration(minutes: 10));
      expect(h.requests, hasLength(6));
      client.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'manual stop cancels pending switch; CEA remains a separate domestic feed',
    (tester) async {
      final h = _Harness();
      final cea = h.client(WhewsService.ceaAggregateUrl);
      cea.start();
      await h.ready(tester);
      for (final delay in [3, 6, 12, 24, 48, 96]) {
        await h.fail(tester, delay);
      }
      expect(
        h.requests.every(
          (u) => u.host == 'api.2v8.cn' && u.path == '/ws/cea_all',
        ),
        isTrue,
      );
      h.peers.last.closeCode = 1006;
      await h.peers.last.frames.close();
      await tester.pump();
      cea.stop();
      await tester.pump();
      await cea.closed;
      final count = h.requests.length;
      await tester.pump(const Duration(minutes: 10));
      expect(h.requests, hasLength(count));
    },
  );
}
