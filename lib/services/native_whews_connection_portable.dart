/// Explicit compatibility for platforms without the native Windows backend.
abstract final class NativeWhewsConnection {
  static bool get supported => false;
  static int get outputs => 0;
  static dynamic prepare(Map<String, dynamic> request) {
    if (request['op'] == 'endpoints') {
      final original = request['url'] as String;
      final uri = Uri.parse(original);
      final shared =
          uri.scheme == 'wss' &&
          uri.host == 'api.beecld.com' &&
          !uri.hasPort &&
          const {
            '/ws/all',
            '/ws/nied',
            '/ws/snet',
            '/ws/kma_station',
          }.contains(uri.path);
      return [
        original,
        if (shared) original.replaceFirst('api.beecld.com', 'api.2v8.cn'),
      ];
    }
    if (request['op'] == 'retry') {
      final code = request['code'];
      if (const {401, 403, 404, 429, 4401, 4403, 4008, 1008}.contains(code)) {
        return null;
      }
      final seconds = (request['seconds'] as int).clamp(3, 300);
      final count = request['count'] as int;
      final index = request['index'] as int;
      final delay = code == 4503 && seconds < 15 ? 15 : seconds;
      return {
        'index': seconds >= 30 && count > 1 ? (index + 1) % count : index,
        'delay': delay,
        'next': (delay * 2).clamp(3, 300),
      };
    }
    throw ArgumentError('Unknown WHEWS connection operation');
  }
}
