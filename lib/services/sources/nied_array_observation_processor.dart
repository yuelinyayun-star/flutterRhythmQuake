import 'native_ka_history.dart';
import 'nied_monitor.dart';
import 'nied_gif_observation.dart';
import 'whews_station_service.dart';

/// Owns the native rolling observation processor and binds its result to the
/// existing station display views. Detection/hold management is a separate,
/// not-yet-migrated service; its current flags are commands to this processor.
class NiedArrayObservationProcessor {
  List<NiedStation> _stations = const [];
  List<NiedStation> get stations => _stations;
  NativeKaHistorySession? _native;
  bool _hasFrame = false;
  NativeKaHistorySession? get native => _hasFrame ? _native : null;

  void configure(List<NiedStation> stations) {
    _native?.dispose();
    _native = null;
    _hasFrame = false;
    _stations = stations;
    if (stations.isEmpty || !NativeKaHistorySession.supported) return;
    final owner = NativeKaHistorySession(stations.length);
    try {
      for (var i = 0; i < stations.length; i++) {
        owner.histories[i].replace(stations[i].recentLevel);
        owner.setShindoAbnormalCount(i, stations[i].abnormalUpdateCount);
        stations[i].recentLevel = owner.histories[i];
      }
      _native = owner;
    } catch (_) {
      owner.dispose();
      rethrow;
    }
  }

  void resetClock() => _native?.resetShindoClock();

  void resetState() {
    _native?.reset();
    _hasFrame = false;
  }

  /// Returns false only for an unported platform. Windows errors propagate.
  bool apply(WhewsStationFrame frame, {required DateTime receivedAt}) {
    final owner = _native;
    if (owner == null) return false;
    if (frame.values.length != _stations.length) {
      throw ArgumentError('NIED observation count does not match directory');
    }
    for (var i = 0; i < _stations.length; i++) {
      final station = _stations[i];
      owner.writeShindoInput(
        i,
        shindo: frame.values[i],
        expireSeconds: station.expireSeconds,
        isActive: station.isActive,
      );
    }
    owner.processShindoFrame(frame.dataTime.millisecondsSinceEpoch);
    _hasFrame = true;
    for (var i = 0; i < _stations.length; i++) {
      final station = _stations[i], flags = owner.observationFlags(i);
      station
        ..lastUpdate = frame.dataTime
        ..lastDataTime = frame.dataTime
        ..lastReceivedAt = receivedAt;
      if (flags & 2 != 0) station.isActive = false;
      if (flags & 1 != 0) station.continuousShindo = frame.values[i];
      station.applyKaHistoryResult(owner.result(i));
      if (frame.pga.length == _stations.length) {
        station.updateGifObservation(
          NiedGifObservation(
            layer: NiedGifLayer.peakAcceleration,
            pga: frame.pga[i],
          ),
        );
      } else {
        station.clearGifObservation(
          NiedGifLayer.peakAcceleration,
          qualityFlag: 'whews_missing_or_invalid',
        );
      }
      if (frame.pgv.length == _stations.length) {
        station.updateGifObservation(
          NiedGifObservation(
            layer: NiedGifLayer.peakVelocity,
            pgv: frame.pgv[i],
          ),
        );
      } else {
        station.clearGifObservation(
          NiedGifLayer.peakVelocity,
          qualityFlag: 'whews_missing_or_invalid',
        );
      }
    }
    return true;
  }

  void dispose() {
    _native?.dispose();
    _native = null;
    _hasFrame = false;
    _stations = const [];
  }
}
