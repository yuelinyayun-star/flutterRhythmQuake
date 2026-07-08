import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/event_detection/event_detection_models.dart';
import 'package:flutterrhythmquake/core/event_detection/legacy_shake_event_detector_adapter.dart';

void main() {
  test(
    'legacy adapter maps current shake stages without starting sources early',
    () {
      final adapter = LegacyShakeEventDetectorAdapter();
      final t0 = DateTime(2026, 6, 20, 12);

      final idle = adapter.ingestLegacyState(
        stageName: 'idle',
        observedAt: t0,
        stationIds: const [],
        maxIntensity: -1,
        weakCount: 0,
        detectedCount: 0,
        strongCount: 0,
      );
      expect(idle.state, EventDetectionState.idle);
      expect(idle.shouldStartSourceEstimation, isFalse);

      final weak = adapter.ingestLegacyState(
        stageName: 'weak',
        observedAt: t0.add(const Duration(seconds: 1)),
        stationIds: const ['A'],
        maxIntensity: 0,
        weakCount: 1,
        detectedCount: 0,
        strongCount: 0,
      );
      expect(weak.state, EventDetectionState.candidate);
      expect(weak.shouldStartSourceEstimation, isFalse);
      expect(weak.eventId, isNotNull);

      final confirmed = adapter.ingestLegacyState(
        stageName: 'detected',
        observedAt: t0.add(const Duration(seconds: 2)),
        stationIds: const ['A', 'B'],
        maxIntensity: 1,
        weakCount: 0,
        detectedCount: 2,
        strongCount: 0,
      );
      expect(confirmed.state, EventDetectionState.confirmed);
      expect(confirmed.shouldStartSourceEstimation, isTrue);
      expect(confirmed.eventId, weak.eventId);

      final strong = adapter.ingestLegacyState(
        stageName: 'strong',
        observedAt: t0.add(const Duration(seconds: 3)),
        stationIds: const ['A', 'B', 'C'],
        maxIntensity: 4,
        weakCount: 0,
        detectedCount: 0,
        strongCount: 3,
      );
      expect(strong.state, EventDetectionState.strong);
      expect(strong.shouldStartSourceEstimation, isTrue);
      expect(strong.eventId, weak.eventId);
    },
  );

  test('legacy adapter emits ended once when returning to idle', () {
    final adapter = LegacyShakeEventDetectorAdapter();
    final t0 = DateTime(2026, 6, 20, 12);

    final active = adapter.ingestLegacyState(
      stageName: 'detected',
      observedAt: t0,
      stationIds: const ['A', 'B'],
      maxIntensity: 1,
      weakCount: 0,
      detectedCount: 2,
      strongCount: 0,
    );
    final ended = adapter.ingestLegacyState(
      stageName: 'idle',
      observedAt: t0.add(const Duration(seconds: 1)),
      stationIds: const [],
      maxIntensity: -1,
      weakCount: 0,
      detectedCount: 0,
      strongCount: 0,
    );
    final idle = adapter.ingestLegacyState(
      stageName: 'idle',
      observedAt: t0.add(const Duration(seconds: 2)),
      stationIds: const [],
      maxIntensity: -1,
      weakCount: 0,
      detectedCount: 0,
      strongCount: 0,
    );

    expect(ended.state, EventDetectionState.ended);
    expect(ended.eventId, active.eventId);
    expect(idle.state, EventDetectionState.idle);
    expect(idle.eventId, isNull);
  });
}
