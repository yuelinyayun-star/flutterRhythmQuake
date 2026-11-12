// Controlled authentication envelopes; no personal tokens or upstream requests.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/services/jian_auth_service.dart';
import 'package:flutterrhythmquake/services/jian_auth_retry_policy.dart';
import 'package:flutterrhythmquake/services/sources/jian_service.dart';
import 'jian_integration_test.dart' show FakeChannel;

http.Response response(Map<String, Object?> fields, {bool refresh = false}) =>
    http.Response(
      jsonEncode({
        'ok': true,
        'token': refresh ? 'rt_test' : 'at_test',
        refresh ? 'expires_after_min' : 'expires_after_sec': refresh
            ? 259200
            : 3600,
        ...fields,
      }),
      200,
    );

class ExpiryWriteFailureStore extends JianCredentialStore {
  @override
  Future<void> updateExpiry(String token, DateTime expiresAt) async =>
      throw StateError('controlled storage failure');
}

class PausingTicketAuth extends JianAuthService {
  PausingTicketAuth({required DateTime Function() now, required this.pause})
    : super(now: now, client: MockClient((_) async => response({})));
  final void Function() pause;
  bool paused = false;
  @override
  Future<JianCredential> accessTokenCredential(String token) async {
    final credential = await super.accessTokenCredential(token);
    if (!paused) { paused = true; pause(); }
    return credential;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 18);
  final expiry = DateTime.utc(2026, 11, 1, 12, 34, 56);
  setUp(() {
    JianAuthRetryPolicy.storeOverride = MemoryConnectionRetryStore();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      JianCredentialStore.storageKey: 'rt_test',
    });
  });

  for (final refresh in [true, false]) {
    Future<JianCredential> exchange(JianAuthService auth) => refresh
        ? auth.exchangeLoginKeyCredential('lk_test')
        : auth.accessTokenCredential('rt_test');

    test(
      'new ${refresh ? 'refresh' : 'access'} expiry prefers UTC Unix seconds',
      () async {
        final auth = JianAuthService(
          now: () => now,
          client: MockClient(
            (_) async => response({
              'refresh_expires_at': expiry.millisecondsSinceEpoch ~/ 1000,
              'refresh_expires_after_min': 1,
            }, refresh: refresh),
          ),
        );
        addTearDown(auth.close);
        final credential = await exchange(auth);
        expect(credential.refreshExpiresAt, expiry);
        expect(credential.refreshExpiresAt!.isUtc, isTrue);
        expect(
          credential.expiresAt,
          refresh ? expiry : now.add(const Duration(hours: 1)),
        );
      },
    );

    test(
      'new ${refresh ? 'refresh' : 'access'} remaining minutes are RT metadata',
      () async {
        final auth = JianAuthService(
          now: () => now,
          client: MockClient(
            (_) async => response({
              'refresh_expires_after_min': 123.5,
            }, refresh: refresh),
          ),
        );
        addTearDown(auth.close);
        final credential = await exchange(auth);
        final rtExpiry = now.add(const Duration(minutes: 123, seconds: 30));
        expect(credential.refreshExpiresAt, rtExpiry);
        expect(
          credential.expiresAt,
          refresh ? rtExpiry : now.add(const Duration(hours: 1)),
        );
      },
    );
  }

  test(
    'refresh accepts authoritative expiry without legacy duration',
    () async {
      final auth = JianAuthService(
        now: () => now,
        client: MockClient(
          (_) async => response({
            'refresh_expires_at': expiry.millisecondsSinceEpoch ~/ 1000,
            'expires_after_min': null,
          }, refresh: true),
        ),
      );
      addTearDown(auth.close);
      expect(
        (await auth.exchangeLoginKeyCredential('lk_test')).expiresAt,
        expiry,
      );
    },
  );

  test(
    'missing or malformed new fields never infer RT lifetime from AT',
    () async {
      for (final fields in <Map<String, Object?>>[
        {},
        {'refresh_expires_at': 'invalid', 'refresh_expires_after_min': -1},
      ]) {
        final auth = JianAuthService(
          now: () => now,
          client: MockClient((_) async => response(fields)),
        );
        final credential = await auth.accessTokenCredential('rt_test');
        expect(credential.refreshExpiresAt, isNull);
        expect(credential.expiresAt, now.add(const Duration(hours: 1)));
        auth.close();
      }
    },
  );

  test('expiry metadata cannot replace a different stored RT', () async {
    final store = JianCredentialStore();
    await store.write('rt_replacement');
    await store.updateExpiry('rt_test', expiry);
    expect((await store.readCredential()).token, 'rt_replacement');
    expect((await store.readCredential()).expiresAt, isNull);
  });

  test(
    'concurrent expiry update cannot overwrite a replacement credential',
    () async {
      final updating = JianCredentialStore().updateExpiry('rt_test', expiry);
      final replacing = JianCredentialStore().write('rt_replacement');
      await Future.wait([updating, replacing]);
      final saved = await JianCredentialStore().readCredential();
      expect(saved.token, 'rt_replacement');
      expect(saved.expiresAt, isNull);
    },
  );

  for (final failSave in [false, true]) {
    testWidgets(
      'access response updates dashboard metadata; save failure=$failSave',
      (tester) async {
        final store = failSave
            ? ExpiryWriteFailureStore()
            : JianCredentialStore();
        final channel = FakeChannel();
        Map<String, dynamic>? socketHeaders;
        final service = JianService(
          credentialStore: store,
          now: tester.binding.clock.now,
          authService: JianAuthService(
            client: MockClient(
              (_) async => response({
                'refresh_expires_at': expiry.millisecondsSinceEpoch ~/ 1000,
              }),
            ),
          ),
          socketFactory: (_, {headers}) {
            socketHeaders = headers;
            return channel;
          },
        );
        addTearDown(service.dispose);
        service.connect();
        await tester.pump();
        expect(socketHeaders, {'Authorization': 'Bearer at_test'});
        expect(service.authStatus, JianAuthStatus.authenticated);
        expect(service.credentialInfo.expiresAt, expiry);
        expect(
          (await store.readCredential()).expiresAt,
          failSave ? null : expiry,
        );
        expect((await store.readCredential()).token, 'rt_test');
        service.disconnect();
      },
    );
  }

  testWidgets('late response cannot save expiry after credentials reload', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var requests = 0;
    final service = JianService(
      now: tester.binding.clock.now,
      authService: JianAuthService(
        client: MockClient((_) {
          requests++;
          return pending.future;
        }),
      ),
      socketFactory: (_, {headers}) =>
          throw StateError('old request must not connect'),
    );
    addTearDown(service.dispose);
    service.connect();
    await tester.pump();
    final store = JianCredentialStore();
    await store.write('rt_replacement');
    service.reloadCredentials();
    await tester.pump();
    pending.complete(
      response({'refresh_expires_at': expiry.millisecondsSinceEpoch ~/ 1000}),
    );
    await tester.pump();
    expect(requests, 1);
    expect((await store.readCredential()).token, 'rt_replacement');
    expect((await store.readCredential()).expiresAt, isNull);
    service.disconnect();
  });
  testWidgets('expired AT after local pause never reaches a socket; retry obtains a new ticket', (tester) async {
    final start = tester.binding.clock.now();
    var offset = Duration.zero;
    DateTime clock() => tester.binding.clock.now().toUtc().add(offset);
    var opens = 0;
    final auth = PausingTicketAuth(now: clock, pause: () => offset = const Duration(hours: 2));
    final service = JianService(now: clock, authService: auth, socketFactory: (_, {headers}) { opens++; return FakeChannel(); });
    service.connect();
    await tester.pump();
    expect(tester.binding.clock.now(), start);
    expect(opens, 0);
    expect(service.credentialInfo.errorCode, 'expired_access_token');
    await tester.pump(const Duration(minutes: 5));
    expect(opens, 1);
    expect(service.authStatus, JianAuthStatus.authenticated);
    service.dispose(); await tester.pump();
  });

  testWidgets('known expired RT stops before requesting a ticket', (tester) async {
    var requests = 0, opens = 0;
    final now = tester.binding.clock.now().toUtc();
    await JianCredentialStore().write('rt_test', expiresAt: now.subtract(const Duration(seconds: 1)));
    final service = JianService(now: tester.binding.clock.now,
      authService: JianAuthService(client: MockClient((_) async { requests++; return response({}); })),
      socketFactory: (_, {headers}) { opens++; return FakeChannel(); });
    service.connect(); await tester.pump();
    await tester.pump(const Duration(hours: 1));
    expect(requests, 0); expect(opens, 0);
    expect(service.authStatus, JianAuthStatus.invalid);
    expect(service.credentialInfo.errorCode, 'expired_refresh_token');
    service.dispose(); await tester.pump();
  });

}
