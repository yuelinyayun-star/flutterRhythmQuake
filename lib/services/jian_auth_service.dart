import 'dart:async';
import 'sources/api_json_decoder.dart';
import 'dart:convert';
import 'native_jian_connection.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

enum JianAuthStatus {
  anonymous,
  unconfigured,
  authenticating,
  authenticated,
  invalid,
  unavailable,
}

bool isJianCredential(String value, String prefix) =>
    value.startsWith(prefix) &&
    value.length > prefix.length &&
    RegExp(r'^[\x21-\x7E]+$').hasMatch(value);

class JianCredential {
  const JianCredential(this.token, {this.expiresAt, this.refreshExpiresAt});
  final String token;

  /// Expiry of [token] itself: RT for refresh exchange, AT for access exchange.
  final DateTime? expiresAt;

  /// RT expiry returned by either exchange; never inferred from AT lifetime.
  final DateTime? refreshExpiresAt;
}

class JianCredentialStore {
  JianCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  static const storageKey = 'jian.secure.refresh_token';
  final FlutterSecureStorage _storage;
  static Future<void>? _writes;

  // Dialog saves and expiry refreshes may use different store instances.
  static Future<void> _mutate(Future<void> Function() operation) {
    final previous = _writes;
    final next = previous == null
        ? Future<void>.sync(operation)
        : previous.then((_) => operation());
    late final Future<void> tail;
    void finished() {
      if (identical(_writes, tail)) _writes = null;
    }

    tail = next.then<void>(
      (_) => finished(),
      onError: (Object _, StackTrace _) => finished(),
    );
    _writes = tail;
    return next;
  }

  Future<String> read() async => (await readCredential()).token;

  Future<JianCredential> readCredential() async {
    final stored = (await _storage.read(key: storageKey)) ?? '';
    // Older installations stored only the raw rt_. Never invent an expiry.
    if (stored.isEmpty || isJianCredential(stored, 'rt_')) {
      return JianCredential(stored);
    }
    final value = decodeApiJson(stored);
    if (value is! Map ||
        value['token'] is! String ||
        !isJianCredential(value['token'] as String, 'rt_')) {
      throw const JianAuthException('storage');
    }
    final expiry = value['expiresAt'];
    return JianCredential(
      value['token'] as String,
      expiresAt: expiry is String ? DateTime.tryParse(expiry)?.toUtc() : null,
    );
  }

  Future<void> write(String token, {DateTime? expiresAt}) =>
      _mutate(() => _write(token, expiresAt: expiresAt));

  Future<void> _write(String token, {DateTime? expiresAt}) async {
    if (!isJianCredential(token, 'rt_')) {
      throw const JianAuthException('invalid_refresh_token');
    }
    // Keep token and its expiry in one secure write, including replacement.
    await _storage.write(
      key: storageKey,
      value: expiresAt == null
          ? token
          : jsonEncode({
              'token': token,
              'expiresAt': expiresAt.toUtc().toIso8601String(),
            }),
    );
  }

  Future<void> clear() => _mutate(() => _storage.delete(key: storageKey));

  Future<void> updateExpiry(String token, DateTime expiresAt) =>
      _mutate(() async {
        final current = await readCredential();
        if (current.token != token || current.expiresAt == expiresAt) return;
        await _write(token, expiresAt: expiresAt);
      });
}

