import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/services/jian_auth_service.dart';
import 'package:flutterrhythmquake/services/sources/jian_service.dart';
import 'package:flutterrhythmquake/services/sources/source_manager.dart';
import 'package:flutterrhythmquake/models/source_status.dart';
import 'package:flutterrhythmquake/models/source_credential_info.dart';
import 'jian_integration_test.dart' show FakeChannel;

// Non-working, controlled protocol inputs. Never use personal credentials here.
http.Response ticket(String token, {bool refresh = false}) => http.Response(
  jsonEncode({
    'ok': true,
    'token': token,
    refresh ? 'expires_after_min' : 'expires_after_sec': 60,
    'max_connections': 3,
  }),
  200,
);

class BrokenStore extends JianCredentialStore {
  @override
  Future<JianCredential> readCredential() async =>
      throw StateError('sensitive storage detail');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'exchange is bodyless, header-only and never follows redirects',
    () async {
      final calls = <http.Request>[];
      final auth = JianAuthService(
        client: MockClient((request) async {
          calls.add(request);
          return request.url.path.endsWith('refresh')
              ? ticket('rt_test', refresh: true)
              : ticket('at_test');
        }),
      );
      addTearDown(auth.close);
      expect(await auth.exchangeLoginKey('lk_test'), 'rt_test');
      expect(await auth.accessToken('rt_test'), 'at_test');
      expect(calls.map((r) => r.url.path), ['/api/refresh', '/api/access']);
      for (final request in calls) {
        expect(request.url.host, 'auth.sismotide.top');
        expect(request.url.query, isEmpty);
        expect(request.method, 'POST');
        expect(request.body, isEmpty);
        expect(request.followRedirects, isFalse);
      }
      expect(calls.first.headers['Authorization'], 'Bearer lk_test');
      expect(calls.last.headers['Authorization'], 'Bearer rt_test');
    },
  );

  test('secure storage persists only rt and never preferences', () async {
    final store = JianCredentialStore();
    await store.write('rt_test');
    expect(await JianCredentialStore().read(), 'rt_test');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    await expectLater(
      store.write('at_test'),
      throwsA(isA<JianAuthException>()),
    );
    expect(await store.read(), 'rt_test');
    await store.clear();
    expect(await store.read(), isEmpty);
  });

  test(
    'server lifetime is preserved atomically; legacy and imported tokens stay unknown',
    () async {
      final now = DateTime.utc(2026, 9, 21, 12);
      final auth = JianAuthService(
        now: () => now,
        client: MockClient((_) async => ticket('rt_test', refresh: true)),
      );
      addTearDown(auth.close);
      final credential = await auth.exchangeLoginKeyCredential('lk_test');
      expect(credential.expiresAt, now.add(const Duration(minutes: 60)));
      final store = JianCredentialStore();
      await store.write(credential.token, expiresAt: credential.expiresAt);
      expect(await store.read(), 'rt_test');
      expect(
        (await JianCredentialStore().readCredential()).expiresAt,
        credential.expiresAt,
      );
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await store.write('rt_imported');
      expect((await store.readCredential()).expiresAt, isNull);
      await store.clear();
      final cleared = await store.readCredential();
      expect(cleared.token, isEmpty);
      expect(cleared.expiresAt, isNull);
    },
  );

  test(
    'unknown server errors, transport exceptions and invalid success are sanitized',
    () async {
      for (final client in [
        MockClient(
          (_) async => http.Response(
            '{"ok":false,"error":"rt_secret","message":"at_secret"}',
            401,
          ),
        ),
        MockClient((_) async => throw http.ClientException('rt_secret')),
        MockClient((_) async => ticket('rt_wrong_kind')),
        MockClient((_) async => http.Response('<html>at_secret</html>', 302)),
      ]) {
        final auth = JianAuthService(client: client);
        try {
          await auth.accessToken('rt_test');
          fail('must reject');
        } on JianAuthException catch (error) {
          expect(error.toString(), isNot(contains('secret')));
          expect(error.toString(), isNot(contains('rt_')));
        } finally {
          auth.close();
        }
      }
    },
  );

  testWidgets(
    'handshake uses at header; healthy socket outlives access token',
    (tester) async {
      await JianCredentialStore().write('rt_test');
      var exchanges = 0;
      final channels = <FakeChannel>[];
      final requests = <(Uri, Map<String, dynamic>?)>[];
      final service = JianService(
        now: tester.binding.clock.now,
        authService: JianAuthService(
          client: MockClient((_) async => ticket('at_test${++exchanges}')),
        ),
        socketFactory: (uri, {headers}) {
          requests.add((uri, headers));
          final channel = FakeChannel();
          channels.add(channel);
          return channel;
        },
      );
      addTearDown(service.dispose);
      service.connect();
      await tester.pump();
      expect(service.authStatus, JianAuthStatus.authenticated);
      expect(requests.single.$1.toString(), 'wss://api.sismotide.top/all');
      expect(requests.single.$2, {'Authorization': 'Bearer at_test1'});
      for (var i = 0; i < 5; i++) {
        channels.first.frames.add('{"type":"heartbeat"}');
        await tester.pump();
        await tester.pump(const Duration(seconds: 30));
      }
      expect(channels, hasLength(1));
      expect(exchanges, 1);
      expect(
        channels.first.sent.every((v) => !v.toString().contains('at_')),
        isTrue,
      );
      unawaited(channels.first.frames.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 45));
      expect(channels, hasLength(2));
      expect(exchanges, 2);
      expect(service.authStatus, JianAuthStatus.authenticated);
      service.dispose();
    },
  );

  testWidgets('expired rt pauses retries with no anonymous downgrade', (
    tester,
  ) async {
    await JianCredentialStore().write('rt_test');
    var exchanges = 0;
    var opens = 0;
    final service = JianService(
      now: tester.binding.clock.now,
      authService: JianAuthService(
        client: MockClient((_) async {
          exchanges++;
          return http.Response(
            '{"ok":false,"error":"expired_refresh_token","code":4202}',
            401,
          );
        }),
      ),
      socketFactory: (_, {headers}) {
        opens++;
        return FakeChannel();
      },
    );
    service.connect();
    await tester.pump();
    expect(service.authStatus, JianAuthStatus.invalid);
    expect(service.connectionStatus, SourceStatus.error);
    await tester.pump(const Duration(hours: 2));
    expect(opens, 0);
    expect(exchanges, 1);
    expect(await JianCredentialStore().read(), 'rt_test');
    service.dispose();
  });

  testWidgets(
    'missing credential never opens or retries; configuring resumes',
    (tester) async {
      var exchanges = 0;
      final channels = <FakeChannel>[];
      final headersSeen = <Map<String, dynamic>?>[];
      final service = JianService(
        now: tester.binding.clock.now,
        authService: JianAuthService(
          client: MockClient((_) async {
            exchanges++;
            return ticket('at_test');
          }),
        ),
        socketFactory: (_, {headers}) {
          headersSeen.add(headers);
          final channel = FakeChannel();
          channels.add(channel);
          return channel;
        },
      );
      addTearDown(service.dispose);
      service.connect();
      await tester.pump();
      expect(service.authStatus, JianAuthStatus.unconfigured);
      expect(service.connectionStatus, SourceStatus.error);
      expect(service.credentialInfo.configured, isFalse);
      expect(service.lastError, contains('请先配置'));
      await tester.pump(const Duration(hours: 2));
      expect(channels, isEmpty);
      expect(exchanges, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(JianService.retryAfterPreferenceKey), isNull);

      await JianCredentialStore().write('rt_test');
      service.reloadCredentials();
      await tester.pump();
      expect(headersSeen, [
        {'Authorization': 'Bearer at_test'},
      ]);
      expect(service.authStatus, JianAuthStatus.authenticated);
      expect(channels, hasLength(1));
      expect(exchanges, 1);

      await JianCredentialStore().clear();
      service.reloadCredentials();
      await tester.pump();
      expect(service.authStatus, JianAuthStatus.unconfigured);
      await tester.pump(const Duration(hours: 2));
      expect(channels, hasLength(1));
      expect(exchanges, 1);
      service.dispose();
    },
  );

  testWidgets('concurrency rejection waits five minutes before a new ticket', (
    tester,
  ) async {
    await JianCredentialStore().write('rt_test');
    var exchanges = 0;
    final channels = <FakeChannel>[];
    final service = JianService(
      now: tester.binding.clock.now,
      authService: JianAuthService(
        client: MockClient((_) async => ticket('at_test${++exchanges}')),
      ),
      socketFactory: (_, {headers}) {
        final channel = FakeChannel();
        channels.add(channel);
        return channel;
      },
    );
    addTearDown(service.dispose);
    service.connect();
    await tester.pump();
    channels.single.frames.add('{"ok":false,"error":"conn_limit","code":4005}');
    await tester.pump();
    expect(service.credentialInfo.errorCode, 'conn_limit');
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(channels, hasLength(1));
    expect(exchanges, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(channels, hasLength(2));
    expect(exchanges, 2);
    service.dispose();
  });

  testWidgets('disable while exchanging cannot start a socket', (tester) async {
    await JianCredentialStore().write('rt_test');
    final pending = Completer<http.Response>();
    var opens = 0;
    final service = JianService(
      authService: JianAuthService(client: MockClient((_) => pending.future)),
      socketFactory: (_, {headers}) {
        opens++;
        return FakeChannel();
      },
    );
    service.connect();
    await tester.pump();
    service.disconnect();
    pending.complete(ticket('at_test'));
    await tester.pump();
    expect(opens, 0);
    expect(service.connectionStatus, SourceStatus.disconnected);
    service.dispose();
  });

  testWidgets(
    'storage failure is closed, and new auth error envelope is handled',
    (tester) async {
      var opens = 0;
      final failed = JianService(
        credentialStore: BrokenStore(),
        socketFactory: (_, {headers}) {
          opens++;
          return FakeChannel();
        },
      );
      failed.connect();
      await tester.pump();
      expect(opens, 0);
      expect(failed.authStatus, JianAuthStatus.invalid);
      expect(failed.lastError, isNot(contains('sensitive')));
      failed.dispose();
      SharedPreferences.setMockInitialValues({});
      await JianCredentialStore().write('rt_test');
      final channel = FakeChannel();
      final service = JianService(
        authService: JianAuthService(
          client: MockClient((_) async => ticket('at_test')),
        ),
        socketFactory: (_, {headers}) => channel,
      );
      service.connect();
      await tester.pump();
      expect(service.authStatus, JianAuthStatus.authenticated);
      channel.frames.add(
        '{"ok":false,"error":"account_banned","code":4006,"message":"rt_secret"}',
      );
      await tester.pump();
      expect(service.authStatus, JianAuthStatus.invalid);
      expect(service.lastError, isNot(contains('rt_secret')));
      await tester.pump(const Duration(hours: 1));
      service.dispose();
    },
  );

  testWidgets('source manager forwards actual authentication transitions', (
    tester,
  ) async {
    final expiry = DateTime.utc(2027, 1, 1);
    await JianCredentialStore().write('rt_test', expiresAt: expiry);
    final service = JianService(
      authService: JianAuthService(
        client: MockClient((_) async => ticket('at_test')),
      ),
      socketFactory: (_, {headers}) => FakeChannel(),
    );
    final manager = SourceManager();
    manager.reset();
    final statuses = <SourceStatusUpdate>[];
    final subscription = manager.onStatusUpdate.listen(statuses.add);
    addTearDown(() async {
      service.dispose();
      manager.reset();
      await subscription.cancel();
    });
    manager.registerSource(service);
    service.connect();
    await tester.pump();
    expect(statuses.last.status, SourceStatus.connected);
    expect(statuses.last.authenticationStatus, 'authenticated');
    expect(statuses.last.credentialInfo?.expiresAt, expiry);
    expect(statuses.last.credentialInfo?.configured, isTrue);
    final payload = statuses.last.credentialInfo!.toMap();
    expect(
      payload.keys,
      unorderedEquals(['configured', 'expiresAt', 'errorCode']),
    );
    expect(jsonEncode(payload), isNot(contains('rt_test')));
    expect(SourceCredentialInfo.fromMap(payload), statuses.last.credentialInfo);
    expect(
      statuses.map((s) => s.authenticationStatus),
      contains('authenticating'),
    );
    service.disconnect();
    await tester.pump();
    expect(statuses.last.status, SourceStatus.disconnected);
    expect(statuses.last.authenticationStatus, 'anonymous');
  });

  testWidgets(
    'transient failure cools down and retries with the saved credential',
    (tester) async {
      await JianCredentialStore().write('rt_test');
      var exchanges = 0;
      var opens = 0;
      final service = JianService(
        now: tester.binding.clock.now,
        authService: JianAuthService(
          client: MockClient(
            (_) async => ++exchanges == 1
                ? http.Response('unavailable', 503)
                : ticket('at_test'),
          ),
        ),
        socketFactory: (_, {headers}) {
          opens++;
          return FakeChannel();
        },
      );
      addTearDown(service.dispose);
      service.connect();
      await tester.pump();
      expect(opens, 0);
      expect(service.authStatus, JianAuthStatus.unavailable);
      expect(service.credentialInfo.errorCode, 'server');
      await tester.pump(const Duration(minutes: 4));
      expect(exchanges, 1);
      await tester.pump(const Duration(minutes: 1));
      expect(exchanges, 2);
      expect(opens, 1);
      expect(service.authStatus, JianAuthStatus.authenticated);
      expect(service.credentialInfo.errorCode, isNull);
      expect(await JianCredentialStore().read(), 'rt_test');
      service.dispose();
    },
  );

  testWidgets(
    'credential reload discards a pending old ticket and honors spacing',
    (tester) async {
      await JianCredentialStore().write('rt_old');
      final pending = Completer<http.Response>();
      final headersSeen = <String?>[];
      final socketHeaders = <Map<String, dynamic>?>[];
      final service = JianService(
        now: tester.binding.clock.now,
        authService: JianAuthService(
          client: MockClient((request) {
            headersSeen.add(request.headers['Authorization']);
            return headersSeen.length == 1
                ? pending.future
                : Future.value(ticket('at_new'));
          }),
        ),
        socketFactory: (_, {headers}) {
          socketHeaders.add(headers);
          return FakeChannel();
        },
      );
      addTearDown(service.dispose);
      service.connect();
      await tester.pump();
      await JianCredentialStore().write('rt_new');
      service.reloadCredentials();
      pending.complete(ticket('at_old'));
      await tester.pump();
      expect(socketHeaders, isEmpty);
      await tester.pump(const Duration(seconds: 45));
      expect(headersSeen, ['Bearer rt_old', 'Bearer rt_new']);
      expect(socketHeaders, [
        {'Authorization': 'Bearer at_new'},
      ]);
      service.dispose();
    },
  );

  testWidgets('socket failures keep credentials and report transport failure', (tester) async {
    final expiry = DateTime.utc(2026, 10, 1);
    await JianCredentialStore().write('rt_test', expiresAt: expiry);
    final channel = FakeChannel();
    final service = JianService(
      now: tester.binding.clock.now,
      authService: JianAuthService(client: MockClient((_) async => ticket('at_test'))),
      socketFactory: (_, {headers}) => channel,
    );
    addTearDown(service.dispose);
    service.connect();
    await tester.pump();
    expect(service.authStatus, JianAuthStatus.authenticated);
    channel.frames.addError(StateError('at_secret'));
    await tester.pump();
    expect(service.authStatus, JianAuthStatus.unavailable);
    expect(service.credentialInfo.errorCode, 'connection');
    expect(service.credentialInfo.expiresAt, expiry);
    expect(service.lastError, isNot(contains('secret')));
    expect(await JianCredentialStore().read(), 'rt_test');
    service.dispose();
  });
}
