// Isolated host/auth routing tests. Only original files supply business data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/services/native_jian_connection.dart';
import 'package:flutterrhythmquake/services/jian_auth_service.dart';
import 'package:flutterrhythmquake/services/jian_auth_retry_policy.dart';
import 'package:flutterrhythmquake/services/sources/jian_service.dart';
import 'package:flutterrhythmquake/services/sources/jian_station_service.dart';
import 'package:flutterrhythmquake/services/sources/whews_station_service.dart';
import 'package:flutterrhythmquake/services/collector/jian_collector_feed.dart';
import 'package:flutterrhythmquake/models/unified_quake_data.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/services/sources/native_websocket_channel.dart';
import 'package:flutterrhythmquake/services/sources/source_socket_error.dart';
import 'whews_authorization_policy_test.dart' show WhewsPeer;

class _Harness {
  DateTime now = DateTime.utc(2026, 11, 1);
  final authRequests = <http.Request>[];
  final sockets = <Uri>[];
  final socketHeaders = <Map<String, dynamic>>[];
  final peers = <WhewsPeer>[];
  bool failPrimaryAuth = false;
  http.Response? rejected;
  JianAuthService auth() => JianAuthService(
    now: () => now,
    client: MockClient((request) async {
      authRequests.add(request);
      if (rejected != null) {
        return rejected!;
      }
      if (failPrimaryAuth && request.url.host == 'auth.sismotide.top') {
        throw const SocketException('controlled auth outage');
      }
      return http.Response(
        jsonEncode({
          'ok': true,
          'token': request.url.host == 'auth.jianproject.cloud'
              ? 'at_backup_controlled'
              : 'at_primary_controlled',
          'expires_after_sec': 3600,
        }),
        200,
      );
    }),
  );
  WhewsPeer socket(Uri uri, {Map<String, dynamic>? headers}) {
    sockets.add(uri);
    socketHeaders.add(headers ?? {});
    final peer = WhewsPeer();
    peers.add(peer);
    return peer;
  }

