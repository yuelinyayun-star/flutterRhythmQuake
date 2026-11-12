import 'dart:async';

import 'package:flutter/widgets.dart';

/// Caps the framework frame rate at [maxFramesPerSecond] with a Timer, and
/// aligns the Timer expiry to the display's vsync grid.
///
/// Why alignment matters: on a 120 Hz panel the 22.2 ms budget is not a
/// multiple of the 8.33 ms vsync period. A bare Timer fires at a random
/// phase inside a vsync interval; the engine then waits for the *next*
/// vsync, adding 0-8.3 ms (avg. 4.2 ms) on every frame, plus 1-4 ms of
/// Android Timer jitter. Measured effect: drag frame intervals oscillated
/// 26-45 ms (~20-27 fps) even when build+raster needed only ~8 ms.
///
/// Fix: learn the vsync period and clock offset from the engine's
/// `rawTimeStamp` (origin is fixed, period is constant), then set the Timer
/// to fire ~4 ms *before* the first vsync that satisfies the interval
/// budget. Firing early is safe (the engine holds the request until that
/// vsync); firing late misses the vsync and costs a full period, so the
/// 4 ms lead absorbs Timer jitter.
///
/// Framework state-machine note: `super.scheduleFrame()` is a no-op while
/// `_hasScheduledFrame` is true, which is the case until
/// `handleDrawFrame`'s finally block runs. The Timer therefore must never
/// be replaced by an in-frame reschedule (a skip-inside-handleBeginFrame
/// approach deadlocks the frame chain — measured in 1.0.5.34).
class RhythmFrameRateBinding extends WidgetsFlutterBinding {
  RhythmFrameRateBinding._();

  static const int maxFramesPerSecond = 45;
  static const int _minFrameIntervalUs =
      Duration.microsecondsPerSecond ~/ maxFramesPerSecond;

  /// Fire the Timer this long before the targeted vsync so Android Timer
  /// jitter (1-4 ms late) still lands inside the vsync window.
  static const int _vsyncLeadUs = 4000;

  final Stopwatch _clock = Stopwatch()..start();
  Timer? _delayedFrameTimer;
  bool _delayedForcedFrame = false;
  int? _lastBeginFrameUs;

  // --- learned vsync clock model ---
  double? _vsyncPeriodUs;
  double? _clockMinusRawUs; // clock-domain minus rawTimeStamp-domain offset
  int? _lastRawTsUs;
  int? _lastLearnClockUs;

  static WidgetsBinding ensureInitialized() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      return RhythmFrameRateBinding._();
    }
  }

  @override
  void scheduleFrame() {
    _scheduleFrameWithLimit(forced: false);
  }

  @override
  void scheduleForcedFrame() {
    _scheduleFrameWithLimit(forced: true);
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    final nowUs = _clock.elapsedMicroseconds;
    _lastBeginFrameUs = nowUs;
    if (rawTimeStamp != null) {
      _learnVsyncClock(rawTimeStamp.inMicroseconds, nowUs);
    }
    super.handleBeginFrame(rawTimeStamp);
  }

  void _learnVsyncClock(int rawUs, int clockUs) {
    final lastRaw = _lastRawTsUs;
    final lastClock = _lastLearnClockUs;
    _lastRawTsUs = rawUs;
    _lastLearnClockUs = clockUs;

    final obs = (clockUs - rawUs).toDouble();
    _clockMinusRawUs = _clockMinusRawUs == null
        ? obs
        : _clockMinusRawUs! * 0.8 + obs * 0.2;

    if (lastRaw != null && lastClock != null && _vsyncPeriodUs == null) {
      final dRaw = (rawUs - lastRaw).toDouble();
      final dClock = (clockUs - lastClock).toDouble();
      if (dClock > 1000 && dRaw > 0) {
        // Consecutive frames differ by k vsync periods; recover the period.
        final k = (dRaw / dClock).round().clamp(1, 4);
        final period = dRaw / k;
        if (period >= 4000 && period <= 20000) {
          _vsyncPeriodUs = period;
        }
      }
    }
  }

  void _scheduleFrameWithLimit({required bool forced}) {
    if (!forced && !framesEnabled) return;

    // EXPERIMENT (1.0.5.36): frame rate cap disabled entirely — every frame
    // request goes straight through to the engine. Purpose: isolate whether
    // the 45fps limiter itself was the drag-frame-rate bottleneck. Restore
    // the capped path below after the comparison is done.
    _scheduleImmediateFrame(forced: forced);
  }

  // ignore: unused_element
  void _scheduleFrameWithLimitCapped({required bool forced}) {
    if (!forced && !framesEnabled) return;

    if (forced) {
      _delayedForcedFrame = true;
    }

    final lastBeginFrameUs = _lastBeginFrameUs;
    if (lastBeginFrameUs == null) {
      _scheduleImmediateFrame(forced: forced);
      return;
    }

    final elapsedUs = _clock.elapsedMicroseconds - lastBeginFrameUs;
    final remainingUs = _minFrameIntervalUs - elapsedUs;
    if (remainingUs <= 0) {
      _scheduleImmediateFrame(forced: forced || _delayedForcedFrame);
      return;
    }

    if (_delayedFrameTimer != null) return;
    final delayUs = _alignedDelayUs(remainingUs, _clock.elapsedMicroseconds);
    _delayedFrameTimer = Timer(Duration(microseconds: delayUs), () {
      _delayedFrameTimer = null;
      final shouldForce = _delayedForcedFrame;
      _scheduleImmediateFrame(forced: shouldForce);
    });
  }

  /// Returns how long to wait so the Timer fires ~[_vsyncLeadUs] before the
  /// first vsync at or after `now + remainingUs`. Falls back to the raw
  /// remaining time until the vsync model has been learned.
  int _alignedDelayUs(int remainingUs, int nowClockUs) {
    final period = _vsyncPeriodUs;
    final offset = _clockMinusRawUs;
    if (period == null || offset == null) return remainingUs;

    final budgetClock = nowClockUs + remainingUs.toDouble();
    final firstVsyncK = ((budgetClock - offset) / period).ceil();
    final vsyncClock = firstVsyncK * period + offset;
    final delay = vsyncClock - _vsyncLeadUs - nowClockUs;
    if (delay <= 0) {
      // Target vsync is imminent; request now and let the engine catch it.
      return remainingUs;
    }
    return delay.round();
  }

  void _scheduleImmediateFrame({required bool forced}) {
    _delayedForcedFrame = false;
    if (forced) {
      super.scheduleForcedFrame();
    } else {
      super.scheduleFrame();
    }
  }
}
