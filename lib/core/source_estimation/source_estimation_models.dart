import 'package:latlong2/latlong.dart';

import '../event_detection/event_detection_models.dart';
import 'station_observation_history.dart';

enum StationValueType { jmaShindo, mmi, pga, pgv, pgd, custom }

enum StationSensorRole { unspecified, surface, borehole, offshore, mobile }

enum StationLifecycleState { idle, rising, triggered, strong, ended }

enum ObservationOrigin {
  niedGifLayer,
  officialWaveform,
  stationFeed,
  derived,
  unknown,
}

class ObservationProvenance {
  const ObservationProvenance({
    required this.origin,
    required this.quantity,
    this.layerId,
    this.isIndependentPhysicalMeasurement = false,
    this.qualityFlags = const {},
  });

  final ObservationOrigin origin;
  final StationValueType quantity;
  final String? layerId;
  final bool isIndependentPhysicalMeasurement;
  final Set<String> qualityFlags;

  bool get mayBeUsedAsIndependentEvidence =>
      isIndependentPhysicalMeasurement &&
      origin != ObservationOrigin.derived &&
      !qualityFlags.contains('derived_from_shindo');
}

class SensorSelection {
  const SensorSelection({
    this.allowedRoles = const {
      StationSensorRole.surface,
      StationSensorRole.borehole,
      StationSensorRole.offshore,
      StationSensorRole.mobile,
      StationSensorRole.unspecified,
    },
  });

  const SensorSelection.surfaceOnly()
    : allowedRoles = const {StationSensorRole.surface};

  final Set<StationSensorRole> allowedRoles;

  bool accepts(SeismicStationDescriptor descriptor) =>
      allowedRoles.contains(descriptor.sensorRole);
}

class SeismicStationDescriptor {
  final String stationId;
  final String code;
  final String sourceId;
  final String network;
  final LatLng coordinate;
  final double? elevationM;
  final StationSensorRole sensorRole;
  final Map<String, String> tags;

  const SeismicStationDescriptor({
    required this.stationId,
    required this.code,
    required this.sourceId,
    required this.network,
    required this.coordinate,
    this.elevationM,
    this.sensorRole = StationSensorRole.unspecified,
    this.tags = const {},
  });
}

class SeismicStationSample {
  final SeismicStationDescriptor descriptor;
  final DateTime observedAt;
  final DateTime? receivedAt;
  final StationValueType valueType;
  final double? value;
  final double? observedPga;
  final double? observedPgv;
  final double? observedPgd;
  final int? rawLevel;
  final int? detectLevel;
  final double activity;
  final int ascend;
  final bool isTriggered;
  final ObservationTimeInterval? firstRiseInterval;
  final ObservationTimeInterval? firstTriggerInterval;
  final Set<String> qualityFlags;
  final Map<StationValueType, ObservationProvenance> provenance;

  const SeismicStationSample({
    required this.descriptor,
    required this.observedAt,
    this.receivedAt,
    required this.valueType,
    this.value,
    this.observedPga,
    this.observedPgv,
    this.observedPgd,
    this.rawLevel,
    this.detectLevel,
    this.activity = 0,
    this.ascend = 0,
    this.isTriggered = false,
    this.firstRiseInterval,
    this.firstTriggerInterval,
    this.qualityFlags = const {},
    this.provenance = const {},
  });
}

class SeismicStationEventRecord {
  final SeismicStationDescriptor descriptor;
  DateTime firstObservedAt;
  ObservationTimeInterval? firstRiseInterval;
  ObservationTimeInterval? firstTriggerInterval;
  DateTime? peakAt;
  DateTime? lastObservedAt;
  DateTime? endAt;
  double? peakValue;
  double? lastValue;
  double? lastPga;
  double? lastPgv;
  double? lastPgd;
  int? lastRawLevel;
  int? lastDetectLevel;
  double lastActivity;
  int lastAscend;
  int sampleCount;
  StationLifecycleState state;
  final Set<String> qualityFlags;
  final StationObservationHistory observationHistory;
  final Map<StationValueType, ObservationProvenance> provenance;

