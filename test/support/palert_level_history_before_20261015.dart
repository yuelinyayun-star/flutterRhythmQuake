import 'dart:typed_data';

import 'package:flutterrhythmquake/core/source_estimation/palert_source_profile.dart';

/// Reference copied from PAlertService._heldLevelFor before native migration.
class DartPAlertLevelHistoryReference {
  List<String> ids = [];
  final Map<String, List<({DateTime time, int level})>> _history = {};

  void setStations(Iterable<String> next) {
    ids = next.toList(growable: false);
    _history.removeWhere((id, _) => !ids.contains(id));
  }

  Int32List process(
    DateTime timestamp,
    Map<String, double> pga,
    Map<String, double> pgv,
  ) {
    final out = Int32List(ids.length * 2)..fillRange(0, ids.length * 2, -1);
    for (var i = 0; i < ids.length; i++) {
      final value = pga[ids[i]];
      if (value == null) continue;
      final level = PAlertSourceProfile.level(value, pgv[ids[i]]);
      out[i * 2] = level;
      out[i * 2 + 1] = _heldLevelFor(ids[i], timestamp, level);
    }
    return out;
  }

  int _heldLevelFor(String stationId, DateTime timestamp, int currentLevel) {
    final samples = _history.putIfAbsent(stationId, () => []);
    final cutoff = timestamp.subtract(const Duration(seconds: 3));
    samples.removeWhere(
      (sample) =>
          sample.time.isBefore(cutoff) || sample.time.isAfter(timestamp),
    );
    if (currentLevel >= 0) samples.add((time: timestamp, level: currentLevel));
    if (samples.isEmpty) {
      _history.remove(stationId);
      return currentLevel;
    }
    return samples
        .map((sample) => sample.level)
        .reduce((a, b) => a > b ? a : b);
  }

  void clear() {
    ids = [];
    _history.clear();
  }
}
