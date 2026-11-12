import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'connection_retry_store.dart';
export 'connection_retry_store.dart'
    show ConnectionRetryStore, MemoryConnectionRetryStore;

class JianAuthRetryState {
  const JianAuthRetryState({
    this.failures = 0,
    this.revision = 0,
    this.blocked = false,
    this.code,
    this.nextAttemptAt,
  });
  final int failures, revision;
  final bool blocked;
  final String? code;
  final DateTime? nextAttemptAt;
  factory JianAuthRetryState.fromMap(Map<String, dynamic> value) =>
      JianAuthRetryState(
        failures: value['failures'] as int? ?? 0,
        revision: value['revision'] as int? ?? 0,
        blocked: value['blocked'] == true,
        code: value['code'] as String?,
        nextAttemptAt: value['nextAttemptMs'] is int
            ? DateTime.fromMillisecondsSinceEpoch(
                value['nextAttemptMs'] as int,
                isUtc: true,
              )
            : null,
      );
}

/// Limits consecutive token rejections across app/collector instances and restarts.
/// Only fingerprints and retry metadata are stored; no RT, AT or response body.
class JianAuthRetryPolicy {
  JianAuthRetryPolicy({ConnectionRetryStore? store})
    : _store =
          store ??
          storeOverride ??
          createConnectionRetryStore('jian_auth_retry');
  @visibleForTesting
  static ConnectionRetryStore? storeOverride;
  static const maxFailures = 3;
  static const retryDelay = Duration(minutes: 5);
  final ConnectionRetryStore _store;
  static bool isTokenRejection(String code) => const {
    'missing_api_key',
    'invalid_token_format',
    'invalid_api_key',
    'expired_access_token',
  }.contains(code);
  static bool mayRenew(String code) =>
      code == 'invalid_api_key' || code == 'expired_access_token';
  String _key(String token) => sha256.convert(utf8.encode(token)).toString();

  Future<JianAuthRetryState> read(String token) =>
      _store.update(_key(token), (value) => JianAuthRetryState.fromMap(value));

  Future<JianAuthRetryState> rejected(String token, String code, DateTime now) {
    if (!isTokenRejection(code)) throw ArgumentError.value(code, 'code');
    return _store.update(_key(token), (value) {
      final old = JianAuthRetryState.fromMap(value);
      final count = old.failures + 1;
      value.addAll({
        'failures': count,
        'revision': old.revision + 1,
        'blocked': old.blocked || !mayRenew(code) || count >= maxFailures,
        'code': count >= maxFailures ? 'auth_retry_exhausted' : code,
        'nextAttemptMs': now.toUtc().add(retryDelay).millisecondsSinceEpoch,
      });
      return JianAuthRetryState.fromMap(value);
    });
  }

  /// A prior connection cannot clear a newer rejection, or a latched stop.
  Future<void> accepted(String token, int attemptRevision) =>
      _store.update(_key(token), (value) {
        final state = JianAuthRetryState.fromMap(value);
        if (state.blocked ||
            state.revision != attemptRevision ||
            state.failures == 0)
          return;
        value
          ..clear()
          ..['revision'] = state.revision + 1;
      });

  /// Explicitly saving credentials grants one attempt, keeping the cooldown.
  /// Repeated saves before a successful connection cannot refill the budget.
  Future<void> resume(String token) => _store.update(_key(token), (value) {
    final state = JianAuthRetryState.fromMap(value);
    if (!state.blocked) return;
    value.addAll({
      'blocked': false,
      'failures': maxFailures - 1,
      'revision': state.revision + 1,
      'code': null,
    });
  });
}
