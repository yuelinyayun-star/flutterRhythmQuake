import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/intensity_reconstruction.dart';

void main() {
  group('KA level scale', () {
    test('uses the 21-value KA domain without the Scratch 30-value scale', () {
      expect(KaLevelScale.fromContinuousShindo(-3.1), -1);
      expect(KaLevelScale.fromContinuousShindo(-3.0), 0);
      expect(KaLevelScale.fromContinuousShindo(-2.9), 1);
      expect(KaLevelScale.fromContinuousShindo(-2.5), 2);
      expect(KaLevelScale.fromContinuousShindo(0.0), 7);
      expect(KaLevelScale.fromContinuousShindo(0.49), 7);
      expect(KaLevelScale.fromContinuousShindo(0.5), 8);
      expect(KaLevelScale.fromContinuousShindo(6.49), 19);
      expect(KaLevelScale.fromContinuousShindo(6.5), 20);
    });

    test('retains exact JMA class labels for KA levels', () {
      expect(KaLevelScale.jmaClassLabel(7), '0');
      expect(KaLevelScale.jmaClassLabel(8), '1');
      expect(KaLevelScale.jmaClassLabel(16), '5-');
      expect(KaLevelScale.jmaClassLabel(17), '5+');
      expect(KaLevelScale.jmaClassLabel(18), '6-');
      expect(KaLevelScale.jmaClassLabel(19), '6+');
      expect(KaLevelScale.jmaClassLabel(20), '7');
    });
  });

  test('extracts strict same-station same-second Yahoo/GIF pairs', () {
    final report = const KaCaptureInputExtractor().compareDirectory(
      'tmp/captures/20260614_165604_jst',
    );

    expect(report.yahooFrameCount, 1);
    expect(report.gifFrameCount, 1);
    expect(report.timestampMismatchFrameCount, 0);
    expect(report.pairs, isNotEmpty);
    expect(
      report.pairs.every(
        (pair) =>
            pair.yahoo.station.stationId == pair.gif.station.stationId &&
            pair.yahoo.observedAt == pair.gif.observedAt,
      ),
      isTrue,
    );
    expect(report.realtimeSnapshots, hasLength(1));
    expect(report.finalYahooPeaks, isNotEmpty);
    expect(report.finalGifPeaks, isNotEmpty);
  });
}
