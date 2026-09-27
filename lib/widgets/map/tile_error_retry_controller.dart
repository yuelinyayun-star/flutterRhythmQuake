import 'dart:async';

/// Retries a tile layer after visible tiles have exhausted HTTP-level retries.
class TileErrorRetryController {
  TileErrorRetryController({
    this.retryDelays = const [
      Duration(seconds: 8),
      Duration(seconds: 16),
      Duration(seconds: 32),
      Duration(seconds: 60),
    ],
    this.quietPeriod = const Duration(minutes: 2),
  }) : assert(retryDelays.isNotEmpty);

  final List<Duration> retryDelays;
  final Duration quietPeriod;
  final StreamController<void> _reset = StreamController<void>.broadcast();
  Stream<void> get reset => _reset.stream;

  Timer? _timer;
  String? _sourceKey;
  DateTime? _lastFailure;
  int _retryCount = 0;

  void reportFailure(String sourceKey, bool Function(String) isCurrent) {
    if (_reset.isClosed || !isCurrent(sourceKey)) return;
    final now = DateTime.now();
    if (_sourceKey != sourceKey ||
        (_lastFailure != null && now.difference(_lastFailure!) > quietPeriod)) {
      _timer?.cancel();
      _timer = null;
      _retryCount = 0;
      _sourceKey = sourceKey;
    }
    _lastFailure = now;
    if (_timer != null) return;

    final index = _retryCount.clamp(0, retryDelays.length - 1);
    _timer = Timer(retryDelays[index], () {
      _timer = null;
      if (_reset.isClosed || !isCurrent(sourceKey)) return;
      _retryCount++;
      _reset.add(null);
    });
  }

  void dispose() {
    _timer?.cancel();
    _reset.close();
  }
}