  SeismicStationEventRecord({
    required this.descriptor,
    required this.firstObservedAt,
    DateTime? firstRiseAt,
    DateTime? firstTriggerAt,
    ObservationTimeInterval? firstRiseInterval,
    ObservationTimeInterval? firstTriggerInterval,
    this.peakAt,
    this.lastObservedAt,
    this.endAt,
    this.peakValue,
    this.lastValue,
    this.lastPga,
    this.lastPgv,
    this.lastPgd,
    this.lastRawLevel,
    this.lastDetectLevel,
    this.lastActivity = 0,
    this.lastAscend = 0,
    this.sampleCount = 0,
    this.state = StationLifecycleState.idle,
    Set<String>? qualityFlags,
    StationObservationHistory? observationHistory,
    Map<StationValueType, ObservationProvenance>? provenance,
  }) : firstRiseInterval = firstRiseInterval ?? _pointInterval(firstRiseAt),
       firstTriggerInterval =
           firstTriggerInterval ?? _pointInterval(firstTriggerAt),
       qualityFlags = qualityFlags ?? <String>{},
       observationHistory = observationHistory ?? StationObservationHistory(),
       provenance = provenance ?? <StationValueType, ObservationProvenance>{};

  DateTime? get firstRiseAt => firstRiseInterval?.end;
  DateTime? get firstTriggerAt => firstTriggerInterval?.end;
  bool get hasTriggered => firstTriggerInterval != null;
  bool get isActiveLike =>
      state == StationLifecycleState.rising ||
      state == StationLifecycleState.triggered ||
      state == StationLifecycleState.strong;
}

ObservationTimeInterval? _pointInterval(DateTime? value) =>
    value == null ? null : ObservationTimeInterval(start: value, end: value);

class SourceEstimate {
  final double latitude;
  final double longitude;
  final double? depthKm;
  final double? magnitude;
  final DateTime? originTime;
  final double confidence;
  final String method;
  final int supportingStationCount;
  final Map<String, Object?> diagnostics;

  const SourceEstimate({
    required this.latitude,
    required this.longitude,
    this.depthKm,
    this.magnitude,
    this.originTime,
    required this.confidence,
    required this.method,
    required this.supportingStationCount,
    this.diagnostics = const {},
  });
}

class SourceEstimationRequest {
  final String sourceId;
  final String eventId;
  final DateTime observedAt;
  final String stageName;
  final int maxShindo;
  final List<SeismicStationEventRecord> stations;
  final Map<String, Object?> metadata;
  final SensorSelection sensorSelection;

  const SourceEstimationRequest({
    required this.sourceId,
    required this.eventId,
    required this.observedAt,
    required this.stageName,
    required this.maxShindo,
    required this.stations,
    this.metadata = const {},
    this.sensorSelection = const SensorSelection(),
  });
}

class SeismicActiveEvent {
  final String eventId;
  final String sourceId;
  final DateTime startedAt;
  DateTime updatedAt;
  DateTime? endedAt;
  String stageName;
  int maxShindo;
  SourceEstimate? estimate;
  final Map<String, SeismicStationEventRecord> stationRecords;
  final Map<String, Object?> metadata;

  SeismicActiveEvent({
    required this.eventId,
    required this.sourceId,
    required this.startedAt,
    required this.updatedAt,
    required this.stageName,
    required this.maxShindo,
    Map<String, SeismicStationEventRecord>? stationRecords,
    Map<String, Object?>? metadata,
    this.estimate,
    this.endedAt,
  }) : stationRecords = stationRecords ?? <String, SeismicStationEventRecord>{},
       metadata = metadata ?? <String, Object?>{};

  bool get isClosed => endedAt != null;

  List<SeismicStationEventRecord> get records =>
      stationRecords.values.toList(growable: false);
}
