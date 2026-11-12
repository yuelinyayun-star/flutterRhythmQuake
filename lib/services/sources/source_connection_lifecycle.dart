import 'dart:async';

/// A replacement must not overtake pending cancellation or socket shutdown.
class SourceConnectionBarrier {
  Future<void>? _pending;
  Object? _closeFailure;

  void close(Future<void> Function() operation) {
    final next = Future<void>.sync(operation).then<void>(
      (_) {},
      onError: (Object error, StackTrace _) {
        _closeFailure = error;
      },
    );
    final previous = _pending;
    final combined = previous == null
        ? next
        : Future.wait([previous, next]).then<void>((_) {});
    late final Future<void> tail;
    tail = combined.whenComplete(() {
      if (identical(_pending, tail)) _pending = null;
    });
    _pending = tail;
  }

  Future<void> wait() async {
    while (_pending != null) {
      final pending = _pending!;
      await pending;
      if (identical(_pending, pending)) _pending = null;
    }
    if (_closeFailure != null)
      throw StateError('Previous connection shutdown was not confirmed');
  }
}

/// Give queued ingress a chance to drain after a late local timer wakeup.
class SourceActivityWatchdog {
  SourceActivityWatchdog(
    this.interval, {
    this.grace = const Duration(seconds: 20),
  });
  final Duration interval;
  final Duration grace;
  DateTime? _checkedAt;
  DateTime? _resumeUntil;

  void reset(DateTime now) {
    _checkedAt = now;
    _resumeUntil = null;
  }

  bool mayDeclareStale(DateTime now) {
    final previous = _checkedAt;
    _checkedAt = now;
    if (previous != null && now.difference(previous) > interval * 2) {
      _resumeUntil = now.add(grace);
    }
    return _resumeUntil == null || !now.isBefore(_resumeUntil!);
  }
}

/// A late local wakeup is not proof that the peer missed its deadline.
Future<T> sourceReady<T>(
  Future<T> ready,
  Duration timeout, {
  DateTime Function()? now,
}) {
  final clock = now ?? DateTime.now;
  final deadline = clock().add(timeout);
  return ready.timeout(
    timeout,
    onTimeout: () {
      if (clock().difference(deadline) > const Duration(seconds: 5)) {
        return ready.timeout(const Duration(seconds: 2));
      }
      throw TimeoutException('Source handshake timed out', timeout);
    },
  );
}

void cancelSourceSubscription(StreamSubscription<dynamic>? subscription) {
  if (subscription == null) return;
  // Closing the transport is tracked separately and must still succeed.
  try { unawaited(subscription.cancel().catchError((Object _) {})); } catch (_) {}
}
