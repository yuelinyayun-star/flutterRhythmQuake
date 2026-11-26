import 'dart:async';

import '../live_display_time.dart';

/// Schedules a UI refresh at the automatic product's original display deadline.
/// Rechecking on show accounts for Android suspend between Dart timer ticks.
class UsgsAutomaticProductExpiry {
  UsgsAutomaticProductExpiry(this.onExpired, {int Function()? elapsedUs})
    : _elapsedUs = elapsedUs ?? liveDisplayElapsedUs;

  final void Function() onExpired;
  final int Function() _elapsedUs;
  Timer? _timer;
  int? _deadlineUs;

  void start() {
    final lifetime = liveDisplayLifetime(
      LiveDisplayLifetime.usgsAutomaticProduct,
    );
    _deadlineUs = _elapsedUs() + lifetime.inMicroseconds;
    recheck();
  }

  void recheck() {
    final deadline = _deadlineUs;
    if (deadline == null) return;
    _timer?.cancel();
    final remaining = deadline - _elapsedUs();
    if (remaining > 0) {
      _timer = Timer(Duration(microseconds: remaining), recheck);
      return;
    }
    cancel();
    onExpired();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _deadlineUs = null;
  }
}
