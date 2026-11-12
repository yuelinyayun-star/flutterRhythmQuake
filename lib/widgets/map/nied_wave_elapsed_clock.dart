import '../../core/source_estimation/source_estimation_models.dart';

/// Interpolates between algorithm samples without restarting cached samples.
/// Each published source has its own anchor; inference inputs stay unchanged.
class NiedWaveElapsedClock {
  NiedWaveElapsedClock({Duration Function()? elapsed}) : _elapsed = elapsed;

  final Duration Function()? _elapsed;
  final Stopwatch _clock = Stopwatch();
  final Map<Object, ({DateTime? origin, double seconds, Duration at})>
  _anchors = {};

  Object _key(SourceEstimate estimate) =>
      estimate.diagnostics['selected_detection_id'] ?? 'primary';

  Duration get _now => _elapsed?.call() ?? _clock.elapsed;

  void sync(Iterable<SourceEstimate> estimates) {
    _clock.start();
    final now = _now;
    final keys = <Object>{};
    for (final estimate in estimates) {
      final key = _key(estimate);
      final raw = estimate.diagnostics['wave_elapsed_s'];
      final seconds = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '');
      if (seconds == null || !seconds.isFinite) continue;
      keys.add(key);
      final previous = _anchors[key];
      if (previous == null ||
          previous.origin != estimate.originTime ||
          previous.seconds != seconds) {
        _anchors[key] = (
          origin: estimate.originTime,
          seconds: seconds,
          at: now,
        );
      }
    }
    _anchors.removeWhere((key, _) => !keys.contains(key));
  }

  double? elapsedFor(SourceEstimate estimate) {
    final anchor = _anchors[_key(estimate)];
    if (anchor == null) return null;
    return anchor.seconds + (_now - anchor.at).inMicroseconds / 1000000.0;
  }

  void clear() {
    _anchors.clear();
    _clock
      ..stop()
      ..reset();
  }
}
