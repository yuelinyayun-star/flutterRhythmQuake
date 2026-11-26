final _elapsed = Stopwatch()..start();

int liveDisplayElapsedUs() => _elapsed.elapsedMicroseconds;

int liveDisplayLifetimeUs(int kind) => switch (kind) {
  0 => const Duration(minutes: 2).inMicroseconds,
  1 => const Duration(hours: 24).inMicroseconds,
  2 => const Duration(minutes: 5).inMicroseconds,
  3 => const Duration(minutes: 3).inMicroseconds,
  4 => const Duration(seconds: 31).inMicroseconds,
  _ => throw ArgumentError.value(kind),
};
