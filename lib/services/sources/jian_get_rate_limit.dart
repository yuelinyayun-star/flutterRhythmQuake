import 'dart:async';

class JianGetRateLimit {
  static Future<void> _queue = Future<void>.value();
  static DateTime? _lastRequest;

  static Future<T> run<T>(Future<T> Function() request) async {
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    try {
      final lastRequest = _lastRequest;
      if (lastRequest != null) {
        final remaining =
            const Duration(milliseconds: 1100) -
            DateTime.now().difference(lastRequest);
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      }
      _lastRequest = DateTime.now();
      return await request();
    } finally {
      done.complete();
    }
  }
}
