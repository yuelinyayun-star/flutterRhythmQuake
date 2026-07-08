import 'dart:async';

import 'package:flutter/foundation.dart';

class EventAnimationClock {
  EventAnimationClock._();

  static final EventAnimationClock instance = EventAnimationClock._();

  final ValueNotifier<int> frame4Fps = ValueNotifier<int>(0);
  final ValueNotifier<int> blink2Fps = ValueNotifier<int>(0);
  final ValueNotifier<int> second1Fps = ValueNotifier<int>(0);

  Timer? _timer;
  int _leases = 0;
  int _frame = 0;

  bool get isRunning => _timer?.isActive == true;
  int get activeLeaseCount => _leases;

  EventAnimationLease acquire() {
    _leases++;
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _tick(),
    );
    return EventAnimationLease._(this);
  }

  ValueListenable<int> listenableForFrameRate(double requestedFps) {
    if (requestedFps <= 1) return second1Fps;
    if (requestedFps <= 2) return blink2Fps;
    return frame4Fps;
  }

  void _tick() {
    _frame++;
    frame4Fps.value = _frame;
    if (_frame.isEven) blink2Fps.value = _frame ~/ 2;
    if (_frame % 4 == 0) second1Fps.value = _frame ~/ 4;
  }

  void _release() {
    if (_leases <= 0) return;
    _leases--;
    if (_leases != 0) return;
    _timer?.cancel();
    _timer = null;
  }
}

class EventAnimationLease {
  EventAnimationClock? _clock;

  EventAnimationLease._(this._clock);

  void dispose() {
    final clock = _clock;
    if (clock == null) return;
    _clock = null;
    clock._release();
  }
}
