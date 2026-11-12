import 'package:flutterrhythmquake/services/whews_authorization_policy.dart';
// Controlled protocol/lifecycle fixtures. Never contacts an upstream service.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/base_source.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/services/sources/fan_service.dart';
import 'package:flutterrhythmquake/services/sources/fan_socket_connection.dart';
import 'package:flutterrhythmquake/services/sources/whews_socket_client.dart';
import 'package:flutterrhythmquake/services/sources/source_connection_lifecycle.dart';
import 'jian_integration_test.dart' show FakeChannel;

class ProbeSource extends BaseSourceService {
  ProbeSource(this.name);
  @override
  final String name;
  int opens = 0, closes = 0;
  @override
  void connect() {
    opens++;
  }

  @override
  void disconnect() {
    closes++;
  }
}

class FanPeer implements FanSocketConnection, FanSocketCloseDetails {
  final frames = StreamController<Object?>();
  final sent = <String>[];
  final closeGate = Completer<void>();
  bool holdClose = false, closed = false;
  @override
  int? closeCode;
  @override
  String get transportName => 'controlled';
  @override
  Future<void> get ready => Future.value();
  @override
  Stream<Object?> get stream => frames.stream;
  @override
  Future<void> send(String message) async {
    if (closed) throw StateError('closed');
    sent.add(message);
  }

  @override
  Future<void> close() {
    closed = true;
    if (!holdClose && !closeGate.isCompleted) closeGate.complete();
    return closeGate.future;
  }
}

class WhewsPeer extends FakeChannel {
  WhewsPeer({super.ready});
  @override
  int? closeCode;
  @override
  String? closeReason;
}

