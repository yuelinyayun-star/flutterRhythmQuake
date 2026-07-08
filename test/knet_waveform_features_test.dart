import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_archive.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_features.dart';

void main() {
  const extractor = KnetWaveformFeatureExtractor(
    config: KnetFeatureConfig(energyBaselineSeconds: 3),
  );

  test('builds per-second PGA PGV intensity proxy and energy ratio', () {
    final start = DateTime.utc(2026, 6, 20, 12);
    final channels = [
      _channel(
        component: 'NS',
        start: start,
        values: [...List<double>.filled(10, 1), ...List<double>.filled(10, 2)],
      ),
      _channel(
        component: 'EW',
        start: start,
        values: List<double>.filled(20, 0),
      ),
      _channel(
        component: 'UD',
        start: start,
        values: List<double>.filled(20, 0),
      ),
    ];

    final series = extractor.extract(channels).single;

    expect(series.processingVersion, knetWaveformFeatureVersion);
    expect(series.availableComponents, ['EW', 'NS', 'UD']);
    expect(
      series.qualityFlags,
      contains('jma_intensity_unfiltered_duration_proxy'),
    );
    expect(series.seconds, hasLength(2));
    expect(series.seconds[0].startTimeUtc, start);
    expect(series.seconds[0].pgaGal, closeTo(1, 1e-9));
    expect(series.seconds[0].maxHorizontalAccelerationGal, closeTo(1, 1e-9));
    expect(series.seconds[0].rmsAccelerationGal, closeTo(1, 1e-9));
    expect(series.seconds[0].pgvCms, closeTo(1, 1e-9));
    expect(series.seconds[0].jmaIntensityApprox, closeTo(0.94, 1e-9));
    expect(series.seconds[0].energyRatioToPreviousBaseline, isNull);
    expect(series.seconds[1].pgaGal, closeTo(2, 1e-9));
    expect(series.seconds[1].pgvCms, closeTo(3, 1e-9));
    expect(series.seconds[1].energyRatioToPreviousBaseline, closeTo(2, 1e-9));
    expect(
      series.seconds[1].jmaIntensityApprox,
      closeTo(2 * 0.3010299956639812 + 0.94, 1e-9),
    );
  });

  test('keeps missing component quality flags but still emits features', () {
    final start = DateTime.utc(2026, 6, 20, 12);
    final series = extractor.extract([
      _channel(
        component: 'NS',
        start: start,
        values: List<double>.filled(10, 4),
      ),
    ]).single;

    expect(series.seconds, hasLength(1));
    expect(series.seconds.single.pgaGal, closeTo(4, 1e-9));
    expect(series.qualityFlags, contains('missing_ew_component'));
    expect(series.qualityFlags, contains('missing_ud_component'));
  });

  test('separates KiK-net borehole and surface feature series', () {
    final start = DateTime.utc(2026, 6, 20, 12);
    final series = extractor.extract([
      _channel(
        component: 'NS',
        sensorRole: KnetSensorRole.borehole,
        start: start,
        values: List<double>.filled(10, 1),
      ),
      _channel(
        component: 'NS',
        sensorRole: KnetSensorRole.surface,
        start: start,
        values: List<double>.filled(10, 2),
      ),
    ]);

    expect(series, hasLength(2));
    expect(series.first.sensorRole, KnetSensorRole.borehole);
    expect(series.first.seconds.single.pgaGal, closeTo(1, 1e-9));
    expect(series.last.sensorRole, KnetSensorRole.surface);
    expect(series.last.seconds.single.pgaGal, closeTo(2, 1e-9));
  });
}

KnetWaveformChannel _channel({
  required String component,
  required DateTime start,
  required List<double> values,
  KnetSensorRole sensorRole = KnetSensorRole.surface,
}) {
  return KnetWaveformChannel(
    sourcePath: '$component.fixture',
    format: KnetWaveformFormat.ascii,
    network: sensorRole == KnetSensorRole.borehole
        ? KnetNetwork.kikNet
        : KnetNetwork.knet,
    stationCode: 'TST001',
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
    sensorRole: sensorRole,
    scaleFactor: 1,
    headerMaxAccelerationGal: null,
    lastCorrectionUtc: null,
    memo: null,
    digitValues: values.map((value) => value.round()).toList(growable: false),
    accelerationGal: values,
    offsetGal: 0,
    dataPrecision: 'test',
    processingVersion: 'test',
  );
}
