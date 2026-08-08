import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/widgets/map/source_dashboard.dart';

void main() {
  test(
    'NIED freshness follows frame progress instead of absolute data time',
    () {
      final tracker = DataProgressFreshnessTracker();
      final observedAt = DateTime.utc(2026, 7, 28, 8);
      final oldButAdvancingFrame = DateTime(2026, 7, 28, 15);

      expect(
        tracker.update(
          source: 'lmoni',
          frameTime: oldButAdvancingFrame,
          now: observedAt,
        ),
        isTrue,
      );
      expect(
        tracker.update(
          source: 'lmoni',
          frameTime: oldButAdvancingFrame.add(const Duration(seconds: 1)),
          now: observedAt.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );
    },
  );

  test('station freshness becomes stale after three seconds without data', () {
    final tracker = DataProgressFreshnessTracker();
    final observedAt = DateTime.utc(2026, 7, 28, 8);
    final frame = DateTime(2026, 7, 28, 15);

    tracker.update(source: 'lmoni', frameTime: frame, now: observedAt);

    expect(
      tracker.update(
        source: 'lmoni',
        frameTime: frame,
        now: observedAt.add(const Duration(seconds: 2)),
      ),
      isTrue,
    );
    expect(
      tracker.update(
        source: 'lmoni',
        frameTime: frame,
        now: observedAt.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
  });

  test('NIED freshness resets when the active source changes', () {
    final tracker = DataProgressFreshnessTracker();
    final observedAt = DateTime.utc(2026, 7, 28, 8);

    expect(
      tracker.update(
        source: 'lmoni',
        frameTime: DateTime(2026, 7, 28, 15),
        now: observedAt,
      ),
      isTrue,
    );
    expect(
      tracker.update(
        source: 'yahoo',
        frameTime: null,
        now: observedAt.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
  });
}
