import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'wauth_credential_store.dart';

/// WAuth OAuth/OIDC integration primitives.
///
/// The AppSecret must only be supplied by a trusted server when exchanging a
/// code for tokens. Official access and API tokens are handled by the caller
/// after the gateway returns them.
class WAuthService {
  static const String issuer = 'https://auth.beecld.com';
  static const String defaultClientId = 'wauth_49ad8dff5251645797672e5d';
  static const String gatewayBaseUrl = 'https://quake.yuelinrhythm.top';
  static const String defaultRedirectUri =
      'https://quake.yuelinrhythm.top/wauth/callback';

  static const String authorizePath = '/oauth2/authorize';
  static const String tokenPath = '/oauth2/token';
  static const String userInfoPath = '/oauth2/userinfo';
  static const String discoveryPath = '/.well-known/openid-configuration';
  static const String jwksPath = '/.well-known/jwks.json';
  static const String verifyApiTokenPath = '/api/token/verify';
  static const String gatewaySessionPath = '/wauth/session';
  static const String gatewayResultPath = '/wauth/result';
  static const String accessTokenPreferenceKey =
      WAuthCredentialStore.legacyAccessTokenPreferenceKey;
  static const String apiTokenPreferenceKey =
      WAuthCredentialStore.legacyApiTokenPreferenceKey;
  static const String legacySessionTokenPreferenceKey =
      'wauth_gateway_session_token';
  static const String userInfoPreferenceKey = 'wauth_user_info';

  final http.Client _client;
  final String clientId;
  final String gatewayBaseUrlValue;
  final Duration requestTimeout;
  final WAuthCredentialStore credentialStore;

  WAuthService({
    http.Client? client,
    this.clientId = defaultClientId,
    String? gatewayBaseUrl,
    this.requestTimeout = const Duration(seconds: 12),
    WAuthCredentialStore? credentialStore,
  }) : _client = client ?? http.Client(),
       credentialStore = credentialStore ?? WAuthCredentialStore(),
       gatewayBaseUrlValue = gatewayBaseUrl ?? WAuthService.gatewayBaseUrl;

  void close() => _client.close();

