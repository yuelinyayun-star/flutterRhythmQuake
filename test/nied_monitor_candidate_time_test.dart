import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

void main() {
  test('GIF live candidates use latest_time without local projection', () {
    final latest = DateTime(2026, 6, 27, 2, 18, 2);

    final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
      latestTime: latest,
    );

    expect(candidates, hasLength(30));
    expect(candidates.first, latest);
    expect(candidates[1], latest.subtract(const Duration(seconds: 1)));
  });

  test(
    'GIF live candidates use projected local time before latest_time jumps',
    () {
      final latest = DateTime(2026, 6, 27, 2, 18, 2);
      final projected = DateTime(2026, 6, 27, 2, 18, 4);

      final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
        latestTime: latest,
        projectedTime: projected,
      );

      expect(candidates.take(4), [
        projected,
        DateTime(2026, 6, 27, 2, 18, 3),
        latest,
        latest.subtract(const Duration(seconds: 1)),
      ]);
      expect(candidates.toSet(), hasLength(candidates.length));
    },
  );

  test('GIF live candidates catch up from last success in order', () {
    final previous = DateTime(2026, 6, 27, 2, 18, 2);
    final latest = DateTime(2026, 6, 27, 2, 18, 3);
    final projected = DateTime(2026, 6, 27, 2, 18, 5);

    final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
      latestTime: latest,
      projectedTime: projected,
      previousFrameTime: previous,
    );

    expect(candidates.take(3), [
      DateTime(2026, 6, 27, 2, 18, 3),
      DateTime(2026, 6, 27, 2, 18, 4),
      projected,
    ]);
    expect(candidates.toSet(), hasLength(candidates.length));
  });

  test(
    'GIF live candidates cap small local projection catch-up for low load',
    () {
      final previous = DateTime(2026, 6, 27, 2, 18, 2);
      final latest = DateTime(2026, 6, 27, 2, 18, 2);
      final projected = DateTime(2026, 6, 27, 2, 18, 9);

      final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
        latestTime: latest,
        projectedTime: projected,
        previousFrameTime: previous,
      );

      expect(candidates.take(5), [
        DateTime(2026, 6, 27, 2, 18, 3),
        DateTime(2026, 6, 27, 2, 18, 4),
        DateTime(2026, 6, 27, 2, 18, 5),
        DateTime(2026, 6, 27, 2, 18, 6),
        DateTime(2026, 6, 27, 2, 18, 7),
      ]);
    },
  );

  test('GIF live candidates jump large local projection gaps', () {
    final previous = DateTime(2026, 6, 27, 2, 18, 4);
    final latest = DateTime(2026, 6, 27, 2, 18, 8);
    final projected = DateTime(2026, 6, 27, 2, 18, 30);

    final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
      latestTime: latest,
      projectedTime: projected,
      previousFrameTime: previous,
    );

    expect(candidates, [projected, latest]);
    expect(candidates, isNot(contains(previous)));
    expect(candidates.any((time) => time.isBefore(previous)), isFalse);
  });
}
