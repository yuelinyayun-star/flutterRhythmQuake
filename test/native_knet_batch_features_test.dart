import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/knet_batch.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_archive.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_features.dart';

void main() {
  test(
    'Rust K-NET group batch matches independent Dart loop for aligned axes',
    () {
      if (!Platform.isWindows ||
          !Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY')) {
        return;
      }
      const hz = 10.0;
      const count = 60;
      final ns = List<double>.generate(
        70,
        (i) => 1.5 + math.sin(i / 8) * (i < 35 ? 2 : 4),
      );
      final ew = List<double>.generate(65, (i) => -0.4 + math.cos(i / 6) * 3);
      final beforeNs = [...ns];
      final beforeEw = [...ew];
      final native = nativeKnetBatchFeatures(
        components: [ns, ew, null],
        starts: [5, 0, 0],
        offsetsGal: [1.5, -0.4, 0],
        sampleCount: count,
        samplesPerSecond: 10,
        samplingHz: hz,
        durationSeconds: 0.3,
        baselineSeconds: 3,
        epsilon: 1e-9,
      );
      expect(
        native,
        isNotNull,
        reason: 'Native batch symbol must be used, not fallback',
      );
      expect(native, hasLength(6));
      final alignedNs = List.generate(count, (i) => ns[i + 5] - 1.5);
      final alignedEw = List.generate(count, (i) => ew[i] + 0.4);
      final rmsHistory = <double>[];
      var vn = 0.0;
      var ve = 0.0;
      for (var sec = 0; sec < 6; sec++) {
        final vectors = <double>[];
        var pga = 0.0;
        var horizontalMax = 0.0;
        var pgv = 0.0;
        var sumSquare = 0.0;
        for (var i = sec * 10; i < (sec + 1) * 10; i++) {
          final n = alignedNs[i];
          final e = alignedEw[i];
          final horizontal = math.sqrt(n * n + e * e);
          final vector = math.sqrt(horizontal * horizontal);
          vectors.add(vector);
          pga = math.max(pga, vector);
          horizontalMax = math.max(horizontalMax, horizontal);
          sumSquare += vector * vector;
          vn += n / hz;
          ve += e / hz;
          pgv = math.max(pgv, math.sqrt(vn * vn + ve * ve));
        }
        final rms = math.sqrt(sumSquare / 10);
        double? ratio;
        if (rmsHistory.isNotEmpty) {
          final previous = rmsHistory.sublist(
            math.max(0, rmsHistory.length - 3),
          );
          final baseline = previous.reduce((a, b) => a + b) / previous.length;
          if (baseline > 1e-9) ratio = rms / baseline;
        }
        rmsHistory.add(rms);
        vectors.sort((a, b) => b.compareTo(a));
        final proxy = vectors[2] <= 0
            ? null
            : 2 * math.log(vectors[2]) / math.ln10 + 0.94;
        final actual = native![sec];
        expect(actual.pga, closeTo(pga, 1e-11), reason: 'PGA second $sec');
        expect(actual.horizontalPga, closeTo(horizontalMax, 1e-11));
        expect(actual.pgv, closeTo(pgv, 1e-11), reason: 'PGV second $sec');
        expect(actual.rms, closeTo(rms, 1e-11));
        if (ratio == null) {
          expect(actual.energyRatio, isNull);
        } else {
          expect(actual.energyRatio, closeTo(ratio, 1e-11));
        }
        if (proxy == null) {
          expect(actual.intensityProxy, isNull);
        } else {
          expect(actual.intensityProxy, closeTo(proxy, 1e-11));
        }
      }
      expect(
        ns,
        beforeNs,
        reason: 'Borrowed source data must remain immutable',
      );
      expect(ew, beforeEw);

      final start = DateTime.utc(2026, 10, 18, 8);
      final extractor = KnetWaveformFeatureExtractor(
        config: const KnetFeatureConfig(energyBaselineSeconds: 3),
      );
      final series = extractor.extract([
        _channel('NS', start, ns, 1.5),
        _channel('EW', start.add(const Duration(milliseconds: 500)), ew, -0.4),
      ]).single;
      expect(series.seconds, hasLength(6));
      expect(
        series.sampleStartTimeUtc,
        start.add(const Duration(milliseconds: 500)),
      );
      expect(series.qualityFlags, contains('missing_ud_component'));
      for (var i = 0; i < 6; i++) {
        expect(series.seconds[i].pgaGal, closeTo(native![i].pga, 1e-11));
        expect(series.seconds[i].pgvCms, closeTo(native[i].pgv, 1e-11));
        expect(
          series.seconds[i].rmsAccelerationGal,
          closeTo(native[i].rms, 1e-11),
        );
      }
    },
  );

  test('native empty/invalid group inputs decline safely', () {
    if (!Platform.isWindows ||
        !Platform.environment.containsKey('RQ_STATION_CORE_LIBRARY')) {
      return;
    }
    expect(
      nativeKnetBatchFeatures(
        components: [
          <double>[1, 2, 3],
          null,
          null,
        ],
        starts: [2, 0, 0],
        offsetsGal: [0, 0, 0],
        sampleCount: 3,
        samplesPerSecond: 3,
        samplingHz: 3,
        durationSeconds: 0.3,
        baselineSeconds: 3,
        epsilon: 1e-9,
      ),
      isNull,
    );
  });
}

KnetWaveformChannel _channel(
  String component,
  DateTime start,
  List<double> values,
  double offset,
) {
  return KnetWaveformChannel(
    sourcePath: '$component.test',
    format: KnetWaveformFormat.ascii,
    network: KnetNetwork.knet,
    stationCode: 'TESTKNET',
    stationLatitude: 35,
    stationLongitude: 140,
    stationHeightMeters: 1,
    eventOriginTimeUtc: start.subtract(const Duration(seconds: 10)),
    eventLatitude: 35,
    eventLongitude: 140,
    eventDepthKm: 10,
    eventMagnitude: 3,
    recordTimeUtc: start.add(const Duration(seconds: 15)),
    sampleStartTimeUtc: start,
    samplingHz: 10,
    durationSeconds: values.length / 10,
    component: component,
    sensorRole: KnetSensorRole.surface,
    scaleFactor: 1,
    headerMaxAccelerationGal: null,
    lastCorrectionUtc: null,
    memo: null,
    digitValues: values.map((v) => v.round()).toList(growable: false),
    accelerationGal: values,
    offsetGal: offset,
    dataPrecision: 'test',
    processingVersion: 'test',
  );
}