  Uri buildAuthorizationUri({
    required String redirectUri,
    required String state,
    required String codeChallenge,
    String? nonce,
    String scope = 'openid profile email',
  }) {
    final trimmedRedirectUri = redirectUri.trim();
    if (trimmedRedirectUri.isEmpty) {
      throw ArgumentError.value(
        redirectUri,
        'redirectUri',
        'must not be empty',
      );
    }
    if (state.isEmpty) {
      throw ArgumentError.value(state, 'state', 'must not be empty');
    }
    if (codeChallenge.isEmpty) {
      throw ArgumentError.value(
        codeChallenge,
        'codeChallenge',
        'must not be empty',
      );
    }

    return Uri.parse('$issuer$authorizePath').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': trimmedRedirectUri,
        'scope': scope.trim().isEmpty ? 'openid' : scope.trim(),
        'state': state,
        if (nonce != null && nonce.isNotEmpty) 'nonce': nonce,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );
  }

  Future<WAuthPkcePair> createPkcePair() async {
    final random = Random.secure();
    final verifierBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final verifier = _base64UrlNoPadding(verifierBytes);
    return WAuthPkcePair(
      verifier: verifier,
      challenge: challengeForVerifier(verifier),
    );
  }

  /// Creates a server-side authorization session. The client never receives
  /// or stores the WAuth AppSecret; the gateway exchanges the code securely.
  Future<WAuthGatewaySession> createGatewaySession() async {
    final pkce = await createPkcePair();
    final state = _randomBase64Url(32);
    final response = await _gatewayRequest(
      _client.post(
        Uri.parse('$gatewayBaseUrlValue$gatewaySessionPath'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'state': state,
          'code_challenge': pkce.challenge,
          'code_verifier': pkce.verifier,
        }),
      ),
    );
    final json = _decodeObject(response);
    _throwForFailure(response, json);
    return WAuthGatewaySession.fromJson(
      json,
      state: state,
      codeVerifier: pkce.verifier,
    );
  }

  /// Waits for the one-time result produced by the server callback.
  /// Access tokens are intentionally not returned to, or persisted by, the
  /// Flutter client.
  Future<WAuthGatewayResult> waitForGatewayResult({
    required String state,
    Duration timeout = const Duration(minutes: 10),
    Duration pollInterval = const Duration(seconds: 2),
  }) async {
    if (state.isEmpty) {
      throw ArgumentError.value(state, 'state', 'must not be empty');
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await _gatewayRequest(
        _client.get(
          Uri.parse(
            '$gatewayBaseUrlValue$gatewayResultPath',
          ).replace(queryParameters: {'state': state}),
          headers: const {'Accept': 'application/json'},
        ),
      );
      final json = _decodeObject(response);
      if (response.statusCode == 202) {
        await Future<void>.delayed(pollInterval);
        continue;
      }
      _throwForFailure(response, json);
      return WAuthGatewayResult.fromJson(json);
    }
    throw const WAuthApiException(
      statusCode: 408,
      message: 'WAuth authorization timed out.',
    );
  }

  /// Confirms login with WAuth's official userinfo endpoint.
  Future<WAuthAuthorizedSession> requireAuthorizedAccessToken(
    String? accessToken,
  ) async {
    final trimmedToken = accessToken?.trim() ?? '';
    if (trimmedToken.isEmpty) {
      throw const WAuthApiException(
        statusCode: 401,
        message: 'WAuth login is required.',
      );
    }
    final userInfo = await fetchUserInfo(trimmedToken);
    return WAuthAuthorizedSession(
      accessToken: trimmedToken,
      userInfo: userInfo,
    );
  }

  /// Canonical enable guard for future WAuth-protected data sources.
  Future<WAuthAuthorizedSession> requireStoredAuthorizedAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final credentials = await credentialStore.readAndMigrate(
      preferences: prefs,
    );
    return requireAuthorizedAccessToken(credentials.accessToken);
  }

  /// Inspects saved credentials without deciding UI wipe policy.
  ///
  /// Access-token userinfo and API-token verify are checked independently.
  /// An expired access token must not imply the longer-lived API token is dead.
  Future<WAuthStoredAuthorization> inspectStoredAuthorization({
    SharedPreferences? preferences,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final credentials = await credentialStore.readAndMigrate(
      preferences: prefs,
    );
    if (!credentials.isComplete) {
      return const WAuthStoredAuthorization(
        credentials: WAuthCredentials(),
        accessAuthorized: false,
        apiAuthorized: false,
        accessRejected: false,
        apiRejected: false,
      );
    }

    Map<String, dynamic>? userInfo;
    var accessAuthorized = false;
    var accessRejected = false;
    try {
      final authorized = await requireAuthorizedAccessToken(
        credentials.accessToken,
      );
      userInfo = authorized.userInfo;
      accessAuthorized = true;
    } on WAuthApiException catch (error) {
      accessRejected = error.statusCode == 401 || error.statusCode == 403;
    }

    var apiAuthorized = false;
    var apiRejected = false;
    try {
      await requireAuthorizedApiToken(credentials.apiToken);
      apiAuthorized = true;
    } on WAuthApiException catch (error) {
      apiRejected = error.statusCode == 401 || error.statusCode == 403;
    }

    return WAuthStoredAuthorization(
      credentials: credentials,
      accessAuthorized: accessAuthorized,
      apiAuthorized: apiAuthorized,
      accessRejected: accessRejected,
      apiRejected: apiRejected,
      userInfo: userInfo,
    );
  }

  static String challengeForVerifier(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return _base64UrlNoPadding(digest.bytes);
  }

  WAuthCallbackResult parseCallback(Uri callbackUri) {
    final error = callbackUri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      return WAuthCallbackResult.failure(
        error: error,
        description: callbackUri.queryParameters['error_description'],
        state: callbackUri.queryParameters['state'],
      );
    }

    final code = callbackUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      return WAuthCallbackResult.failure(
        error: 'missing_code',
        description: 'Authorization callback did not contain a code.',
        state: callbackUri.queryParameters['state'],
      );
    }
    return WAuthCallbackResult.success(
      code: code,
      state: callbackUri.queryParameters['state'],
    );
  }

  Future<WAuthTokenResponse> exchangeAuthorizationCode({
    required String code,
    required String redirectUri,
    required String codeVerifier,
    required String clientSecret,
  }) async {
    if (code.isEmpty) {
      throw ArgumentError.value(code, 'code', 'must not be empty');
    }
    if (codeVerifier.isEmpty) {
      throw ArgumentError.value(
        codeVerifier,
        'codeVerifier',
        'must not be empty',
      );
    }
    if (clientSecret.isEmpty) {
      throw ArgumentError.value(
        clientSecret,
        'clientSecret',
        'must not be empty',
      );
    }

    final basic = base64.encode(utf8.encode('$clientId:$clientSecret'));
    final response = await _client.post(
      Uri.parse('$issuer$tokenPath'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Basic $basic',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': codeVerifier,
      },
    );
    final json = _decodeObject(response);
    _throwForFailure(response, json);
    return WAuthTokenResponse.fromJson(json);
  }

  Future<Map<String, dynamic>> fetchUserInfo(String accessToken) async {
    if (accessToken.isEmpty) {
      throw ArgumentError.value(
        accessToken,
        'accessToken',
        'must not be empty',
      );
    }
    final response = await _gatewayRequest(
      _client.get(
        Uri.parse('$issuer$userInfoPath'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      ),
    );
    final json = _decodeObject(response);
    _throwForFailure(response, json);
    return json;
  }

  Future<Map<String, dynamic>> fetchDiscovery() async {
    final response = await _client.get(Uri.parse('$issuer$discoveryPath'));
    final json = _decodeObject(response);
    _throwForFailure(response, json);
    return json;
  }

  Future<Map<String, dynamic>> fetchJwks() async {
    final response = await _client.get(Uri.parse('$issuer$jwksPath'));
    final json = _decodeObject(response);
    _throwForFailure(response, json);
    return json;
  }

  Future<Map<String, dynamic>> verifyApiToken(String apiToken) async {
    if (apiToken.isEmpty) {
      throw ArgumentError.value(apiToken, 'apiToken', 'must not be empty');
    }
    final response = await _gatewayRequest(
      _client.post(
        Uri.parse('$issuer$verifyApiTokenPath'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $apiToken',
        },
      ),
    );
    final json = _decodeObject(response);
    _throwForFailure(response, json);
    return json;
  }

  /// Confirms that the official API credential is accepted by WAuth.
  Future<WAuthApiTokenVerification> requireAuthorizedApiToken(
    String? apiToken,
  ) async {
    final trimmedToken = apiToken?.trim() ?? '';
    if (trimmedToken.isEmpty) {
      throw const WAuthApiException(
        statusCode: 401,
        message: 'WAuth API login is required.',
      );
    }
    final result = await verifyApiToken(trimmedToken);
    if (result['valid'] != true) {
      throw const WAuthApiException(
        statusCode: 401,
        message: 'WAuth API token is invalid or expired.',
      );
    }
    return WAuthApiTokenVerification(apiToken: trimmedToken, claims: result);
  }

  /// Canonical guard for WAuth-protected data sources.
  Future<WAuthApiTokenVerification> requireStoredAuthorizedApiToken() async {
    final prefs = await SharedPreferences.getInstance();
    final credentials = await credentialStore.readAndMigrate(
      preferences: prefs,
    );
    return requireAuthorizedApiToken(credentials.apiToken);
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('Expected a JSON object.');
    } catch (error) {
      throw WAuthApiException(
        statusCode: response.statusCode,
        message: 'Invalid WAuth JSON response: $error',
      );
    }
  }

  void _throwForFailure(http.Response response, Map<String, dynamic> json) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final message =
        json['message']?.toString() ??
        json['error_description']?.toString() ??
        json['error']?.toString() ??
        'WAuth request failed';
    throw WAuthApiException(statusCode: response.statusCode, message: message);
  }

  Future<http.Response> _gatewayRequest(Future<http.Response> request) async {
    try {
      return await request.timeout(requestTimeout);
    } on TimeoutException {
      throw const WAuthApiException(
        statusCode: 408,
        message: 'WAuth gateway request timed out.',
      );
    } on http.ClientException catch (error) {
      throw WAuthApiException(statusCode: 0, message: error.message);
    }
  }

  static String _base64UrlNoPadding(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _randomBase64Url(int byteCount) {
    final random = Random.secure();
    return _base64UrlNoPadding(
      List<int>.generate(byteCount, (_) => random.nextInt(256)),
    );
  }
}

