import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

void main() {
  test('Lmoni metadata uses the same HTTPS endpoint as its viewer', () {
    final uri = Uri.parse(
      NiedMonitorService.latestFrameMetadataUrlForTest(
        source: 'lmoni',
        nonce: 123456,
      ),
    );

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.lmoni.bosai.go.jp');
    expect(uri.path, '/img_svr/webservice/server/pros/latest.json');
    expect(uri.queryParameters['_'], '123456');
  });

  test('KMONI metadata stays on the selected KMONI host', () {
    final uri = Uri.parse(
      NiedMonitorService.latestFrameMetadataUrlForTest(
        source: 'kmoni',
        nonce: 654321,
      ),
    );

    expect(uri.scheme, 'http');
    expect(uri.host, 'www.kmoni.bosai.go.jp');
    expect(uri.path, '/webservice/server/pros/latest.json');
    expect(uri.queryParameters['_'], '654321');
  });

  test('one live tick limits failed frame attempts', () {
    expect(NiedMonitorService.liveCandidateAttemptCountForTest(30), 3);
    expect(NiedMonitorService.liveCandidateAttemptCountForTest(2), 2);
    expect(NiedMonitorService.liveCandidateAttemptCountForTest(0), 0);
  });

  test('failed live fetch after a received frame requires upstream resync', () {
    final previous = DateTime(2026, 9, 13, 17, 45, 30);

    expect(
      NiedMonitorService.shouldRequireUpstreamResyncForTest(
        replayEnabled: false,
        attempted: true,
        fetchedAny: false,
        previousFrameTime: previous,
      ),
      isTrue,
    );
    expect(
      NiedMonitorService.shouldRequireUpstreamResyncForTest(
        replayEnabled: true,
        attempted: true,
        fetchedAny: false,
        previousFrameTime: previous,
      ),
      isFalse,
    );
    expect(
      NiedMonitorService.shouldRequireUpstreamResyncForTest(
        replayEnabled: false,
        attempted: true,
        fetchedAny: false,
        previousFrameTime: null,
      ),
      isFalse,
    );
  });

  test('reconnected live fetch starts at authoritative upstream time', () {
    final previous = DateTime(2026, 9, 13, 17, 40, 0);
    final latest = DateTime(2026, 9, 13, 17, 45, 59);

    final candidates = NiedMonitorService.buildRecoveryCandidateTimesForTest(
      latest,
    );

    expect(candidates, [latest]);
    expect(
      candidates,
      isNot(contains(previous.add(const Duration(seconds: 1)))),
    );
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
          );

      expect(candidates.first, DateTime(2026, 8, 7, 21, 0, 2, 400));
      expect(candidates[1], DateTime(2026, 8, 7, 21, 0, 1, 400));
      expect(candidates.take(3), hasLength(3));
    },
  );

  test('local-time fallback drives both Lmoni and KMONI GIF URLs', () {
    final stamp = NiedMonitorService.buildLocalFallbackCandidateTimesForTest(
      correctedNow: DateTime.utc(2026, 8, 7, 12, 0, 2, 400),
    ).first;

    final lmoni = Uri.parse(
      NiedMonitorService.gifLayerUrlForTest(source: 'lmoni', jstTime: stamp),
    );
    final kmoni = Uri.parse(
      NiedMonitorService.gifLayerUrlForTest(source: 'kmoni', jstTime: stamp),
    );

    expect(lmoni.host, 'www.lmoni.bosai.go.jp');
    expect(lmoni.path, startsWith('/img_svr/data/map_img/RealTimeImg/'));
    expect(kmoni.host, 'www.kmoni.bosai.go.jp');
    expect(lmoni.path, contains('/20260807/20260807210002.jma_s.gif'));
    expect(kmoni.path, contains('/20260807/20260807210002.jma_s.gif'));
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

  test(
    'GIF live candidates preserve one-second history after falling behind',
    () {
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
    },
  );

  test('GIF live candidates catch up projected seconds in order', () {
    final previous = DateTime(2026, 6, 27, 2, 18, 2);
    final latest = DateTime(2026, 6, 27, 2, 18, 2);
    final projected = DateTime(2026, 6, 27, 2, 18, 9);

    final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
      latestTime: latest,
      projectedTime: projected,
      previousFrameTime: previous,
    );

    expect(candidates, [
      DateTime(2026, 6, 27, 2, 18, 3),
      DateTime(2026, 6, 27, 2, 18, 4),
      DateTime(2026, 6, 27, 2, 18, 5),
      DateTime(2026, 6, 27, 2, 18, 6),
      DateTime(2026, 6, 27, 2, 18, 7),
      DateTime(2026, 6, 27, 2, 18, 8),
      projected,
    ]);
  });

  test('GIF live candidates catch up large metadata gaps oldest-first', () {
    final previous = DateTime(2026, 6, 27, 2, 18, 4);
    final latest = DateTime(2026, 6, 27, 2, 18, 8);
    final projected = DateTime(2026, 6, 27, 2, 18, 30);

    final candidates = NiedMonitorService.buildLiveCandidateTimesForTest(
      latestTime: latest,
      projectedTime: projected,
      previousFrameTime: previous,
    );

    expect(candidates, [
      DateTime(2026, 6, 27, 2, 18, 5),
      DateTime(2026, 6, 27, 2, 18, 6),
      DateTime(2026, 6, 27, 2, 18, 7),
      latest,
    ]);
    expect(candidates, isNot(contains(previous)));
    expect(candidates.any((time) => time.isBefore(previous)), isFalse);
  });
}