void main() {
  setUp(() => WhewsAuthorizationPolicy.storeOverride = MemoryConnectionRetryStore());
  testWidgets(
    'reset cancels delayed source starts, including an old credential owner',
    (tester) async {
      final manager = SourceManager();
      manager.reset();
      final first = ProbeSource('first'),
          old = ProbeSource('FAN'),
          fresh = ProbeSource('FAN');
      manager.registerSource(first);
      manager.registerSource(old);
      manager.startAll(stagger: const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 20));
      manager.reset();
      manager.registerSource(fresh);
      manager.startAll(stagger: Duration.zero);
      await tester.pump(const Duration(seconds: 1));
      expect(old.opens, 0);
      expect(fresh.opens, 1);
      manager.stopAll();
      expect(fresh.closes, 1);
      manager.reset();
      first.dispose();
      old.dispose();
      fresh.dispose();
    },
  );
  testWidgets('enable while staggered start is pending opens the source once', (
    tester,
  ) async {
    final manager = SourceManager();
    manager.reset();
    final a = ProbeSource('first'), b = ProbeSource('FAN');
    manager.registerSource(a);
    manager.registerSource(b);
    manager.startAll();
    manager.setSourceEnabled('FAN', false);
    manager.setSourceEnabled('FAN', true);
    await tester.pump(const Duration(seconds: 1));
    expect(b.opens, 1);
    manager.reset();
    a.dispose();
    b.dispose();
  });
  testWidgets(
    'FAN empty key never opens, credentials start one authenticated handshake',
    (tester) async {
      final peers = <FanPeer>[];
      final source = FanService(
        socketFactory: (_) async {
          final p = FanPeer();
          peers.add(p);
          return p;
        },
      );
      source.connect();
      source.connect();
      await tester.pump();
      expect(peers, isEmpty);
      source.setApiKey('controlled-key');
      await tester.pump();
      expect(peers, hasLength(1));
      expect(jsonDecode(peers.single.sent.single)['type'], 'auth');
      await tester.pump(const Duration(seconds: 10));
      expect(peers.single.sent, hasLength(1));
      peers.single.frames.add('{"type":"auth_success"}');
      await tester.pump();
      expect(peers.single.sent, contains('cwalist'));
      expect(source.authStatusNotifier.value, FanAuthStatus.authenticated);
      source.dispose();
      await tester.pump();
      expect(peers.single.closed, isTrue);
    },
  );
  for (final type in ['auth_fail', 'auth_error', 'error']) {
    testWidgets(
      'FAN $type stops business and retries until credentials change',
      (tester) async {
        final peers = <FanPeer>[];
        final source = FanService(
          apiKey: 'controlled-old',
          socketFactory: (_) async {
            final p = FanPeer();
            peers.add(p);
            return p;
          },
        );
        source.connect();
        await tester.pump();
        peers.single.frames.add(
          jsonEncode({'type': type, 'message': 'controlled rejection'}),
        );
        await tester.pump();
        await tester.pump(const Duration(hours: 1));
        expect(peers, hasLength(1));
        expect(peers.single.closed, isTrue);
        expect(peers.single.sent, hasLength(1));
        expect(source.authStatusNotifier.value, FanAuthStatus.failed);
        source.connect();
        await tester.pump();
        expect(peers, hasLength(1));
        source.setApiKey('controlled-new');
        await tester.pump();
        expect(peers, hasLength(2));
        expect(jsonDecode(peers.last.sent.single)['key'], 'controlled-new');
        source.dispose();
        await tester.pump();
      },
    );
  }
  testWidgets(
    'FAN repeated short authenticated sessions retain increasing backoff',
    (tester) async {
      final peers = <FanPeer>[];
      final source = FanService(
        apiKey: 'controlled',
        socketFactory: (_) async {
          final p = FanPeer();
          peers.add(p);
          return p;
        },
      );
      source.connect();
      await tester.pump();
      peers.last.frames.add('{"type":"auth_success"}');
      await tester.pump();
      unawaited(peers.last.frames.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(peers, hasLength(2));
      peers.last.frames.add('{"type":"auth_success"}');
      await tester.pump();
      unawaited(peers.last.frames.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(peers, hasLength(2));
      await tester.pump(const Duration(seconds: 3));
      expect(peers, hasLength(3));
      source.dispose();
      await tester.pump();
    },
  );
  testWidgets('FAN replacement waits for pending factory and old close', (
    tester,
  ) async {
    final pending = Completer<FanSocketConnection>();
    final old = FanPeer()..holdClose = true;
    final fresh = FanPeer();
    var opens = 0;
    final source = FanService(
      apiKey: 'controlled-old',
      socketFactory: (_) {
        opens++;
        return opens == 1 ? pending.future : Future.value(fresh);
      },
    );
    source.connect();
    await tester.pump();
    source.setApiKey('controlled-new');
    await tester.pump();
    expect(opens, 1);
    pending.complete(old);
    await tester.pump();
    expect(old.closed, isTrue);
    expect(opens, 1);
    old.closeGate.complete();
    await tester.pump();
    expect(opens, 2);
    expect(old.sent, isEmpty);
    expect(jsonDecode(fresh.sent.single)['key'], 'controlled-new');
    source.dispose();
    await tester.pump();
  });
  testWidgets('FAN dispose cancels a queued reconnect', (tester) async {
    var opens = 0;
    final peer = FanPeer();
    final source = FanService(
      apiKey: 'controlled',
      socketFactory: (_) async {
        opens++;
        return peer;
      },
    );
    source.connect();
    await tester.pump();
    unawaited(peer.frames.close());
    await tester.pump();
    source.dispose();
    await tester.pump(const Duration(minutes: 10));
    expect(opens, 1);
    expect(peer.closed, isTrue);
  });
  for (final code in [4401, 4403, 4008]) {
    testWidgets(
      'WHEWS $code stops on first rejection without an anonymous fallback',
      (tester) async {
        final peers = <WhewsPeer>[];
        final uris = <Uri>[];
        final states = <WhewsSocketState>[];
        final client = WhewsSocketClient(
          url: 'ws://loopback-$code/business',
          apiToken: 'wat_controlled',
          onMessage: (_) {},
          onStateChanged: states.add,
          socketFactory: (uri) {
            uris.add(uri);
            final p = WhewsPeer();
            peers.add(p);
            return p;
          },
        );
        client.start();
        await tester.pump();
        peers.single.closeCode = code;
        unawaited(peers.single.frames.close());
        await tester.pump();
        await tester.pump(const Duration(hours: 1));
        client.reconnect();
        await tester.pump();
        expect(uris, hasLength(1));
        expect(uris.single.queryParameters['token'], 'wat_controlled');
        expect(client.authorizationRejected, isTrue);
        expect(states, isNot(contains(WhewsSocketState.connected)));
        client.dispose();
        await tester.pump();
      },
    );
  }
  testWidgets(
    'WHEWS error frame never marks session alive or reaches business',
    (tester) async {
      final peer = WhewsPeer();
      final states = <WhewsSocketState>[];
      var delivered = 0;
      final client = WhewsSocketClient(
        url: 'ws://loopback-error/business',
        apiToken: 'wat_controlled',
        onMessage: (_) {
          delivered++;
        },
        onStateChanged: states.add,
        socketFactory: (_) => peer,
      );
      client.start();
      await tester.pump();
      peer.frames.add('{"type":"error","message":"controlled rejection"}');
      await tester.pump();
      expect(client.aliveConfirmed, isFalse);
      expect(client.authorizationRejected, isTrue);
      expect(delivered, 0);
      expect(states, isNot(contains(WhewsSocketState.connected)));
      client.dispose();
      await tester.pump();
    },
  );
  test(
    'late local wakeup grants bounded ingress recovery, real staleness remains detectable',
    () {
      final now = DateTime.utc(2026, 10, 18);
      final watcher = SourceActivityWatchdog(const Duration(seconds: 30));
      watcher.reset(now);
      expect(
        watcher.mayDeclareStale(now.add(const Duration(seconds: 95))),
        isFalse,
      );
      expect(
        watcher.mayDeclareStale(now.add(const Duration(seconds: 116))),
        isTrue,
      );
    },
  );
  test('shutdown failure keeps the replacement gate closed', () async {
    final barrier = SourceConnectionBarrier();
    barrier.close(() async => throw StateError('controlled shutdown failure'));
    await expectLater(barrier.wait(), throwsStateError);
    await expectLater(barrier.wait(), throwsStateError);
  });
  testWidgets('a delayed local handshake timer drains pending readiness before failing', (tester) async {
    var wall = DateTime.utc(2026, 10, 18);
    final ready = Completer<void>();
    var complete = false;
    final result = sourceReady(ready.future, const Duration(seconds: 10), now: () => wall).then((_) { complete = true; });
    wall = wall.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 10));
    expect(complete, isFalse);
    ready.complete(); await tester.pump(); await result;
    expect(complete, isTrue);
  });

  testWidgets('WHEWS short successful handshakes retain increasing backoff', (tester) async {
    final peers = <WhewsPeer>[];
    final client = WhewsSocketClient(url: 'ws://controlled-short/all', apiToken: 'wat_controlled', onMessage: (_) {},
      socketFactory: (_) { final peer = WhewsPeer(); peers.add(peer); return peer; });
    client.start(); await tester.pump();
    peers.last.frames.add('{"type":"pong"}'); await tester.pump();
    unawaited(peers.last.frames.close()); await tester.pump();
    await tester.pump(const Duration(seconds: 3)); expect(peers, hasLength(2));
    peers.last.frames.add('{"type":"pong"}'); await tester.pump();
    unawaited(peers.last.frames.close()); await tester.pump();
    await tester.pump(const Duration(seconds: 3)); expect(peers, hasLength(2));
    await tester.pump(const Duration(seconds: 3)); expect(peers, hasLength(3));
    client.dispose(); await tester.pump();
  });

  testWidgets('FAN local stall drains a queued auth success before rejecting the session', (tester) async {
    var wall = DateTime.utc(2026, 10, 18);
    final peer = FanPeer();
    final source = FanService(apiKey: 'controlled', now: () => wall, socketFactory: (_) async => peer);
    source.connect(); await tester.pump();
    wall = wall.add(const Duration(seconds: 95));
    await tester.pump(const Duration(seconds: 15));
    expect(peer.closed, isFalse);
    peer.frames.add('{"type":"auth_success"}'); await tester.pump();
    expect(source.authStatusNotifier.value, FanAuthStatus.authenticated);
    source.dispose(); await tester.pump();
  });

}
