import 'dart:async';

import 'package:flutter/widgets.dart';

class RhythmFrameRateBinding extends WidgetsFlutterBinding {
  RhythmFrameRateBinding._();

  static const int maxFramesPerSecond = 45;
  static const int _minFrameIntervalUs =
      Duration.microsecondsPerSecond ~/ maxFramesPerSecond;

  final Stopwatch _clock = Stopwatch()..start();
  Timer? _delayedFrameTimer;
  bool _delayedForcedFrame = false;
  int? _lastBeginFrameUs;

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
    _lastBeginFrameUs = _clock.elapsedMicroseconds;
    super.handleBeginFrame(rawTimeStamp);
  }

  void _scheduleFrameWithLimit({required bool forced}) {
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
    _delayedFrameTimer = Timer(Duration(microseconds: remainingUs), () {
      _delayedFrameTimer = null;
      final shouldForce = _delayedForcedFrame;
      _scheduleImmediateFrame(forced: shouldForce);
    });
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
