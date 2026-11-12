import 'event_detection_models.dart';
import 'robust_station_trigger_detector.dart';

class NativeStationTriggerDetector implements BatchStationTriggerDetector {
  NativeStationTriggerDetector({
    this.detectorId = 'robust_station_trigger_v0',
    this.config = const RobustStationTriggerConfig(),
    this.collectTimings = false,
  }) {
    throw UnsupportedError('Native station trigger session requires Windows');
  }
  static bool get supported => false;
  static Map<String, int> get globalDiagnostics => const {};
  @override
  final String detectorId;
  final RobustStationTriggerConfig config;
  final bool collectTimings;
  @override
  StationTriggerSnapshot update(StationObservationFrame observation) =>
      throw UnsupportedError('Native trigger session unavailable');
  @override
  List<StationTriggerSnapshot> updateBatch(
    List<StationObservationFrame> observations,
  ) => throw UnsupportedError('Native trigger session unavailable');
  @override
  void resetStation(String stationId) {}
  @override
  void reset() {}
  void dispose() {}
  Map<String, int> get diagnostics => const {};
}
