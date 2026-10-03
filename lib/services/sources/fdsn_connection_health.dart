import 'fdsn_seedlink_info.dart';

/// Observation health is independent of transport keepalive replies.
class FdsnConnectionHealth {
  FdsnConnectionHealth({
    this.grace = const Duration(minutes: 2),
    this.sustain = const Duration(minutes: 1),
    this.cooldown = const Duration(minutes: 5),
  });

  final Duration grace;
  final Duration sustain;
  final Duration cooldown;
  final _observations = <String, ({DateTime observed, DateTime arrived})>{};
  DateTime? _started;
  DateTime? _lagSince;
  DateTime? _healthySince;
  DateTime? nextRecoveryAt;
  int recoveries = 0;
  int _failures = 0;

  DateTime? observationFor(String station) => _observations[station]?.observed;

  void connected(DateTime now) {
    _started = now;
    _lagSince = null;
    _healthySince = null;
    _observations.clear();
  }

  void observe(String station, DateTime observed, DateTime now) {
    // A clock error or a future packet is not evidence of an old backlog.
    if (observed.isAfter(now)) return;
    final previous = _observations[station];
    _observations[station] = (
      observed: previous != null && previous.observed.isAfter(observed)
          ? previous.observed
          : observed,
      arrived: now,
    );
  }

  bool shouldRecover(DateTime now) {
    final started = _started;
    if (started == null || now.difference(started) < grace) return false;
    // Count stations, not packets: a single high-rate stale channel must not
    // force every healthy station on this socket to reconnect.
    final active = _observations.values
        .where((v) => now.difference(v.arrived) <= sustain)
        .toList(growable: false);
    if (active.isEmpty) {
      _lagSince = null;
      _healthySince = null;
      return false;
    }
    final stale = active
        .where((v) => now.difference(v.observed) > FdsnSeedLinkInfo.maxDataAge)
        .length;
    if (stale * 5 < active.length * 4) {
      _lagSince = null;
      // Reset backoff only after sustained broadly healthy observations.
      if (stale * 5 <= active.length) {
        _healthySince ??= now;
        if (now.difference(_healthySince!) >= cooldown) _failures = 0;
      } else {
        _healthySince = null;
      }
      return false;
    }
    _healthySince = null;
    _lagSince ??= now;
    if (now.difference(_lagSince!) < sustain ||
        (nextRecoveryAt != null && now.isBefore(nextRecoveryAt!))) {
      return false;
    }
    recoveries++;
    final multiplier = (1 << _failures.clamp(0, 3)).clamp(1, 6);
    nextRecoveryAt = now.add(cooldown * multiplier);
    _failures++;
    _lagSince = null;
    return true;
  }
}