/// Messages are local and allowlisted: server bodies and credentials never
/// become log text, UI errors, or cross-isolate status messages.
class JianAuthException implements Exception {
  const JianAuthException(this.code);
  final String code;
  bool get retryable => const {
    'network',
    'server',
    'invalid_response',
    'cooldown',
    'conn_limit',
    'expired_access_token',
    'invalid_api_key',
  }.contains(code);
  String get message => switch (code) {
    'credential_required' => 'Jian 业务连接需要鉴权，请先配置个人凭证。',
    'invalid_refresh_token' => '长期 Token 无效，请重新配置。',
    'expired_refresh_token' => '长期 Token 已过期，请重新申请登录密钥。',
    'invalid_login_key' || 'expired_login_key' => '登录密钥无效或已过期，请重新申请。',
    'token_exists' => '已有长期 Token，请使用原凭证或在申请页选择覆盖。',
    'expired_access_token' => '访问令牌已过期，将重新换取。',
    'auth_retry_exhausted' => '连续令牌校验失败，已暂停自动连接。请检查鉴权后重新保存凭证再试。',
    'retry_storage' => '无法读写鉴权重试记录，已暂停连接。',
    'handshake_rejected' => 'Jian 握手被拒绝，已暂停连接，请检查鉴权配置。',
    'invalid_api_key' ||
    'invalid_token_format' ||
    'missing_api_key' => '访问令牌被拒绝，请检查鉴权配置。',
    'ip_banned' => 'Jian IP 已被封禁，请等待解封后再连接。',
    'account_banned' => 'Jian 账号已被封禁，请联系服务方。',
    'conn_limit' => 'Jian 凭证并发连接已满。',
    'cooldown' => 'Jian 请求过于频繁，请稍后重试。',
    'network' => '无法连接 Jian 鉴权服务，请稍后重试。',
    'server' => 'Jian 鉴权服务暂不可用，请稍后重试。',
    'invalid_response' => 'Jian 鉴权响应异常，将稍后重试。',
    'storage' => '无法读取安全存储，未建立匿名连接。',
    _ => 'Jian 鉴权失败，请检查凭证或重新申请。',
  };
  @override
  String toString() => message;

  static JianAuthException fromResponse(Map<dynamic, dynamic> body) {
    final known = const {
      'missing_api_key',
      'invalid_token_format',
      'invalid_api_key',
      'expired_access_token',
      'conn_limit',
      'account_banned',
      'invalid_login_key',
      'expired_login_key',
      'token_exists',
      'invalid_refresh_token',
      'expired_refresh_token',
      'cooldown',
    };
    if (body['type'] == 'error' &&
        body['message'] is String &&
        (body['message'] as String).contains('封禁')) {
      return const JianAuthException('ip_banned');
    }
    final error = body['error'];
    if (known.contains(error)) return JianAuthException(error as String);
    return JianAuthException(switch (body['code']) {
      4001 => 'missing_api_key',
      4002 => 'invalid_token_format',
      4003 => 'invalid_api_key',
      4004 => 'expired_access_token',
      4005 => 'conn_limit',
      4006 => 'account_banned',
      4101 => 'invalid_login_key',
      4102 => 'expired_login_key',
      4103 => 'token_exists',
      4201 => 'invalid_refresh_token',
      4202 => 'expired_refresh_token',
      4301 => 'cooldown',
      // An unrecognized response does not prove that the saved RT is invalid.
      _ => 'invalid_response',
    });
  }
}

