import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/replay/knet_gif_domain_alignment.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_archive.dart';
import 'package:flutterrhythmquake/core/replay/knet_waveform_features.dart';

void main() {
  test('selects lag with maximum matches and reports shindo bias', () {
    final start = DateTime.utc(2026, 6, 20, 12);
    final aligner = KnetGifDomainAligner(
      lagCandidatesSeconds: const [-1, 0, 1],
    );
    final report = aligner.align(
      eventId: 'event-a',
      waveformSeries: [
        _series(
          stationCode: 'TST001',
          start: start,
          intensities: const [1, 2, 3],
        ),
      ],
      gifObservations: [
        _gif('TST001', start.add(const Duration(seconds: 1)), 1.5),
        _gif('TST001', start.add(const Duration(seconds: 2)), 2.5),
        _gif('TST001', start.add(const Duration(seconds: 3)), 3.5),
      ],
    );

    expect(report.schemaVersion, knetGifDomainAlignmentVersion);
    expect(report.stationReports, hasLength(1));
    final station = report.stationReports.single;
    expect(station.bestLagSeconds, 1);
    expect(station.sampleCount, 3);
    expect(station.meanDifferenceGifMinusWaveform, closeTo(0.5, 1e-9));
    expect(station.meanAbsoluteDifference, closeTo(0.5, 1e-9));
    expect(station.rmse, closeTo(0.5, 1e-9));
    expect(report.summary.sampleCount, 3);
    expect(report.summary.stationCount, 1);
  });

  test('keeps missing waveform stations in summary', () {
    final start = DateTime.utc(2026, 6, 20, 12);
    final report = const KnetGifDomainAligner(lagCandidatesSeconds: [0]).align(
      eventId: 'event-b',
      waveformSeries: [
        _series(stationCode: 'TST001', start: start, intensities: const [1]),
      ],
      gifObservations: [
        _gif('TST001', start, 1.1),
        _gif('MISSING', start, 2.0),
      ],
    );

    expect(report.summary.sampleCount, 1);
    expect(report.summary.missingWaveStations, ['MISSING:surface']);
  });

  test('does not mix surface and borehole series', () {
    final start = DateTime.utc(2026, 6, 20, 12);
    final report = const KnetGifDomainAligner(lagCandidatesSeconds: [0]).align(
      eventId: 'event-c',
      waveformSeries: [
        _series(
          stationCode: 'TST001',
          start: start,
          intensities: const [1],
          sensorRole: KnetSensorRole.borehole,
        ),
        _series(
          stationCode: 'TST001',
          start: start,
          intensities: const [4],
          sensorRole: KnetSensorRole.surface,
        ),
      ],
      gifObservations: [_gif('TST001', start, 4.2)],
    );

    expect(report.stationReports, hasLength(1));
    expect(report.stationReports.single.sensorRole, KnetSensorRole.surface);
    expect(
      report.stationReports.single.meanDifferenceGifMinusWaveform,
      closeTo(0.2, 1e-9),
    );
  });
}

KnetWaveformFeatureSeries _series({
  required String stationCode,
  required DateTime start,
  required List<double> intensities,
  KnetSensorRole sensorRole = KnetSensorRole.surface,
}) {
  return KnetWaveformFeatureSeries(
    stationCode: stationCode,
    network: sensorRole == KnetSensorRole.borehole
        ? KnetNetwork.kikNet
        : KnetNetwork.knet,
    sensorRole: sensorRole,
    stationLatitude: 35,
    stationLongitude: 140,
    sampleStartTimeUtc: start,
    samplingHz: 100,
    sourcePaths: const ['waveform.zip'],
    availableComponents: const ['NS', 'EW', 'UD'],
    seconds: [
      for (var index = 0; index < intensities.length; index++)
        KnetWaveformSecondFeature(
          secondIndex: index,
          startTimeUtc: start.add(Duration(seconds: index)),
          pgaGal: (10 + index).toDouble(),
          maxHorizontalAccelerationGal: (9 + index).toDouble(),
          pgvCms: (1 + index).toDouble(),
          rmsAccelerationGal: (2 + index).toDouble(),
          energyRatioToPreviousBaseline: index == 0 ? null : 2,
          jmaIntensityApprox: intensities[index],
          qualityFlags: const [],
        ),
    ],
    qualityFlags: const ['jma_intensity_unfiltered_duration_proxy'],
    processingVersion: knetWaveformFeatureVersion,
  );
}

GifDecodedStationSecond _gif(
  String stationCode,
  DateTime time,
  double shindo,
) => GifDecodedStationSecond(
  stationCode: stationCode,
  observedAtUtc: time,
  gifDecodedShindo: shindo,
);
