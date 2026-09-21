import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  const JianCredential(this.token, {this.expiresAt});
  final String token;
  final DateTime? expiresAt;
}

class JianCredentialStore {
  JianCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  static const storageKey = 'jian.secure.refresh_token';
  final FlutterSecureStorage _storage;

  Future<String> read() async => (await readCredential()).token;

  Future<JianCredential> readCredential() async {
    final stored = (await _storage.read(key: storageKey)) ?? '';
    // Older installations stored only the raw rt_. Never invent an expiry.
    if (stored.isEmpty || isJianCredential(stored, 'rt_')) {
      return JianCredential(stored);
    }
    final value = jsonDecode(stored);
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

  Future<void> write(String token, {DateTime? expiresAt}) async {
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

  Future<void> clear() => _storage.delete(key: storageKey);
}

/// Messages are local and allowlisted: server bodies and credentials never
/// become log text, UI errors, or cross-isolate status messages.
class JianAuthException implements Exception {
  const JianAuthException(this.code);
  final String code;
  bool get retryable => const {
    'network',
    'server',
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
    'invalid_api_key' ||
    'invalid_token_format' ||
    'missing_api_key' => '访问令牌被拒绝，请检查鉴权配置。',
    'account_banned' => 'Jian 账号已被封禁，请联系服务方。',
    'conn_limit' => 'Jian 凭证并发连接已满。',
    'cooldown' => 'Jian 请求过于频繁，请稍后重试。',
    'network' => '无法连接 Jian 鉴权服务，请稍后重试。',
    'server' => 'Jian 鉴权服务暂不可用，请稍后重试。',
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
      _ => 'rejected',
    });
  }
}

class JianAuthService {
  JianAuthService({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;
  final http.Client _client;
  final DateTime Function() _now;
  static final registrationUri = Uri.https('auth.sismotide.top', '/');

  Future<String> exchangeLoginKey(String key) async =>
      (await exchangeLoginKeyCredential(key)).token;
  Future<JianCredential> exchangeLoginKeyCredential(String key) =>
      _exchange('refresh', key, 'lk_', 'rt_', 'expires_after_min');
  Future<String> accessToken(String token) async => (await _exchange(
    'access',
    token,
    'rt_',
    'at_',
    'expires_after_sec',
  )).token;

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
    try {
      final requestedAt = _now().toUtc();
      final request =
          http.Request('POST', Uri.https('auth.sismotide.top', '/api/$path'))
            ..followRedirects = false
            ..headers['Authorization'] = 'Bearer $credential';
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 429) throw const JianAuthException('cooldown');
      if (response.statusCode >= 500) throw const JianAuthException('server');
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const JianAuthException('rejected');
      if (response.statusCode != 200 || decoded['ok'] != true) {
        throw JianAuthException.fromResponse(decoded);
      }
      final token = decoded['token'];
      final lifetime = decoded[lifetimeKey];
      if (token is! String ||
          !isJianCredential(token, outputPrefix) ||
          lifetime is! num ||
          !lifetime.isFinite ||
          lifetime <= 0) {
        throw const JianAuthException('rejected');
      }
      final seconds = lifetime * (lifetimeKey == 'expires_after_min' ? 60 : 1);
      return JianCredential(
        token,
        expiresAt: requestedAt.add(
          Duration(milliseconds: (seconds * 1000).floor()),
        ),
      );
    } on JianAuthException {
      rethrow;
    } on TimeoutException {
      throw const JianAuthException('network');
    } on http.ClientException {
      throw const JianAuthException('network');
    } catch (_) {
      throw const JianAuthException('rejected');
    }
  }

  void close() => _client.close();
}