class WAuthPkcePair {
  final String verifier;
  final String challenge;

  const WAuthPkcePair({required this.verifier, required this.challenge});
}

class WAuthGatewaySession {
  final Uri authorizationUri;
  final String state;
  final String codeVerifier;
  final int? expiresIn;

  const WAuthGatewaySession({
    required this.authorizationUri,
    required this.state,
    required this.codeVerifier,
    required this.expiresIn,
  });

  factory WAuthGatewaySession.fromJson(
    Map<String, dynamic> json, {
    required String state,
    required String codeVerifier,
  }) {
    final rawUrl = json['authorizationUrl']?.toString() ?? '';
    final authorizationUri = Uri.tryParse(rawUrl);
    if (authorizationUri == null || !authorizationUri.hasScheme) {
      throw const FormatException(
        'WAuth gateway response did not contain a valid authorization URL.',
      );
    }
    return WAuthGatewaySession(
      authorizationUri: authorizationUri,
      state: state,
      codeVerifier: codeVerifier,
      expiresIn: (json['expiresIn'] as num?)?.toInt(),
    );
  }
}

class WAuthGatewayResult {
  final WAuthTokenResponse token;
  final Map<String, dynamic> userInfo;

  const WAuthGatewayResult({required this.token, required this.userInfo});

