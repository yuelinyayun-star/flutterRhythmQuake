import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_trigger.dart';

void main() {
  test(
    'source trigger gate starts only for confirmed or strong detections',
    () {
      const gate = SourceEstimationTriggerGate();
      final t0 = DateTime(2026, 6, 20, 12);

      SourceEstimationTriggerDecision decide(EventDetectionState state) {
        return gate.evaluate(
          EventDetection(
            detectorId: 'detector',
            sourceId: 'nied',
            eventId: 'event-1',
            state: state,
            observedAt: t0,
            memberStationIds: const ['A', 'B'],
            detectionScore: 3,
          ),
        );
      }

      final idle = decide(EventDetectionState.idle);
      expect(idle.stageName, 'idle');
      expect(idle.shouldIngestFrame, isFalse);
      expect(idle.shouldRunEstimator, isFalse);

      final candidate = decide(EventDetectionState.candidate);
      expect(candidate.stageName, 'idle');
      expect(candidate.shouldIngestFrame, isFalse);
      expect(candidate.shouldRunEstimator, isFalse);

      final confirmed = decide(EventDetectionState.confirmed);
      expect(confirmed.stageName, 'confirmed');
      expect(confirmed.shouldIngestFrame, isTrue);
      expect(confirmed.shouldRunEstimator, isTrue);
      expect(confirmed.eventId, 'event-1');

      final strong = decide(EventDetectionState.strong);
      expect(strong.stageName, 'strong');
      expect(strong.shouldIngestFrame, isTrue);
      expect(strong.shouldRunEstimator, isTrue);

      final ended = decide(EventDetectionState.ended);
      expect(ended.stageName, 'idle');
      expect(ended.shouldIngestFrame, isTrue);
      expect(ended.shouldRunEstimator, isFalse);

      final rejected = decide(EventDetectionState.rejected);
      expect(rejected.stageName, 'idle');
      expect(rejected.shouldIngestFrame, isTrue);
      expect(rejected.shouldRunEstimator, isFalse);
    },
  );
}
