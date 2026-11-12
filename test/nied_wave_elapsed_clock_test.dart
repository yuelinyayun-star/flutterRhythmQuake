import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/widgets/map/nied_wave_elapsed_clock.dart';

void main() {
  SourceEstimate sample(int id, double elapsed, {DateTime? origin}) =>
      SourceEstimate(
        latitude: 35,
        longitude: 140,
        confidence: 0.5,
        method: 'nied_dart_hyp_v1',
        supportingStationCount: 5,
        originTime: origin,
        diagnostics: {'selected_detection_id': id, 'wave_elapsed_s': elapsed},
      );

  test(
    'cached samples keep advancing through the 300 second hide boundary',
    () {
      var now = Duration.zero;
      final clock = NiedWaveElapsedClock(elapsed: () => now);
      final estimate = sample(1, 127);
      clock.sync([estimate]);
      for (var second = 1; second <= 180; second++) {
        now = Duration(seconds: second);
        // A fresh transfer object can still contain the same cached sample.
        clock.sync([sample(1, 127)]);
        expect(clock.elapsedFor(estimate), 127.0 + second);
      }
      expect(clock.elapsedFor(estimate), greaterThan(300));
      clock.clear();
      expect(clock.elapsedFor(estimate), isNull);
    },
  );

  test('new samples and separate sources have independent anchors', () {
    var now = Duration.zero;
    final clock = NiedWaveElapsedClock(elapsed: () => now);
    final first = sample(1, 10), second = sample(2, 50);
    clock.sync([first, second]);
    now = const Duration(seconds: 2);
    final updated = sample(1, 12.5);
    clock.sync([updated, second]);
    now = const Duration(seconds: 3);
    expect(clock.elapsedFor(updated), 13.5);
    expect(clock.elapsedFor(second), 53);
    clock.sync([updated]);
    expect(clock.elapsedFor(second), isNull);
    final corrected = sample(1, 12.5, origin: DateTime(2026));
    clock.sync([corrected]);
    expect(clock.elapsedFor(corrected), 12.5);
  });
}
