import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterrhythmquake/services/wauth_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('builds an OAuth authorization URI with PKCE parameters', () async {
    final service = WAuthService();
    final pkce = await service.createPkcePair();
    final uri = service.buildAuthorizationUri(
      redirectUri: 'https://example.com/callback',
      state: 'state-1',
      nonce: 'nonce-1',
      codeChallenge: pkce.challenge,
    );

    expect(uri.toString(), startsWith(WAuthService.issuer));
    expect(uri.queryParameters['response_type'], 'code');
    expect(uri.queryParameters['client_id'], WAuthService.defaultClientId);
    expect(uri.queryParameters['redirect_uri'], 'https://example.com/callback');
    expect(uri.queryParameters['scope'], 'openid profile email');
    expect(uri.queryParameters['state'], 'state-1');
    expect(uri.queryParameters['nonce'], 'nonce-1');
    expect(uri.queryParameters['code_challenge'], pkce.challenge);
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(pkce.verifier, isNot(contains('=')));
  });

  test('parses successful and failed callbacks', () {
    final service = WAuthService();
    final success = service.parseCallback(
      Uri.parse('https://example.com/callback?code=abc&state=s1'),
    );
    final failure = service.parseCallback(
      Uri.parse('https://example.com/callback?error=access_denied&state=s1'),
    );

    expect(success.isSuccess, isTrue);
    expect(success.code, 'abc');
    expect(success.state, 's1');
    expect(failure.isSuccess, isFalse);
    expect(failure.error, 'access_denied');
  });

  test(
    'exchanges an authorization code without persisting the secret',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'access_token': 'access-token',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'scope': 'openid profile',
            'id_token': 'id-token',
          }),
          200,
        );
      });
      final service = WAuthService(client: client, clientId: 'client-id');

      final token = await service.exchangeAuthorizationCode(
        code: 'auth-code',
        redirectUri: 'https://example.com/callback',
        codeVerifier: 'verifier',
        clientSecret: 'runtime-only-secret',
      );

      expect(token.accessToken, 'access-token');
      expect(captured.method, 'POST');
      expect(captured.url.path, WAuthService.tokenPath);
      expect(captured.bodyFields['grant_type'], 'authorization_code');
      expect(captured.bodyFields['code_verifier'], 'verifier');
      expect(captured.headers['authorization'], startsWith('Basic '));
    },
  );

  test(
    'fetches user information through the gateway with a Bearer token',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'sub': '72'}), 200);
      });
      final service = WAuthService(
        client: client,
        gatewayBaseUrl: 'https://gateway.test',
      );

      final user = await service.fetchUserInfo('access-token');

      expect(user['sub'], '72');
      expect(captured.method, 'GET');
      expect(captured.url.host, 'gateway.test');
      expect(captured.url.path, WAuthService.gatewayUserInfoPath);
      expect(captured.headers['authorization'], 'Bearer access-token');
    },
  );

  test('creates a gateway session with state and PKCE fields', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['state'], isA<String>());
      expect(body['code_challenge'], isA<String>());
      expect(body['code_verifier'], isA<String>());
      return http.Response(
        jsonEncode({
          'status': 'ready',
          'authorizationUrl': 'https://auth.test/authorize',
          'expiresIn': 600,
        }),
        200,
      );
    });
    final service = WAuthService(
      client: client,
      gatewayBaseUrl: 'https://gateway.test',
    );

    final session = await service.createGatewaySession();

    expect(captured.url.toString(), 'https://gateway.test/wauth/session');
    expect(captured.headers['content-type'], contains('application/json'));
    expect(session.authorizationUri.toString(), 'https://auth.test/authorize');
    expect(session.state, isNotEmpty);
    expect(session.codeVerifier, isNotEmpty);
  });

  test('polls pending gateway result and returns the official token', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      expect(request.url.queryParameters['state'], 'state-1');
      if (calls == 1) {
        return http.Response(jsonEncode({'status': 'pending'}), 202);
      }
      return http.Response(
        jsonEncode({
          'status': 'complete',
          'token': {
            'access_token': 'official-access-token',
            'api_token': 'official-api-token',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'scope': 'openid profile',
            'id_token': 'id-token',
          },
          'userinfo': {'sub': '72', 'name': 'Rhythm'},
        }),
        200,
      );
    });
    final service = WAuthService(
      client: client,
      gatewayBaseUrl: 'https://gateway.test',
    );

    final result = await service.waitForGatewayResult(
      state: 'state-1',
      timeout: const Duration(seconds: 1),
      pollInterval: Duration.zero,
    );

    expect(calls, 2);
    expect(result.token.accessToken, 'official-access-token');
    expect(result.token.apiToken, 'official-api-token');
    expect(result.token.tokenType, 'Bearer');
    expect(result.userInfo, {'sub': '72', 'name': 'Rhythm'});
  });

  test(
    'keeps the same authorization after transient polling failures',
    () async {
      var calls = 0;
      final service = WAuthService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.queryParameters['state'], 'same-attempt');
          calls++;
          if (calls == 1) {
            throw http.ClientException('Connection reset by peer');
          }
          if (calls == 2) throw TimeoutException('temporary timeout');
          if (calls == 3) return http.Response('<html>Bad Gateway</html>', 502);
          if (calls == 4) return http.Response('{"status":"pending"}', 202);
          return http.Response(
            jsonEncode({
              'token': {'access_token': 'test-access', 'api_token': 'test-api'},
              'userinfo': {'sub': 'test-user'},
            }),
            200,
          );
        }),
      );
      addTearDown(service.close);

      final result = await service.waitForGatewayResult(
        state: 'same-attempt',
        timeout: const Duration(seconds: 1),
        pollInterval: Duration.zero,
      );
      expect(calls, 5);
      expect(result.token.apiToken, 'test-api');
    },
  );

  for (final status in [401, 403, 410]) {
    test(
      'does not retry a rejected or consumed authorization: $status',
      () async {
        var calls = 0;
        final service = WAuthService(
          client: MockClient((_) async {
            calls++;
            return http.Response(
              '{"error":"authorization_unavailable"}',
              status,
            );
          }),
        );
        addTearDown(service.close);
        await expectLater(
          service.waitForGatewayResult(
            state: 'attempt',
            pollInterval: Duration.zero,
          ),
          throwsA(
            isA<WAuthApiException>().having(
              (e) => e.statusCode,
              'status',
              status,
            ),
          ),
        );
        expect(calls, 1);
      },
    );
  }

  test(
    'continuous network failure ends at the authorization deadline',
    () async {
      var calls = 0;
      final service = WAuthService(
        client: MockClient((_) async {
          calls++;
          throw http.ClientException('offline');
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.waitForGatewayResult(
          state: 'attempt',
          timeout: const Duration(milliseconds: 25),
          pollInterval: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<WAuthApiException>().having((e) => e.statusCode, 'status', 408),
        ),
      );
      expect(calls, greaterThan(0));
      expect(calls, lessThanOrEqualTo(3));
    },
  );

  test('closing the service does not retry a failed polling request', () async {
    var calls = 0;
    late WAuthService service;
    service = WAuthService(
      client: MockClient((_) async {
        calls++;
        service.close();
        throw http.ClientException('closed');
      }),
    );
    await expectLater(
      service.waitForGatewayResult(
        state: 'attempt',
        pollInterval: Duration.zero,
      ),
      throwsA(isA<WAuthApiException>()),
    );
    expect(calls, 1);
  });

  test('rejects a gateway result without an official access token', () {
    expect(
      () => WAuthGatewayResult.fromJson({
        'status': 'complete',
        'token': {'token_type': 'Bearer'},
        'userinfo': {'sub': '72'},
      }),
      throwsFormatException,
    );
  });

  test('requires an official access token before protected API use', () async {
    final service = WAuthService(
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    await expectLater(
      service.requireAuthorizedAccessToken(null),
      throwsA(
        isA<WAuthApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('cached userinfo alone cannot enable a protected API', () async {
    SharedPreferences.setMockInitialValues({
      WAuthService.userInfoPreferenceKey: jsonEncode({
        'sub': '72',
        'name': 'Rhythm',
      }),
    });
    final service = WAuthService(
      client: MockClient((_) async {
        fail('WAuth userinfo must not be called without an access token.');
      }),
    );

    await expectLater(
      service.requireStoredAuthorizedAccessToken(),
      throwsA(
        isA<WAuthApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('verifies an access token through the WAuth gateway', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'sub': '72', 'name': 'Rhythm'}), 200);
    });
    final service = WAuthService(
      client: client,
      gatewayBaseUrl: 'https://gateway.test',
    );

    final authorized = await service.requireAuthorizedAccessToken(
      'official-access-token',
    );

    expect(
      captured.url.toString(),
      'https://gateway.test${WAuthService.gatewayUserInfoPath}',
    );
    expect(captured.headers['authorization'], 'Bearer official-access-token');
    expect(authorized.accessToken, 'official-access-token');
    expect(authorized.userInfo['sub'], '72');
  });

  test('stored access token is verified before protected API use', () async {
    SharedPreferences.setMockInitialValues({
      WAuthService.accessTokenPreferenceKey: 'stored-access-token',
    });
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'sub': '72'}), 200);
    });
    final service = WAuthService(
      client: client,
      gatewayBaseUrl: 'https://gateway.test',
    );

    final authorized = await service.requireStoredAuthorizedAccessToken();

    expect(captured.headers['authorization'], 'Bearer stored-access-token');
    expect(authorized.userInfo['sub'], '72');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(WAuthService.accessTokenPreferenceKey), isFalse);
  });

  test('official userinfo rejection keeps protected API disabled', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': 'invalid_token',
          'message': 'WAuth login is no longer valid',
        }),
        401,
      );
    });
    final service = WAuthService(
      client: client,
      gatewayBaseUrl: 'https://gateway.test',
    );

    await expectLater(
      service.requireAuthorizedAccessToken('expired-access-token'),
      throwsA(
        isA<WAuthApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.message,
              'message',
              'WAuth login is no longer valid',
            ),
      ),
    );
  });

  test('verifies an official API token and returns claims', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'valid': true,
          'app_id': 'wauth-client-id',
          'user_id': 72,
          'username': 'Rhythm',
          'role': 'developer',
        }),
        200,
      );
    });
    final service = WAuthService(
      client: client,
      gatewayBaseUrl: 'https://gateway.test',
    );

    final verified = await service.requireAuthorizedApiToken(
      'official-api-token',
    );

    expect(captured.method, 'POST');
    expect(captured.url.host, 'gateway.test');
    expect(captured.url.path, WAuthService.gatewayVerifyApiTokenPath);
    expect(captured.headers['authorization'], 'Bearer official-api-token');
    expect(verified.claims['valid'], isTrue);
    expect(verified.claims['user_id'], 72);
  });

  test('does not accept a valid false API token response', () async {
    final service = WAuthService(
      client: MockClient(
        (_) async => http.Response(jsonEncode({'valid': false}), 200),
      ),
    );

    await expectLater(
      service.requireAuthorizedApiToken('invalid-api-token'),
      throwsA(
        isA<WAuthApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having(
              (error) => error.message,
              'message',
              'WAuth API token is invalid or expired.',
            ),
      ),
    );
  });

  test('stored API token is checked by the official verifier', () async {
    SharedPreferences.setMockInitialValues({
      WAuthService.apiTokenPreferenceKey: 'stored-api-token',
    });
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer stored-api-token');
      return http.Response(jsonEncode({'valid': true}), 200);
    });
    final service = WAuthService(client: client);

    final verified = await service.requireStoredAuthorizedApiToken();

    expect(verified.apiToken, 'stored-api-token');
    expect(verified.claims['valid'], isTrue);
  });

  test(
    'expired access token alone does not force forgetting a valid API login',
    () async {
      SharedPreferences.setMockInitialValues({
        WAuthService.accessTokenPreferenceKey: 'expired-access-token',
        WAuthService.apiTokenPreferenceKey: 'still-valid-api-token',
      });
      final client = MockClient((request) async {
        if (request.url.path == WAuthService.gatewayUserInfoPath) {
          return http.Response(jsonEncode({'error': 'invalid_token'}), 401);
        }
        expect(request.url.path, WAuthService.gatewayVerifyApiTokenPath);
        return http.Response(jsonEncode({'valid': true}), 200);
      });
      final service = WAuthService(client: client);

      final status = await service.inspectStoredAuthorization();

      expect(status.hasCredentials, isTrue);
      expect(status.accessAuthorized, isFalse);
      expect(status.accessRejected, isTrue);
      expect(status.apiAuthorized, isTrue);
      expect(status.apiRejected, isFalse);
      expect(status.shouldForgetLogin, isFalse);
    },
  );

  test(
    'network failure on API verify keeps cached login presentation',
    () async {
      SharedPreferences.setMockInitialValues({
        WAuthService.accessTokenPreferenceKey: 'access-token',
        WAuthService.apiTokenPreferenceKey: 'api-token',
        WAuthService.userInfoPreferenceKey: jsonEncode({'name': 'Rhythm'}),
      });
      final client = MockClient((request) async {
        if (request.url.path == WAuthService.gatewayUserInfoPath) {
          return http.Response(jsonEncode({'name': 'Rhythm'}), 200);
        }
        return http.Response(jsonEncode({'error': 'timeout'}), 408);
      });
      final service = WAuthService(client: client);

      final status = await service.inspectStoredAuthorization();

      expect(status.accessAuthorized, isTrue);
      expect(status.apiAuthorized, isFalse);
      expect(status.apiRejected, isFalse);
      expect(status.shouldForgetLogin, isFalse);
      expect(status.hasTransientVerificationFailure, isTrue);
      expect(status.keepsCachedLoginPresentation, isTrue);
    },
  );

  test('API-only stored credentials can be verified', () async {
    SharedPreferences.setMockInitialValues({
      WAuthService.apiTokenPreferenceKey: 'business-only',
    });
    final service = WAuthService(client: MockClient((request) async {
      expect(request.url.path, WAuthService.gatewayVerifyApiTokenPath);
      return http.Response(jsonEncode({'valid': true}), 200);
    }));
    addTearDown(service.close);
    final status = await service.inspectStoredAuthorization();
    expect(status.hasCredentials, isTrue);
    expect(status.apiAuthorized, isTrue);
    expect(status.shouldForgetLogin, isFalse);
  });

  test('expired OAuth plus unavailable verifier preserves API token', () async {
    SharedPreferences.setMockInitialValues({
      WAuthService.accessTokenPreferenceKey: 'expired-account',
      WAuthService.apiTokenPreferenceKey: 'saved-business',
    });
    final service = WAuthService(client: MockClient((request) async {
      return http.Response('{}',
        request.url.path == WAuthService.gatewayUserInfoPath ? 401 : 503);
    }));
    addTearDown(service.close);
    final status = await service.inspectStoredAuthorization();
    expect(status.accessRejected, isTrue);
    expect(status.hasTransientVerificationFailure, isTrue);
    expect(status.shouldForgetLogin, isFalse);
    expect((await service.credentialStore.readAndMigrate()).apiToken,
      'saved-business');
  });

  test('rejected API token forces forgetting saved login', () async {
    SharedPreferences.setMockInitialValues({
      WAuthService.accessTokenPreferenceKey: 'access-token',
      WAuthService.apiTokenPreferenceKey: 'dead-api-token',
    });
    final client = MockClient((request) async {
      if (request.url.path == WAuthService.gatewayUserInfoPath) {
        return http.Response(jsonEncode({'sub': '72'}), 200);
      }
      return http.Response(jsonEncode({'valid': false}), 200);
    });
    final service = WAuthService(client: client);

    final status = await service.inspectStoredAuthorization();

    expect(status.accessAuthorized, isTrue);
    expect(status.apiAuthorized, isFalse);
    expect(status.apiRejected, isTrue);
    expect(status.shouldForgetLogin, isTrue);
  });

  test('gateway requests time out instead of leaving login pending', () async {
    final service = WAuthService(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      }),
      gatewayBaseUrl: 'https://gateway.test',
      requestTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      service.createGatewaySession(),
      throwsA(
        isA<WAuthApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          408,
        ),
      ),
    );
  });
}
