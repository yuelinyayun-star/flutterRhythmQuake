import 'dart:math' as math;

import 'nied_monitor.dart';
import 'palert_service.dart';
import 'shake_detection_service.dart';

/// Adapts current PGA estimates to the existing detector's level domain.
/// Raw P-Alert observations and display peak holds are never modified.
class PAlertDetector {
  PAlertDetector() {
    _engine.onDetectionSnapshotChanged = (value) {
      snapshot = value;
      onSnapshot?.call(value);
      _publishCwaIntensity();
    };
  }

  // Application-specific noise gate, independent of the marker threshold.
  static const double minimumDetectionPgaGal = 0.8;
  static const int minimumJointStations = 3;

  final _engine = ShakeDetectionService.forSource(
    'palert',
    minimumJointStations: minimumJointStations,
    allowActiveRiseShortcut: false,
  );
  final Map<String, NiedStation> _stations = {};
  final Map<String, int?> _currentCwaIndices = {};
  String _layout = '';
  ShakeDetectionSnapshot snapshot = ShakeDetectionService.idleSnapshot;
  void Function(ShakeDetectionSnapshot)? onSnapshot;
  void Function(int)? onCwaIntensityChanged;
  int confirmedCwaMaxShindo = -1;

  void setSensitivity(int value) => _engine.setSensitivity(value);

  void update(List<PAlertStation> input, {required DateTime now}) {
    final ordered = input.toList()..sort((a, b) => a.id.compareTo(b.id));
    final layout = ordered.map((s) => '${s.id}:${s.coordinate}').join('|');
    if (_layout != layout) {
      reset();
      _layout = layout;
      for (var i = 0; i < ordered.length; i++) {
        final station = ordered[i];
        _stations[station.id] = NiedStation(
          id: i,
          code: station.id,
          name: station.name,
          coordinate: station.coordinate,
          network: 'P-Alert',
          prefecture: station.area,
          expireSeconds: NiedStation.kaExpireSeconds,
        );
      }
      _engine.setStations(_stations.values.toList());
    }
    var changed = false;
    // A cached/duplicate sample cannot vote again when another station updates.
    for (final state in _stations.values) {
      state.activity = 0;
    }
    for (final station in ordered) {
      final state = _stations[station.id]!;
      final time = station.dataTime;
      final receivedAt = station.receivedAt;
      if (time == null ||
          receivedAt == null ||
          now.difference(receivedAt) > PAlertService.frameStaleAfter ||
          station.detectionLevel < 0) {
        changed = _invalidate(state) || changed;
        continue;
      }
      final previous = state.lastDataTime;
      if (previous != null && !time.isAfter(previous)) continue;
      if (previous != null) {
        final gap = time.difference(previous).inSeconds;
        if (gap > PAlertService.frameStaleAfter.inSeconds) {
          _invalidate(state);
        } else {
          // Missing source seconds remain unknown; they are not observations.
          for (var second = 1; second < math.min(gap, 60); second++) {
            state.lastDataTime = previous.add(Duration(seconds: second));
            state.update(-1);
          }
        }
      }
      state.lastDataTime = time;
      state.lastReceivedAt = receivedAt;
      state.lastUpdate = receivedAt;
      _currentCwaIndices[station.id] = station.cwaIntensityIndex;
      state.update(station.detectionLevel);
      // Keep the original level/history for rise detection and display. Only
      // the detection vote is gated, including when an old hold is active.
      if (station.pgaGal! < minimumDetectionPgaGal) state.activity = 0;
      changed = true;
    }
    if (changed) _engine.processUpdate();
    // PGV/CWA can change without changing the PGA level or engine snapshot.
    _publishCwaIntensity();
  }

  void expireStale(DateTime now) {
    var changed = false;
    for (final state in _stations.values) {
      state.activity = 0;
      final receivedAt = state.lastReceivedAt;
      if (receivedAt != null &&
          now.difference(receivedAt) > PAlertService.frameStaleAfter) {
        changed = _invalidate(state) || changed;
      }
    }
    if (changed) _engine.processUpdate();
    _publishCwaIntensity();
  }

  void _publishCwaIntensity() {
    var maxShindo = -1;
    for (final station in _stations.values) {
      if (!station.isActive || station.level < 0) continue;
      // Keep the detection session open during weak/unknown CWA frames,
      // without inventing an audible intensity or resetting its sound tiers.
      maxShindo = math.max(maxShindo, 0);
      final index = _currentCwaIndices[station.code];
      if (index == null || index < 0 || index > 9) continue;
      final shindo = index <= 4
          ? index
          : (index <= 6 ? 5 : (index <= 8 ? 6 : 7));
      maxShindo = math.max(maxShindo, shindo);
    }
    if (maxShindo == confirmedCwaMaxShindo) return;
    confirmedCwaMaxShindo = maxShindo;
    onCwaIntensityChanged?.call(maxShindo);
  }

  bool _invalidate(NiedStation state) {
    _currentCwaIndices.remove(state.code);
    final changed = state.level >= 0 || state.isActive;
    state.activeTimer?.cancel();
    state.isActive = false;
    state.level = -1;
    state.activity = 0;
    state.ascend = 0;
    state.triggerStamp = 0;
    state.detectState = 0;
    state.detectReason = '';
    state.abnormalUpdateCount = null;
    state.recentLevel.clear();
    state.lastDataTime = null;
    state.lastReceivedAt = null;
    return changed;
  }

  void reset() {
    _engine.reset(detachStations: true);
    _stations.clear();
    _currentCwaIndices.clear();
    _layout = '';
    snapshot = ShakeDetectionService.idleSnapshot;
    _publishCwaIntensity();
  }

  void dispose() {
    onSnapshot = null;
    onCwaIntensityChanged = null;
    reset();
  }
}