class JianAuthService {
  JianAuthService({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _now;
  String _accessAuthHost = 'auth.sismotide.top';

  /// The documented business host selects its matching ticket issuer.
  void selectApiEndpoint(Uri endpoint) {
    if (endpoint.scheme != 'wss' ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasPort) {
      throw ArgumentError('Untrusted JIAN API endpoint');
    }
    _accessAuthHost =
        NativeJianConnection.prepare({'op': 'authHost', 'host': endpoint.host})
            as String;
  }

  static JianAuthException? transportAuthFailure(int? code) {
    final name = NativeJianConnection.prepare({
      'op': 'transportAuthFailure',
      'code': code,
    });
    return name == null ? null : JianAuthException(name as String);
  }

  static final registrationUri = Uri.https('auth.sismotide.top', '/');

  Future<String> exchangeLoginKey(String key) async =>
      (await exchangeLoginKeyCredential(key)).token;
  Future<JianCredential> exchangeLoginKeyCredential(String key) =>
      _exchange('refresh', key, 'lk_', 'rt_', 'expires_after_min');
  Future<String> accessToken(String token) async =>
      (await accessTokenCredential(token)).token;

  Future<JianCredential> accessTokenCredential(String token) =>
      _exchange('access', token, 'rt_', 'at_', 'expires_after_sec');

  static DateTime? _expiry(
    num? value,
    DateTime requestedAt, {
    bool unix = false,
    int unitMillis = 60000,
  }) {
    if (value == null || !value.isFinite || (unix ? value <= 0 : value < 0)) {
      return null;
    }
    try {
      final millis = value * (unix ? 1000 : unitMillis);
      return unix
          ? DateTime.fromMillisecondsSinceEpoch(millis.floor(), isUtc: true)
          : requestedAt.add(Duration(milliseconds: millis.floor()));
    } catch (_) {
      return null;
    }
  }

  static DateTime? _refreshExpiry(
    Map<dynamic, dynamic> body,
    DateTime requestedAt,
  ) {
    final absolute = body['refresh_expires_at'];
    final remaining = body['refresh_expires_after_min'];
    return _expiry(
          absolute is num ? absolute : null,
          requestedAt,
          unix: true,
        ) ??
        _expiry(remaining is num ? remaining : null, requestedAt);
  }

  Future<JianCredential> _exchange(
    String path,
    String credential,
    String inputPrefix,
    String outputPrefix,
    String lifetimeKey,
  ) async {
    if (!isJianCredential(credential, inputPrefix)) {
      throw JianAuthException(
        inputPrefix == 'lk_' ? 'invalid_login_key' : 'invalid_refresh_token',
      );
    }
    final requestedAt = _now().toUtc();
    late final http.Response response;
    try {
      final authHost = path == 'access'
          ? _accessAuthHost
          : 'auth.sismotide.top';
      final uri = kIsWeb && authHost == 'auth.sismotide.top'
          ? Uri.base.resolve('/api/jian/auth/$path')
          : Uri.https(authHost, '/api/$path');
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['Authorization'] = 'Bearer $credential';
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Only transport work is inside this block. Never classify a failed
      // request/response stream as a rejection of the stored credential.
      throw const JianAuthException('network');
    }
    try {
      if (response.statusCode == 429) throw const JianAuthException('cooldown');
      if (response.statusCode >= 500) throw const JianAuthException('server');
      final decoded = decodeApiJsonBytes(response.bodyBytes);
      if (decoded is! Map) throw const JianAuthException('invalid_response');
      if (response.statusCode != 200 || decoded['ok'] != true) {
        throw JianAuthException.fromResponse(decoded);
      }
      final token = decoded['token'];
      final lifetime = decoded[lifetimeKey];
      final refreshExpiry = _refreshExpiry(decoded, requestedAt);
      if (token is! String || !isJianCredential(token, outputPrefix)) {
        throw const JianAuthException('invalid_response');
      }
      final legacyExpiry = lifetime is num && lifetime.isFinite && lifetime > 0
          ? _expiry(
              lifetime,
              requestedAt,
              unitMillis: lifetimeKey == 'expires_after_min' ? 60000 : 1000,
            )
          : null;
      final expiresAt = outputPrefix == 'rt_'
          ? refreshExpiry ?? legacyExpiry
          : legacyExpiry;
      if (expiresAt == null) {
        throw const JianAuthException('invalid_response');
      }
      return JianCredential(
        token,
        expiresAt: expiresAt,
        refreshExpiresAt: refreshExpiry,
      );
    } on JianAuthException {
      rethrow;
    } catch (_) {
      // Includes non-JSON/invalid UTF-8 gateway pages and malformed tickets.
      // Keep the original credential and use the bounded reconnect cooldown.
      throw const JianAuthException('invalid_response');
    }
  }

  void close() => _client.close();
}
