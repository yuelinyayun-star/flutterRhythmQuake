enum StationTriggerState { idle, rising, triggered, strong, decaying, ended }

enum EventDetectionState { idle, candidate, confirmed, strong, ended, rejected }

enum ObservationSensorRole { unspecified, surface, borehole, offshore, mobile }

class ObservationTimeInterval {
  final DateTime start;
  final DateTime end;

  const ObservationTimeInterval({required this.start, required this.end});
}

class StationObservationFrame {
  final String stationId;
  final String code;
  final String sourceId;
  final DateTime observedAt;
  final double? latitude;
  final double? longitude;
  final double? intensity;
  final int? rawLevel;
  final int? detectLevel;
  final ObservationSensorRole sensorRole;
  final Set<String> qualityFlags;
  final Map<String, Object?> metadata;

  const StationObservationFrame({
    required this.stationId,
    required this.code,
    required this.sourceId,
    required this.observedAt,
    this.latitude,
    this.longitude,
    this.intensity,
    this.rawLevel,
    this.detectLevel,
    this.sensorRole = ObservationSensorRole.unspecified,
    this.qualityFlags = const {},
    this.metadata = const {},
  });

  bool get hasUsableObservation =>
      (intensity != null && intensity!.isFinite) ||
      rawLevel != null ||
      detectLevel != null;
}

class StationTriggerSnapshot {
  final String stationId;
  final String code;
  final String sourceId;
  final DateTime observedAt;
  final StationTriggerState state;
  final double? latitude;
  final double? longitude;
  final double? intensity;
  final int? rawLevel;
  final int? detectLevel;
  final double activity;
  final int ascend;
  final ObservationTimeInterval? firstRiseInterval;
  final ObservationTimeInterval? firstTriggerInterval;
  final Set<String> qualityFlags;
  final Set<String> reasonCodes;

  const StationTriggerSnapshot({
    required this.stationId,
    required this.code,
    required this.sourceId,
    required this.observedAt,
    required this.state,
    this.latitude,
    this.longitude,
    this.intensity,
    this.rawLevel,
    this.detectLevel,
    this.activity = 0,
    this.ascend = 0,
    this.firstRiseInterval,
    this.firstTriggerInterval,
    this.qualityFlags = const {},
    this.reasonCodes = const {},
  });

  bool get isActiveLike =>
      state == StationTriggerState.rising ||
      state == StationTriggerState.triggered ||
      state == StationTriggerState.strong;
}

abstract class StationTriggerDetector {
  String get detectorId;

  StationTriggerSnapshot update(StationObservationFrame observation);

  void resetStation(String stationId);

  void reset();
}

class EventDetection {
  final String detectorId;
  final String sourceId;
  final String? eventId;
  final EventDetectionState state;
  final DateTime observedAt;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final DateTime? endedAt;
  final List<String> memberStationIds;
  final double detectionScore;
  final int maxIntensity;
  final Set<String> reasonCodes;
  final Map<String, Object?> metadata;

  const EventDetection({
    required this.detectorId,
    required this.sourceId,
    required this.eventId,
    required this.state,
    required this.observedAt,
    this.startedAt,
    this.updatedAt,
    this.endedAt,
    this.memberStationIds = const [],
    this.detectionScore = 0,
    this.maxIntensity = -1,
    this.reasonCodes = const {},
    this.metadata = const {},
  });

  bool get hasActiveEvent =>
      state == EventDetectionState.candidate ||
      state == EventDetectionState.confirmed ||
      state == EventDetectionState.strong;

  bool get shouldStartSourceEstimation =>
      state == EventDetectionState.confirmed ||
      state == EventDetectionState.strong;
}

abstract class EventDetector {
  String get detectorId;

  EventDetection update({
    required DateTime observedAt,
    required List<StationTriggerSnapshot> stations,
  });

  void reset();
}
