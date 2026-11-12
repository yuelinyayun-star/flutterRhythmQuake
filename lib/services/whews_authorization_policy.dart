import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'connection_retry_store.dart';
export 'connection_retry_store.dart' show MemoryConnectionRetryStore;

/// A station whitelist rejection is scoped to that endpoint, not all WHEWS feeds.
class WhewsAuthorizationPolicy {
  WhewsAuthorizationPolicy({ConnectionRetryStore? store})
    : _store =
          store ??
          storeOverride ??
          createConnectionRetryStore('whews_auth_block');
  @visibleForTesting
  static ConnectionRetryStore? storeOverride;
  final ConnectionRetryStore _store;
  static bool isTerminal(int? code) =>
      const {401, 403, 404, 429, 4401, 4403, 4008, 1008}.contains(code);
  static String endpoint(String url) {
    final uri = Uri.parse(url);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }

  String _key(String token) =>
      sha256.convert(utf8.encode(token.trim())).toString();
  Future<int?> blockedCode(String url, String token) =>
      _store.update(_key(token), (record) {
        final paths = record['paths'] as Map?;
        final state = paths?[endpoint(url)] as Map?;
        return state?['blocked'] == true ? state!['code'] as int : null;
      });
  Future<void> block(String url, String token, int code) =>
      _store.update(_key(token), (record) {
        final paths = Map<String, dynamic>.from(record['paths'] as Map? ?? {});
        paths[endpoint(url)] = {'blocked': true, 'code': code};
        record['paths'] = paths;
      });

  /// Only explicit credential save/login calls this; reload/start never does.
  Future<void> resumeToken(String token) =>
      _store.update(_key(token), (record) {
        record.clear();
      });
}