  factory WAuthGatewayResult.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    final userInfo = json['userinfo'];
    if (token is! Map) {
      throw const FormatException(
        'WAuth gateway result did not contain an official token response.',
      );
    }
    if (userInfo is! Map) {
      throw const FormatException(
        'WAuth gateway result did not contain user information.',
      );
    }
    return WAuthGatewayResult(
      token: WAuthTokenResponse.fromJson(Map<String, dynamic>.from(token)),
      userInfo: Map<String, dynamic>.from(userInfo),
    );
  }
}

class WAuthAuthorizedSession {
  final String accessToken;
  final Map<String, dynamic> userInfo;

  const WAuthAuthorizedSession({
    required this.accessToken,
    required this.userInfo,
  });
}

class WAuthApiTokenVerification {
  final String apiToken;
  final Map<String, dynamic> claims;

  const WAuthApiTokenVerification({
    required this.apiToken,
    required this.claims,
  });
}

class WAuthStoredAuthorization {
  final WAuthCredentials credentials;
  final bool accessAuthorized;
  final bool apiAuthorized;
  final bool accessRejected;
  final bool apiRejected;
  final Map<String, dynamic>? userInfo;

  const WAuthStoredAuthorization({
    required this.credentials,
    required this.accessAuthorized,
    required this.apiAuthorized,
    required this.accessRejected,
    required this.apiRejected,
    this.userInfo,
  });

  bool get hasCredentials => credentials.isComplete;

  /// Forget saved login only when the business API credential is rejected, or
  /// both the account session and API credential are rejected.
  bool get shouldForgetLogin =>
      hasCredentials && (apiRejected || (accessRejected && !apiAuthorized));

  /// Network/timeouts and other non-auth failures should keep cached login UI.
  bool get hasTransientVerificationFailure =>
      hasCredentials && !apiAuthorized && !apiRejected;

  bool get keepsCachedLoginPresentation => hasCredentials && !shouldForgetLogin;
}

class WAuthCallbackResult {
  final String? code;
  final String? error;
  final String? description;
  final String? state;

  const WAuthCallbackResult._({
    this.code,
    this.error,
    this.description,
    this.state,
  });

  const WAuthCallbackResult.success({required String code, String? state})
    : this._(code: code, state: state);

  const WAuthCallbackResult.failure({
    required String error,
    String? description,
    String? state,
  }) : this._(error: error, description: description, state: state);

  bool get isSuccess => code != null && error == null;
}

class WAuthTokenResponse {
  final String accessToken;
  final String? apiToken;
  final String tokenType;
  final int? expiresIn;
  final String scope;
  final String? idToken;

  const WAuthTokenResponse({
    required this.accessToken,
    required this.apiToken,
    required this.tokenType,
    required this.expiresIn,
    required this.scope,
    required this.idToken,
  });

  factory WAuthTokenResponse.fromJson(Map<String, dynamic> json) {
    final accessToken = json['access_token']?.toString() ?? '';
    if (accessToken.isEmpty) {
      throw const FormatException(
        'WAuth response did not contain access_token.',
      );
    }
    final rawApiToken = json['api_token']?.toString().trim();
    return WAuthTokenResponse(
      accessToken: accessToken,
      apiToken: rawApiToken == null || rawApiToken.isEmpty ? null : rawApiToken,
      tokenType: json['token_type']?.toString() ?? 'Bearer',
      expiresIn: (json['expires_in'] as num?)?.toInt(),
      scope: json['scope']?.toString() ?? '',
      idToken: json['id_token']?.toString(),
    );
  }
}

class WAuthApiException implements Exception {
  final int statusCode;
  final String message;

  const WAuthApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'WAuthApiException($statusCode): $message';
}
