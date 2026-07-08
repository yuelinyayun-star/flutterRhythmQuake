import '../event_detection/event_detection_models.dart';

class SourceEstimationTriggerDecision {
  final String stageName;
  final String? eventId;
  final bool shouldIngestFrame;
  final Map<String, Object?> metadata;

  const SourceEstimationTriggerDecision({
    required this.stageName,
    required this.eventId,
    required this.shouldIngestFrame,
    this.metadata = const {},
  });

  bool get shouldRunEstimator => stageName != 'idle';
}

class SourceEstimationTriggerGate {
  const SourceEstimationTriggerGate();

  SourceEstimationTriggerDecision evaluate(EventDetection detection) {
    final stageName = switch (detection.state) {
      EventDetectionState.confirmed => 'confirmed',
      EventDetectionState.strong => 'strong',
      EventDetectionState.ended || EventDetectionState.rejected => 'idle',
      EventDetectionState.idle || EventDetectionState.candidate => 'idle',
    };
    final shouldIngestFrame =
        detection.shouldStartSourceEstimation ||
        detection.state == EventDetectionState.ended ||
        detection.state == EventDetectionState.rejected;

    return SourceEstimationTriggerDecision(
      stageName: stageName,
      eventId: detection.eventId,
      shouldIngestFrame: shouldIngestFrame,
      metadata: {
        'source_trigger_state': detection.state.name,
        'source_trigger_detector_id': detection.detectorId,
        'source_trigger_event_id': detection.eventId,
        'source_trigger_score': detection.detectionScore,
        'source_trigger_member_count': detection.memberStationIds.length,
      },
    );
  }
}
