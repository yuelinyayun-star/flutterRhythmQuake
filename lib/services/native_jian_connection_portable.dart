abstract final class NativeJianConnection {
  static bool get supported => false;
  static int get outputs => 0;
  static dynamic prepare(Map<String, dynamic> v) {
    const apis = ['api.sismotide.top', 'api.jianproject.cloud'];
    const auth = ['auth.sismotide.top', 'auth.jianproject.cloud'];
    if (v['op'] == 'transportAuthFailure') {
      return const {
        401: 'invalid_api_key',
        4003: 'invalid_api_key',
        403: 'handshake_rejected',
        1008: 'handshake_rejected',
        429: 'cooldown',
        4001: 'missing_api_key',
        4002: 'invalid_token_format',
        4004: 'expired_access_token',
        4005: 'conn_limit',
        4006: 'account_banned',
      }[v['code']];
    }
    if (v['op'] == 'authHost') {
      final index = apis.indexOf(v['host'] as String);
      if (index < 0) {
        throw ArgumentError('Untrusted JIAN API host');
      }
      return auth[index];
    }
    final index = v['index'] as int;
    if (index < 0 || index > 1) {
      throw ArgumentError('Invalid JIAN endpoint index');
    }
    if (v['op'] == 'endpoint') {
      final path = v['path'] as String;
      if (!const {'/all', '/kmoni', '/s-net', '/kma-station'}.contains(path)) {
        throw ArgumentError('Unsupported JIAN path');
      }
      return {
        'url': 'wss://${apis[index]}$path',
        'authHost': auth[index],
        'needsAuth': path == '/all',
      };
    }
    if (v['op'] == 'retry') {
      var failures = v['failures'] as int;
      if (v['stableMillis'] is int && (v['stableMillis'] as int) > 120000) {
        failures = 0;
      }
      final explicit = v['cooldownMs'] as int?;
      final delay =
          explicit ?? (45000 * (1 << failures.clamp(0, 3))).clamp(0, 300000);
      return {
        'index': v['switchEndpoint'] == true ? 1 - index : index,
        'failures': explicit == null ? failures + 1 : failures,
        'delayMs': delay,
      };
    }
    throw ArgumentError('Unknown JIAN connection operation');
  }
}
