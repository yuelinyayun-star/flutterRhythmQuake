import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

void main() {
  test('GIF metadata time always comes from the Lmoni webservice', () {
    final uri = Uri.parse(
      NiedMonitorService.latestFrameMetadataUrlForTest(123456),
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'smi.lmoniexp.bosai.go.jp');
    expect(uri.path, '/webservice/server/pros/latest.json');
    expect(uri.queryParameters['_'], '123456');
  });

  test('one live tick limits failed frame attempts', () {
    expect(NiedMonitorService.liveCandidateAttemptCountForTest(30), 3);
    expect(NiedMonitorService.liveCandidateAttemptCountForTest(2), 2);
    expect(NiedMonitorService.liveCandidateAttemptCountForTest(0), 0);
  });

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
    'GIF requests use corrected local JST while Lmoni time is unavailable',
    () {
      final candidates =
          NiedMonitorService.buildLocalFallbackCandidateTimesForTest(
            correctedNow: DateTime.utc(2026, 8, 7, 12, 0, 2, 400),
            realtimeDelayMs: 1200,
          );

      expect(candidates.first, DateTime(2026, 8, 7, 21, 0, 1, 200));
      expect(candidates[1], DateTime(2026, 8, 7, 21, 0, 0, 200));
      expect(candidates.take(3), hasLength(3));
    },
  );

  test('local-time fallback drives both Lmoni and KMONI GIF URLs', () {
    final stamp = NiedMonitorService.buildLocalFallbackCandidateTimesForTest(
      correctedNow: DateTime.utc(2026, 8, 7, 12, 0, 2, 400),
      realtimeDelayMs: 1200,
    ).first;

    final lmoni = Uri.parse(
      NiedMonitorService.gifLayerUrlForTest(source: 'lmoni', jstTime: stamp),
    );
    final kmoni = Uri.parse(
      NiedMonitorService.gifLayerUrlForTest(source: 'kmoni', jstTime: stamp),
    );

    expect(lmoni.host, 'smi.lmoniexp.bosai.go.jp');
    expect(kmoni.host, 'www.kmoni.bosai.go.jp');
    expect(lmoni.path, contains('/20260807/20260807210001.jma_s.gif'));
    expect(kmoni.path, contains('/20260807/20260807210001.jma_s.gif'));
  });

  test(
    'GIF live candidates use Lmoni-anchored projection between metadata updates',
    () {
      final latest = DateTime(2026, 6, 27, 2, 18, 2);
      final projected = DateTime(2026, 6, 27, 2, 18, 4);

      final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
        latestTime: latest,
        projectedTime: projected,
      );

      expect(candidates.take(4), [
        latest,
        projected,
        DateTime(2026, 6, 27, 2, 18, 3),
        latest.subtract(const Duration(seconds: 1)),
      ]);
      expect(candidates.toSet(), hasLength(candidates.length));
    },
  );

  test('GIF live candidates jump to latest_time after falling behind', () {
    final previous = DateTime(2026, 6, 27, 2, 18, 2);
    final latest = DateTime(2026, 6, 27, 2, 18, 3);
    final projected = DateTime(2026, 6, 27, 2, 18, 5);

    final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
      latestTime: latest,
      projectedTime: projected,
      previousFrameTime: previous,
    );

    expect(candidates.take(3), [DateTime(2026, 6, 27, 2, 18, 3)]);
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
        DateTime(2026, 6, 27, 2, 18, 9),
        DateTime(2026, 6, 27, 2, 18, 8),
        DateTime(2026, 6, 27, 2, 18, 7),
        DateTime(2026, 6, 27, 2, 18, 6),
        DateTime(2026, 6, 27, 2, 18, 5),
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

    expect(candidates, [
      latest,
      DateTime(2026, 6, 27, 2, 18, 7),
      DateTime(2026, 6, 27, 2, 18, 6),
      DateTime(2026, 6, 27, 2, 18, 5),
    ]);
    expect(candidates, isNot(contains(previous)));
    expect(candidates.any((time) => time.isBefore(previous)), isFalse);
  });
}
