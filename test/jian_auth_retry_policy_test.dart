// Controlled authentication/lifecycle inputs. No upstream traffic or observations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutterrhythmquake/services/jian_auth_retry_policy.dart';
import 'package:flutterrhythmquake/services/connection_retry_store_io.dart';
import 'package:flutterrhythmquake/services/jian_auth_service.dart';
import 'package:flutterrhythmquake/services/sources/jian_service.dart';
import 'package:flutterrhythmquake/services/collector/jian_collector_feed.dart';

class Peer implements WebSocketChannel {
  @override
  int? get closeCode => null;
  final frames = StreamController<dynamic>();
  @override
  Stream<dynamic> get stream => frames.stream;
  @override
  Future<void> get ready => Future<void>.value();
  @override
  final WebSocketSink sink = PeerSink();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  void reject(int code) => frames.add(jsonEncode({'ok': false, 'code': code}));
}

class PeerSink implements WebSocketSink {
  @override
  void add(dynamic data) {}
  @override
  Future<void> close([int? code, String? reason]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BrokenRetryStore implements ConnectionRetryStore {
  @override
  Future<T> update<T>(
    String fingerprint,
    T Function(Map<String, dynamic>) action,
  ) => Future<T>.error(StateError('controlled storage failure'));
}

class Harness {
  Harness(this.now, this.policy);
  final DateTime Function() now;
  final JianAuthRetryPolicy policy;
  final peers = <Peer>[];
  final headers = <String>[];
  int requests = 0;
  JianAuthService auth() => JianAuthService(
    now: now,
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'ok': true,
          'token': 'at_controlled_${++requests}',
          'expires_after_sec': 3600,
        }),
        200,
      ),
    ),
  );
  WebSocketChannel socket(Uri _, {Map<String, dynamic>? headers}) {
    this.headers.add(headers!['Authorization'] as String);
    final peer = Peer();
    peers.add(peer);
    return peer;
  }

  JianService service() => JianService(
    now: now,
    retryPolicy: policy,
    authService: auth(),
    socketFactory: socket,
  );
  JianCollectorFeed collector(List<String> statuses) => JianCollectorFeed(
    credential: 'rt_controlled',
    now: now,
    retryPolicy: policy,
    auth: auth(),
    socketFactory: socket,
    onEvent: (_) {},
    onStatus: statuses.add,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      JianCredentialStore.storageKey: 'rt_controlled',
    });
    JianAuthRetryPolicy.storeOverride = MemoryConnectionRetryStore();
  });
  for (final codes in [
    [4003, 4003, 4003],
    [4004, 4004, 4004],
    [4003, 4004, 4003],
  ]) {
    testWidgets(
      'main stops after three consecutive rejections $codes across reload and collector',
      (tester) async {
        final policy = JianAuthRetryPolicy();
        final h = Harness(tester.binding.clock.now, policy);
        final service = h.service();
        service.connect();
        await tester.pump();
        for (var i = 0; i < codes.length; i++) {
          h.peers.last.reject(codes[i]);
          await tester.pump();
          await tester.pump(const Duration(minutes: 5));
        }
        expect(h.requests, 3);
        expect(h.headers.toSet(), hasLength(3));
        expect(service.credentialInfo.errorCode, 'auth_retry_exhausted');
        expect(service.authStatus, JianAuthStatus.invalid);
        service.dispose();
        await tester.pump();
        // New owners share durable policy, not the stopped object's in-memory state.
        final next = Harness(tester.binding.clock.now, policy);
        final restarted = next.service();
        restarted.connect();
        await tester.pump();
        final statuses = <String>[];
        final collector = next.collector(statuses);
        collector.start();
        await tester.pump();
        await tester.pump(const Duration(days: 1));
        expect(next.requests, 0);
        expect(next.peers, isEmpty);
        expect(statuses, contains('auth_retry_exhausted'));
        restarted.dispose();
        await collector.stop();
        await tester.pump();
      },
    );
  }
  for (final code in [4001, 4002]) {
    testWidgets(
      'missing/malformed credential $code blocks immediately and survives restart',
      (tester) async {
        final h = Harness(tester.binding.clock.now, JianAuthRetryPolicy());
        final service = h.service();
        service.connect();
        await tester.pump();
        h.peers.single.reject(code);
        await tester.pump();
        await tester.pump(const Duration(days: 1));
        expect(h.requests, 1);
        expect((await h.policy.read('rt_controlled')).blocked, isTrue);
        service.dispose();
        await tester.pump();
        final restarted = h.service();
        restarted.connect();
        await tester.pump();
        expect(h.requests, 1);
        restarted.dispose();
        await tester.pump();
      },
    );
  }
  testWidgets(
    'upgrade/heartbeat/error cannot reset failures; accepted all frame does',
    (tester) async {
      final policy = JianAuthRetryPolicy();
      final h = Harness(tester.binding.clock.now, policy);
      final service = h.service();
      service.connect();
      await tester.pump();
      h.peers.last.reject(4003);
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect((await policy.read('rt_controlled')).failures, 1);
      h.peers.last.frames.add('{"type":"heartbeat"}');
      await tester.pump();
      expect((await policy.read('rt_controlled')).failures, 1);
      h.peers.last.reject(4004);
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect((await policy.read('rt_controlled')).failures, 2);
      h.peers.last.frames.add('{"type":"all"}');
      await tester.pump();
      expect((await policy.read('rt_controlled')).failures, 0);
      h.peers.last.reject(4004);
      await tester.pump();
      expect((await policy.read('rt_controlled')).failures, 1);
      service.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'explicit credential save grants one delayed attempt, then stops on rejection',
    (tester) async {
      final policy = JianAuthRetryPolicy();
      final now = tester.binding.clock.now();
      for (var i = 0; i < 3; i++) {
        await policy.rejected('rt_controlled', 'invalid_api_key', now);
      }
      final h = Harness(tester.binding.clock.now, policy);
      final service = h.service();
      service.connect();
      await tester.pump();
      expect(h.requests, 0);
      service.reloadCredentials();
      await tester.pump();
      expect(h.requests, 0);
      await tester.pump(const Duration(minutes: 5));
      expect(h.requests, 1);
      h.peers.single.reject(4004);
      await tester.pump();
      await tester.pump(const Duration(days: 1));
      expect(h.requests, 1);
      expect(service.credentialInfo.errorCode, 'auth_retry_exhausted');
      service.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'replacement RT has its own budget and does not reuse a blocked RT',
    (tester) async {
      final policy = JianAuthRetryPolicy();
      for (var i = 0; i < 3; i++) {
        await policy.rejected(
          'rt_controlled',
          'invalid_api_key',
          tester.binding.clock.now(),
        );
      }
      await JianCredentialStore().write('rt_replacement');
      final h = Harness(tester.binding.clock.now, policy);
      final service = h.service();
      service.connect();
      await tester.pump();
      expect(h.requests, 1);
      expect(h.peers, hasLength(1));
      expect((await policy.read('rt_controlled')).blocked, isTrue);
      service.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'collector also stops at three rejections and cannot restart with same RT',
    (tester) async {
      final policy = JianAuthRetryPolicy();
      final h = Harness(tester.binding.clock.now, policy);
      final statuses = <String>[];
      final collector = h.collector(statuses);
      collector.start();
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        h.peers.last.reject(i == 1 ? 4003 : 4004);
        await tester.pump();
        await tester.pump(const Duration(minutes: 5));
      }
      expect(h.requests, 3);
      expect(statuses.last, 'auth_retry_exhausted');
      await collector.stop();
      await tester.pump();
      final restarted = h.collector(statuses);
      restarted.start();
      await tester.pump();
      await tester.pump(const Duration(days: 1));
      expect(h.requests, 3);
      await restarted.stop();
      await tester.pump();
    },
  );
  testWidgets(
    'retry storage failure prevents app and collector from connecting',
    (tester) async {
      final h = Harness(
        tester.binding.clock.now,
        JianAuthRetryPolicy(store: BrokenRetryStore()),
      );
      final service = h.service();
      service.connect();
      await tester.pump();
      final statuses = <String>[];
      final collector = h.collector(statuses);
      collector.start();
      await tester.pump();
      await tester.pump(const Duration(days: 1));
      expect(h.requests, 0);
      expect(service.credentialInfo.errorCode, 'retry_storage');
      expect(statuses, contains('retry_storage'));
      service.dispose();
      await collector.stop();
      await tester.pump();
    },
  );
  test(
    'durable file survives store recreation, redacts credentials and preserves corrupt bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'jian_retry_test_',
      );
      try {
        final path = '${directory.path}/retry.json';
        final policy = JianAuthRetryPolicy(
          store: FileConnectionRetryStore(path: path),
        );
        final now = DateTime.utc(2026, 10, 18);
        for (var i = 0; i < 3; i++) {
          await policy.rejected(
            'rt_private_controlled',
            'expired_access_token',
            now,
          );
        }
        final reloaded = JianAuthRetryPolicy(
          store: FileConnectionRetryStore(path: path),
        );
        expect((await reloaded.read('rt_private_controlled')).blocked, isTrue);
        expect((await reloaded.read('rt_private_controlled')).failures, 3);
        final file = File(path);
        expect(
          await file.readAsString(),
          isNot(contains('rt_private_controlled')),
        );
        await reloaded.accepted('rt_private_controlled', 0);
        expect((await reloaded.read('rt_private_controlled')).blocked, isTrue);
        await reloaded.resume('rt_private_controlled');
        await reloaded.resume('rt_private_controlled');
        expect((await reloaded.read('rt_private_controlled')).failures, 2);
        final original = utf8.encode('controlled corrupt metadata');
        await file.writeAsBytes(original);
        await expectLater(
          reloaded.read('rt_private_controlled'),
          throwsA(isA<FormatException>()),
        );
        expect(await file.readAsBytes(), original);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test('old accepted session cannot erase a newer rejection', () async {
    final policy = JianAuthRetryPolicy();
    final original = await policy.read('rt_controlled');
    await policy.rejected(
      'rt_controlled',
      'invalid_api_key',
      DateTime.utc(2026),
    );
    await policy.accepted('rt_controlled', original.revision);
    expect((await policy.read('rt_controlled')).failures, 1);
  });
}
