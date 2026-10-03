import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/app_edition.dart';
import 'package:flutterrhythmquake/models/station_history_frame.dart';
import 'package:flutterrhythmquake/services/station_history_capture.dart';

// Empty transport snapshots verify gating, not simulated station observations.
Map<String, dynamic> emptySnapshot(String kind) => {
  'kind': kind,
  if (kind == 'lpgm') 'topStations': [] else 'stations': [],
};

void main() {
  for (final kind in StationHistoryFrame.kinds) {
    test('$kind disabled publication neither builds nor caches a snapshot', () {
      final capture = StationHistoryCapture();
      final received = <StationHistoryFrame>[];
      capture.addListener(received.add);
      capture.setEnabled(kind, false);
      var builds = 0;
      capture.publish(kind, () {
        builds++;
        return emptySnapshot(kind);
      });
      expect(builds, 0);
      expect(received, isEmpty);
      expect(capture.latest, isEmpty);
    });

    test('$kind disable clears only the pending seed, not saved frames', () {
      final capture = StationHistoryCapture();
      final received = <StationHistoryFrame>[];
      capture.addListener(received.add);
      final allowed = kind != 'palert' || AppEdition.hasPAlertStations;
      final first = DateTime.utc(2026, 10, 3);
      capture.publish(kind, () => emptySnapshot(kind), receivedAt: first);
      expect(received.length, allowed ? 1 : 0);
      capture.setEnabled(kind, false);
      expect(capture.latest, isEmpty);
      capture.publish(kind, () => emptySnapshot(kind));
      expect(received.length, allowed ? 1 : 0);
      capture.setEnabled(kind, true);
      expect(
        capture.latest,
        isEmpty,
        reason: 'Re-enable cannot reuse the old seed',
      );
      final second = first.add(const Duration(seconds: 1));
      capture.publish(kind, () => emptySnapshot(kind), receivedAt: second);
      expect(received.length, allowed ? 2 : 0);
      if (allowed) {
        expect(received.first.receivedAt, first);
        expect(received.last.receivedAt, second);
        expect(capture.latest.single.receivedAt, second);
      }
    });
  }

  test('LPGM gate is independent of the NIED gate', () {
    final capture = StationHistoryCapture();
    capture.setEnabled('nied', false);
    capture.publish('nied', () => emptySnapshot('nied'));
    capture.publish('lpgm', () => emptySnapshot('lpgm'));
    expect(capture.latest.map((frame) => frame.kind), ['lpgm']);
    capture.setEnabled('lpgm', false);
    capture.setEnabled('nied', true);
    capture.publish('nied', () => emptySnapshot('nied'));
    capture.publish('lpgm', () => emptySnapshot('lpgm'));
    expect(capture.latest.map((frame) => frame.kind), ['nied']);
  });

  test('temporarily empty enabled frames still reach the recorder', () {
    final capture = StationHistoryCapture();
    final received = <StationHistoryFrame>[];
    capture.addListener(received.add);
    capture.publish('nied', () => emptySnapshot('nied'));
    capture.publish('nied', () => emptySnapshot('nied'));
    expect(received, hasLength(2));
    expect(capture.isEnabled('nied'), isTrue);
  });

  test('disabling during delivery blocks remaining listeners', () {
    final capture = StationHistoryCapture();
    final received = <StationHistoryFrame>[];
    capture.addListener((_) => capture.setEnabled('nied', false));
    capture.addListener(received.add);
    capture.publish('nied', () => emptySnapshot('nied'));
    expect(received, isEmpty);
    expect(capture.latest, isEmpty);
  });

  test('edition restriction cannot be bypassed by enabling capture', () {
    final capture = StationHistoryCapture();
    capture.setEnabled('palert', true);
    expect(capture.isEnabled('palert'), AppEdition.hasPAlertStations);
    expect(() => capture.setEnabled('unknown', false), throwsArgumentError);
  });
}