  JianService service() =>
      JianService(now: () => now, authService: auth(), socketFactory: socket);
  Future<void> advance(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
    await tester.pump();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      JianCredentialStore.storageKey: 'rt_controlled',
    });
    JianAuthRetryPolicy.storeOverride = MemoryConnectionRetryStore();
  });
  test(
    'Rust selects a paired issuer, rejects unknown hosts, and releases every output',
    () {
      expect(NativeJianConnection.supported, isTrue);
      for (var index = 0; index < 2; index++) {
        final r =
            NativeJianConnection.prepare({
                  'op': 'endpoint',
                  'index': index,
                  'path': '/all',
                })
                as Map;
        expect(
          r['authHost'],
          index == 0 ? 'auth.sismotide.top' : 'auth.jianproject.cloud',
        );
        expect(r['needsAuth'], true);
        for (final path in ['/kmoni', '/s-net', '/kma-station']) {
          expect(
            (NativeJianConnection.prepare({
                  'op': 'endpoint',
                  'index': index,
                  'path': path,
                })
                as Map)['needsAuth'],
            false,
          );
        }
      }
      expect(
        () => NativeJianConnection.prepare({
          'op': 'authHost',
          'host': 'untrusted.invalid',
        }),
        throwsStateError,
      );
      expect(NativeJianConnection.outputs, 0);
    },
  );
  test(
    'aggregate switches both API and access issuer; Bearer AT is present on every handshake',
    () => fakeAsync((clock) {
      final h = _Harness();
      final service = h.service();
      final events = <UnifiedQuakeData>[];
      final sub = service.onUnifiedEvent.listen(events.add);
      service.connect();
      clock.flushMicrotasks();
      expect(h.sockets.single.host, 'api.sismotide.top');
      h.peers.single.closeCode = 1006;
      unawaited(h.peers.single.frames.close());
      clock.flushMicrotasks();
      h.now = h.now.add(const Duration(seconds: 45));
      clock.elapse(const Duration(seconds: 45));
      clock.flushMicrotasks();
      expect(h.authRequests.map((r) => r.url.host), [
        'auth.sismotide.top',
        'auth.jianproject.cloud',
      ]);
      expect(h.sockets.map((u) => u.host), [
        'api.sismotide.top',
        'api.jianproject.cloud',
      ]);
      expect(
        h.authRequests.every(
          (r) =>
              r.method == 'POST' &&
              r.url.path == '/api/access' &&
              r.headers['Authorization'] == 'Bearer rt_controlled' &&
              r.body.isEmpty,
        ),
        isTrue,
      );
      expect(h.socketHeaders.map((h) => h['Authorization']), [
        'Bearer at_primary_controlled',
        'Bearer at_backup_controlled',
      ]);
      expect(h.sockets.every((u) => u.query.isEmpty), isTrue);
      final raw = File('test/fixtures/jian/all.json').readAsStringSync();
      h.peers.last.frames.add(raw);
      clock.flushMicrotasks();
      expect(events, isNotEmpty);
      final original = jsonDecode(raw) as Map;
      expect(
        events.every(
          (e) => original.values.whereType<Map>().any(
            (v) => jsonEncode(v['Data']) == jsonEncode(e.sourcePayload),
          ),
        ),
        isTrue,
      );
      service.dispose();
      clock.flushMicrotasks();
      unawaited(sub.cancel());
      clock.flushMicrotasks();
      expect(NativeJianConnection.outputs, 0);
    }),
  );
  testWidgets(
    'primary access issuer unavailable switches to backup before any business socket opens',
    (tester) async {
      final h = _Harness()..failPrimaryAuth = true;
      final service = h.service();
      service.connect();
      await tester.pump();
      await tester.pump();
      expect(h.sockets, isEmpty);
      await h.advance(tester, const Duration(minutes: 5));
      expect(h.authRequests.map((r) => r.url.host), [
        'auth.sismotide.top',
        'auth.jianproject.cloud',
      ]);
      expect(h.sockets.single.host, 'api.jianproject.cloud');
      expect(
        h.socketHeaders.single['Authorization'],
        'Bearer at_backup_controlled',
      );
      service.dispose();
      await tester.pump();
    },
  );
  testWidgets(
    'backup native handshake actually sends its paired AT header and no credential business frames',
    (tester) async {
      final h = _Harness();
      late HttpServer server;
      StreamSubscription<HttpRequest>? listener;
      final peers = <WebSocket>[];
      final handshakes = <String?>[];
      final frames = <dynamic>[];
      NativeWebSocketChannel? channel;
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        listener = server.listen((request) async {
          handshakes.add(request.headers.value('Authorization'));
          expectSync(request.uri.query, isEmpty);
          final peer = await WebSocketTransformer.upgrade(request);
          peers.add(peer);
          peer.listen(frames.add);
          peer.add('{"type":"heartbeat"}');
        });
      });
      final service = JianService(
        now: () => h.now,
        authService: h.auth(),
        socketFactory: (uri, {headers}) {
          h.sockets.add(uri);
          if (uri.host == 'api.sismotide.top') {
            throw const SocketException('controlled primary outage');
          }
          return channel = NativeWebSocketChannel.connect(
            uri.replace(scheme: 'ws', host: '127.0.0.1', port: server.port),
            headers: headers,
          );
        },
      );
      try {
        service.connect();
        await tester.pump();
        await tester.pump();
        await h.advance(tester, const Duration(seconds: 45));
        for (
          var i = 0;
          i < 100 && service.connectionStatus != SourceStatus.connected;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(service.connectionStatus, SourceStatus.connected);
        expect(h.authRequests.last.url.host, 'auth.jianproject.cloud');
        expect(h.sockets.last.host, 'api.jianproject.cloud');
        expect(handshakes, ['Bearer at_backup_controlled']);
        await h.advance(tester, const Duration(seconds: 30));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(frames, isNotEmpty);
        expect(
          frames.every(
            (v) =>
                !v.toString().contains('at_') && !v.toString().contains('rt_'),
          ),
          isTrue,
        );
      } finally {
        service.dispose();
        await tester.pump();
        var closed = channel == null;
        if (channel != null) {
          unawaited(channel!.sink.done.then((_) => closed = true));
        }
        for (var i = 0; i < 100 && !closed; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(closed, isTrue);
        await tester.runAsync(() async {
          for (final peer in peers) {
            await peer.close();
          }
          await listener?.cancel();
          await server.close(force: true);
        });
      }
    },
  );
  testWidgets('HTTP authorization rejection never becomes a network failover', (
    tester,
  ) async {
    final h = _Harness();
    var opens = 0;
    final service = JianService(
      now: () => h.now,
      authService: h.auth(),
      socketFactory: (uri, {headers}) {
        opens++;
        throw SourceSocketException(
          'controlled authorization rejection',
          statusCode: 403,
        );
      },
    );
    service.connect();
    await tester.pump();
    await tester.pump();
    await h.advance(tester, const Duration(minutes: 10));
    expect(opens, 1);
    expect(service.activeEndpoint.host, 'api.sismotide.top');
    expect(service.credentialInfo.errorCode, 'handshake_rejected');
    service.dispose();
    await tester.pump();
  });
  for (final code in [
    'account_banned',
    'cooldown',
    'conn_limit',
    'invalid_refresh_token',
  ]) {
    testWidgets(
      '$code never changes API or issuer to bypass the auth decision',
      (tester) async {
        final h = _Harness()
          ..rejected = http.Response(
            jsonEncode({'ok': false, 'error': code}),
            403,
          );
        final service = h.service();
        service.connect();
        await tester.pump();
        await tester.pump();
        expect(h.sockets, isEmpty);
        await h.advance(tester, const Duration(minutes: 5));
        expect(
          h.authRequests.every((r) => r.url.host == 'auth.sismotide.top'),
          isTrue,
        );
        expect(service.activeEndpoint.host, 'api.sismotide.top');
        service.dispose();
        await tester.pump();
      },
    );
  }
  testWidgets(
    'collector pairs its backup issuer and keeps its existing five-minute cooldown',
    (tester) async {
      final h = _Harness();
      final feed = JianCollectorFeed(
        credential: 'rt_controlled',
        onEvent: (_) {},
        onStatus: (_) {},
        now: () => h.now,
        auth: h.auth(),
        socketFactory: h.socket,
      );
      feed.start();
      await tester.pump();
      h.peers.single.closeCode = 1006;
      await h.peers.single.frames.close();
      await tester.pump();
      await h.advance(tester, const Duration(minutes: 5));
      expect(h.sockets.last.host, 'api.jianproject.cloud');
      expect(h.authRequests.last.url.host, 'auth.jianproject.cloud');
      expect(
        h.socketHeaders.last['Authorization'],
        'Bearer at_backup_controlled',
      );
      final stop = feed.stop();
      await tester.pump();
      await stop;
    },
  );
  for (final kind in WhewsStationKind.values) {
    testWidgets(
      '$kind exempt station keeps its path without borrowing aggregate credentials',
      (tester) async {
        final h = _Harness();
        final station = JianStationService(
          kind: kind,
          socketFactory: (uri) => h.socket(uri),
        );
        station.start();
        await tester.pump();
        h.peers.single.closeCode = 1006;
        await h.peers.single.frames.close();
        await tester.pump();
        await h.advance(tester, const Duration(seconds: 15));
        expect(h.sockets.map((u) => u.host), [
          'api.sismotide.top',
          'api.jianproject.cloud',
        ]);
        expect(h.sockets.first.path, h.sockets.last.path);
        expect(h.socketHeaders.every((v) => v.isEmpty), isTrue);
        station.stop();
        await tester.pump();
        await station.closed;
      },
    );
  }
  testWidgets(
    'stopping aggregate cancels the pending failover and authentication exchange',
    (tester) async {
      final h = _Harness();
      final service = h.service();
      service.connect();
      await tester.pump();
      await tester.pump();
      h.peers.single.closeCode = 1006;
      await h.peers.single.frames.close();
      await tester.pump();
      service.disconnect();
      await h.advance(tester, const Duration(minutes: 10));
      expect(h.sockets, hasLength(1));
      expect(h.authRequests, hasLength(1));
      service.dispose();
      await tester.pump();
    },
  );
}
