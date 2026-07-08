import 'event_detection_models.dart';

class LegacyShakeEventDetectorAdapter {
  final String detectorId;
  final String sourceId;

  String? _currentEventId;
  DateTime? _startedAt;

  LegacyShakeEventDetectorAdapter({
    this.detectorId = 'legacy_shake_detection_adapter',
    this.sourceId = 'nied',
  });

  EventDetection ingestLegacyState({
    required String stageName,
    required DateTime observedAt,
    required Iterable<String> stationIds,
    required int maxIntensity,
    required int weakCount,
    required int detectedCount,
    required int strongCount,
    Map<String, Object?> metadata = const {},
  }) {
    final state = _mapStage(stageName);
    final members = List<String>.unmodifiable(stationIds);
    if (state == EventDetectionState.idle) {
      if (_currentEventId == null) {
        return _idle(observedAt, metadata: metadata);
      }
      final ended = EventDetection(
        detectorId: detectorId,
        sourceId: sourceId,
        eventId: _currentEventId,
        state: EventDetectionState.ended,
        observedAt: observedAt,
        startedAt: _startedAt,
        updatedAt: observedAt,
        endedAt: observedAt,
        memberStationIds: members,
        detectionScore: 0,
        maxIntensity: maxIntensity,
        reasonCodes: const {'legacy_stage_idle'},
        metadata: metadata,
      );
      reset();
      return ended;
    }

    _currentEventId ??= '$sourceId-${observedAt.toIso8601String()}';
    _startedAt ??= observedAt;
    return EventDetection(
      detectorId: detectorId,
      sourceId: sourceId,
      eventId: _currentEventId,
      state: state,
      observedAt: observedAt,
      startedAt: _startedAt,
      updatedAt: observedAt,
      memberStationIds: members,
      detectionScore: _legacyScore(
        weakCount: weakCount,
        detectedCount: detectedCount,
        strongCount: strongCount,
      ),
      maxIntensity: maxIntensity,
      reasonCodes: {'legacy_stage_$stageName'},
      metadata: metadata,
    );
  }

  void reset() {
    _currentEventId = null;
    _startedAt = null;
  }

  EventDetection _idle(
    DateTime observedAt, {
    Map<String, Object?> metadata = const {},
  }) {
    return EventDetection(
      detectorId: detectorId,
      sourceId: sourceId,
      eventId: null,
      state: EventDetectionState.idle,
      observedAt: observedAt,
      metadata: metadata,
    );
  }

  EventDetectionState _mapStage(String stageName) {
    return switch (stageName) {
      'weak' => EventDetectionState.candidate,
      'detected' => EventDetectionState.confirmed,
      'strong' => EventDetectionState.strong,
      _ => EventDetectionState.idle,
    };
  }

  double _legacyScore({
    required int weakCount,
    required int detectedCount,
    required int strongCount,
  }) {
    return weakCount + detectedCount * 2.0 + strongCount * 3.0;
  }
}
