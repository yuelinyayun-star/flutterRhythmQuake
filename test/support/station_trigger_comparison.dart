import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';

Object stationTriggerValues(StationTriggerSnapshot snapshot) {
  Object? interval(ObservationTimeInterval? value) => value == null
      ? null
      : [
          value.start.microsecondsSinceEpoch,
          value.start.isUtc,
          value.end.microsecondsSinceEpoch,
          value.end.isUtc,
        ];
  return [
    snapshot.stationId,
    snapshot.code,
    snapshot.sourceId,
    snapshot.observedAt.microsecondsSinceEpoch,
    snapshot.observedAt.isUtc,
    snapshot.state.index,
    snapshot.latitude,
    snapshot.longitude,
    snapshot.intensity,
    snapshot.rawLevel,
    snapshot.detectLevel,
    snapshot.activity,
    snapshot.ascend,
    interval(snapshot.firstRiseInterval),
    interval(snapshot.firstTriggerInterval),
    snapshot.qualityFlags.toList()..sort(),
    snapshot.reasonCodes.toList()..sort(),
  ];
}
