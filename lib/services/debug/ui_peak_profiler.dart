import 'package:flutter/scheduler.dart';

/// Read-only UI-thread workload profiler for field jank attribution.
///
/// Zero behavior change: zones are Stopwatch-only and FrameTiming aggregation
/// is passive. Output goes to `print` (logcat) only when a zone exceeds its
/// threshold, plus a periodic FrameTiming aggregate line. Opt out entirely
/// with --dart-define=RQ_UI_PROFILER=false.
// Diagnostic field profiler: print is intentional so release builds reach
// logcat (debugPrint is a release no-op in main.dart).
// ignore_for_file: avoid_print
class UiPeakProfiler {
  UiPeakProfiler._();

  static const bool enabled = bool.fromEnvironment(
    'RQ_UI_PROFILER',
    defaultValue: true,
  );

  static const String tag = '[RQPerf]';

  static final Map<String, Stopwatch> _active = {};
  static final Map<String, int> _hits = {};
  static final Map<String, int> _totalMicros = {};
  static final Map<String, int> _maxMicros = {};
  static bool _frameStatsAttached = false;
  static final List<FrameTiming> _pendingTimings = [];
  static DateTime _lastFrameFlush = DateTime.now();

  /// Starts a timing lap for [zone]. Nested or repeated laps overwrite only
  /// their own zone.
  static void begin(String zone) {
    if (!enabled) return;
    (_active[zone] ??= Stopwatch()).start();
  }

  /// Ends the lap for [zone]; accumulates stats and reports immediately when
  /// the lap exceeded [reportThresholdMs].
  static void end(String zone, {int reportThresholdMs = 8}) {
    if (!enabled) return;
    final sw = _active.remove(zone);
    if (sw == null) return;
    sw.stop();
    final micros = sw.elapsedMicroseconds;
    _hits[zone] = (_hits[zone] ?? 0) + 1;
    _totalMicros[zone] = (_totalMicros[zone] ?? 0) + micros;
    if (micros > (_maxMicros[zone] ?? 0)) {
      _maxMicros[zone] = micros;
    }
    if (micros >= reportThresholdMs * 1000) {
      print('$tag SLOW zone=$zone took=${(micros / 1000).toStringAsFixed(1)}ms');
    }
  }

  /// One-line aggregate per zone; call periodically to see call counts.
  static void drainSummary() {
    if (!enabled) return;
    for (final zone in _hits.keys.toList()..sort()) {
      final hits = _hits[zone]!;
      final total = _totalMicros[zone] ?? 0;
      final max = _maxMicros[zone] ?? 0;
      if (hits == 0) continue;
      print(
        '$tag SUM zone=$zone hits=$hits avg=${(total / hits / 1000).toStringAsFixed(2)}ms '
        'max=${(max / 1000).toStringAsFixed(1)}ms total=${(total / 1000).toStringAsFixed(0)}ms',
      );
    }
    _hits.clear();
    _totalMicros.clear();
    _maxMicros.clear();
  }

  /// Attaches passive FrameTiming aggregation (build vs raster split).
  static void attachFrameStats() {
    if (!enabled || _frameStatsAttached) return;
    _frameStatsAttached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    _pendingTimings.addAll(timings);
    final now = DateTime.now();
    if (now.difference(_lastFrameFlush).inSeconds < 2) return;
    _lastFrameFlush = now;
    if (_pendingTimings.isEmpty) {
      print('$tag FRAME win=2s n=0 (no frames produced)');
      return;
    }
    final builds = _pendingTimings
        .map((t) => t.buildDuration.inMicroseconds)
        .toList()
      ..sort();
    final rasters = _pendingTimings
        .map((t) => t.rasterDuration.inMicroseconds)
        .toList()
      ..sort();
    final totalSpans = _pendingTimings
        .map((t) => t.totalSpan.inMicroseconds)
        .toList()
      ..sort();
    String pct(List<int> sorted, double p) =>
        (sorted[((sorted.length - 1) * p).round().clamp(0, sorted.length - 1)] /
            1000)
        .toStringAsFixed(1);
    final jank100 = totalSpans.where((us) => us > 100 * 1000).length;
    print(
      '$tag FRAME win=2s n=${_pendingTimings.length} '
      'build p50=${pct(builds, 0.5)} p95=${pct(builds, 0.95)} max=${pct(builds, 1.0)}ms '
      'raster p50=${pct(rasters, 0.5)} p95=${pct(rasters, 0.95)} max=${pct(rasters, 1.0)}ms '
      'span max=${pct(totalSpans, 1.0)}ms jank100=$jank100',
    );
    _pendingTimings.clear();
  }
}
