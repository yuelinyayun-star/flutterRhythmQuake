import 'dart:math' as math;

import 'knet_waveform_archive.dart';
import 'knet_waveform_features.dart';

const knetGifDomainAlignmentVersion = 'knet_gif_domain_alignment_v1';

class GifDecodedStationSecond {
  const GifDecodedStationSecond({
    required this.stationCode,
    required this.observedAtUtc,
    required this.gifDecodedShindo,
    this.sensorRole = KnetSensorRole.surface,
    this.qualityFlags = const [],
  });

  final String stationCode;
  final DateTime observedAtUtc;
  final double gifDecodedShindo;
  final KnetSensorRole sensorRole;
  final List<String> qualityFlags;

  Map<String, Object?> toJson() => {
    'stationCode': stationCode,
    'observedAtUtc': observedAtUtc.toIso8601String(),
    'gifDecodedShindo': gifDecodedShindo,
    'sensorRole': sensorRole.name,
    'qualityFlags': qualityFlags,
  };
}

class KnetGifDomainAligner {
  const KnetGifDomainAligner({
    this.lagCandidatesSeconds = const [-5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5],
    this.highSaturationShindo = 6.5,
    this.lowFloorShindo = -2.5,
  });

  final List<int> lagCandidatesSeconds;
  final double highSaturationShindo;
  final double lowFloorShindo;

  KnetGifDomainAlignmentReport align({
    required String eventId,
    required List<KnetWaveformFeatureSeries> waveformSeries,
    required List<GifDecodedStationSecond> gifObservations,
  }) {
    final waveByKey = <_StationRoleKey, KnetWaveformFeatureSeries>{
      for (final series in waveformSeries)
        _StationRoleKey(series.stationCode, series.sensorRole): series,
    };
    final gifByKey = <_StationRoleKey, List<GifDecodedStationSecond>>{};
    for (final observation in gifObservations) {
      gifByKey
          .putIfAbsent(
            _StationRoleKey(observation.stationCode, observation.sensorRole),
            () => [],
          )
          .add(observation);
    }

    final stationReports = <KnetGifStationAlignmentReport>[];
    final allSamples = <KnetGifAlignedSample>[];
    final missingWaveStations = <String>[];

    for (final entry in gifByKey.entries) {
      final series = waveByKey[entry.key];
      if (series == null) {
        missingWaveStations.add(
          '${entry.key.stationCode}:${entry.key.sensorRole.name}',
        );
        continue;
      }
      final stationReport = _alignStation(series, entry.value);
      if (stationReport != null) {
        stationReports.add(stationReport);
        allSamples.addAll(stationReport.samples);
      }
    }

    return KnetGifDomainAlignmentReport(
      eventId: eventId,
      schemaVersion: knetGifDomainAlignmentVersion,
      stationReports: stationReports
        ..sort((a, b) => a.stationCode.compareTo(b.stationCode)),
      summary: _summarize(allSamples, missingWaveStations),
    );
  }

  KnetGifStationAlignmentReport? _alignStation(
    KnetWaveformFeatureSeries series,
    List<GifDecodedStationSecond> observations,
  ) {
    final byTime = <DateTime, GifDecodedStationSecond>{
      for (final observation in observations)
        observation.observedAtUtc: observation,
    };
    KnetGifStationAlignmentReport? best;
    for (final lag in lagCandidatesSeconds) {
      final samples = <KnetGifAlignedSample>[];
      for (final second in series.seconds) {
        if (second.jmaIntensityApprox == null) continue;
        final gifTime = second.startTimeUtc.add(Duration(seconds: lag));
        final gif = byTime[gifTime];
        if (gif == null) continue;
        samples.add(
          KnetGifAlignedSample(
            stationCode: series.stationCode,
            sensorRole: series.sensorRole,
            waveformTimeUtc: second.startTimeUtc,
            gifObservedAtUtc: gif.observedAtUtc,
            lagSeconds: lag,
            waveformIntensityApprox: second.jmaIntensityApprox!,
            gifDecodedShindo: gif.gifDecodedShindo,
            pgaGal: second.pgaGal,
            pgvCms: second.pgvCms,
            qualityFlags: [
              ...series.qualityFlags,
              ...second.qualityFlags,
              ...gif.qualityFlags,
            ]..sort(),
          ),
        );
      }
      final report = _stationReport(series, lag, samples);
      if (report == null) continue;
      if (best == null ||
          report.sampleCount > best.sampleCount ||
          (report.sampleCount == best.sampleCount && report.rmse < best.rmse)) {
        best = report;
      }
    }
    return best;
  }

  KnetGifStationAlignmentReport? _stationReport(
    KnetWaveformFeatureSeries series,
    int lagSeconds,
    List<KnetGifAlignedSample> samples,
  ) {
    if (samples.isEmpty) return null;
    final diffs = samples.map((sample) => sample.shindoDifference).toList();
    final meanDiff = diffs.reduce((a, b) => a + b) / diffs.length;
    final meanAbsDiff =
        diffs.map((value) => value.abs()).reduce((a, b) => a + b) /
        diffs.length;
    final rmse = math.sqrt(
      diffs.map((value) => value * value).reduce((a, b) => a + b) /
          diffs.length,
    );
    final highSaturationCount = samples
        .where((sample) => sample.gifDecodedShindo >= highSaturationShindo)
        .length;
    final lowFloorCount = samples
        .where((sample) => sample.gifDecodedShindo <= lowFloorShindo)
        .length;
    return KnetGifStationAlignmentReport(
      stationCode: series.stationCode,
      sensorRole: series.sensorRole,
      bestLagSeconds: lagSeconds,
      sampleCount: samples.length,
      meanDifferenceGifMinusWaveform: meanDiff,
      meanAbsoluteDifference: meanAbsDiff,
      rmse: rmse,
      highSaturationCount: highSaturationCount,
      lowFloorCount: lowFloorCount,
      samples: samples,
    );
  }

  KnetGifDomainAlignmentSummary _summarize(
    List<KnetGifAlignedSample> samples,
    List<String> missingWaveStations,
  ) {
    if (samples.isEmpty) {
      return KnetGifDomainAlignmentSummary(
        sampleCount: 0,
        stationCount: 0,
        meanDifferenceGifMinusWaveform: null,
        meanAbsoluteDifference: null,
        rmse: null,
        missingWaveStations: missingWaveStations..sort(),
      );
    }
    final diffs = samples.map((sample) => sample.shindoDifference).toList();
    final stations = {
      for (final sample in samples)
        '${sample.stationCode}:${sample.sensorRole.name}',
    };
    return KnetGifDomainAlignmentSummary(
      sampleCount: samples.length,
      stationCount: stations.length,
      meanDifferenceGifMinusWaveform:
          diffs.reduce((a, b) => a + b) / diffs.length,
      meanAbsoluteDifference:
          diffs.map((value) => value.abs()).reduce((a, b) => a + b) /
          diffs.length,
      rmse: math.sqrt(
        diffs.map((value) => value * value).reduce((a, b) => a + b) /
            diffs.length,
      ),
      missingWaveStations: missingWaveStations..sort(),
    );
  }
}

class KnetGifDomainAlignmentReport {
  const KnetGifDomainAlignmentReport({
    required this.eventId,
    required this.schemaVersion,
    required this.stationReports,
    required this.summary,
  });

  final String eventId;
  final String schemaVersion;
  final List<KnetGifStationAlignmentReport> stationReports;
  final KnetGifDomainAlignmentSummary summary;

  Map<String, Object?> toJson({bool includeSamples = true}) => {
    'schemaVersion': schemaVersion,
    'eventId': eventId,
    'summary': summary.toJson(),
    'stationReports': stationReports
        .map((report) => report.toJson(includeSamples: includeSamples))
        .toList(),
  };
}

class KnetGifDomainAlignmentSummary {
  const KnetGifDomainAlignmentSummary({
    required this.sampleCount,
    required this.stationCount,
    required this.meanDifferenceGifMinusWaveform,
    required this.meanAbsoluteDifference,
    required this.rmse,
    required this.missingWaveStations,
  });

  final int sampleCount;
  final int stationCount;
  final double? meanDifferenceGifMinusWaveform;
  final double? meanAbsoluteDifference;
  final double? rmse;
  final List<String> missingWaveStations;

  Map<String, Object?> toJson() => {
    'sampleCount': sampleCount,
    'stationCount': stationCount,
    'meanDifferenceGifMinusWaveform': meanDifferenceGifMinusWaveform,
    'meanAbsoluteDifference': meanAbsoluteDifference,
    'rmse': rmse,
    'missingWaveStations': missingWaveStations,
  };
}

class KnetGifStationAlignmentReport {
  const KnetGifStationAlignmentReport({
    required this.stationCode,
    required this.sensorRole,
    required this.bestLagSeconds,
    required this.sampleCount,
    required this.meanDifferenceGifMinusWaveform,
    required this.meanAbsoluteDifference,
    required this.rmse,
    required this.highSaturationCount,
    required this.lowFloorCount,
    required this.samples,
  });

  final String stationCode;
  final KnetSensorRole sensorRole;
  final int bestLagSeconds;
  final int sampleCount;
  final double meanDifferenceGifMinusWaveform;
  final double meanAbsoluteDifference;
  final double rmse;
  final int highSaturationCount;
  final int lowFloorCount;
  final List<KnetGifAlignedSample> samples;

  Map<String, Object?> toJson({bool includeSamples = true}) => {
    'stationCode': stationCode,
    'sensorRole': sensorRole.name,
    'bestLagSeconds': bestLagSeconds,
    'sampleCount': sampleCount,
    'meanDifferenceGifMinusWaveform': meanDifferenceGifMinusWaveform,
    'meanAbsoluteDifference': meanAbsoluteDifference,
    'rmse': rmse,
    'highSaturationCount': highSaturationCount,
    'lowFloorCount': lowFloorCount,
    if (includeSamples)
      'samples': samples.map((sample) => sample.toJson()).toList(),
  };
}

class KnetGifAlignedSample {
  const KnetGifAlignedSample({
    required this.stationCode,
    required this.sensorRole,
    required this.waveformTimeUtc,
    required this.gifObservedAtUtc,
    required this.lagSeconds,
    required this.waveformIntensityApprox,
    required this.gifDecodedShindo,
    required this.pgaGal,
    required this.pgvCms,
    required this.qualityFlags,
  });

  final String stationCode;
  final KnetSensorRole sensorRole;
  final DateTime waveformTimeUtc;
  final DateTime gifObservedAtUtc;
  final int lagSeconds;
  final double waveformIntensityApprox;
  final double gifDecodedShindo;
  final double pgaGal;
  final double pgvCms;
  final List<String> qualityFlags;

  double get shindoDifference => gifDecodedShindo - waveformIntensityApprox;

  Map<String, Object?> toJson() => {
    'stationCode': stationCode,
    'sensorRole': sensorRole.name,
    'waveformTimeUtc': waveformTimeUtc.toIso8601String(),
    'gifObservedAtUtc': gifObservedAtUtc.toIso8601String(),
    'lagSeconds': lagSeconds,
    'waveformIntensityApprox': waveformIntensityApprox,
    'gifDecodedShindo': gifDecodedShindo,
    'shindoDifference': shindoDifference,
    'pgaGal': pgaGal,
    'pgvCms': pgvCms,
    'qualityFlags': qualityFlags,
  };
}

class _StationRoleKey {
  const _StationRoleKey(this.stationCode, this.sensorRole);

  final String stationCode;
  final KnetSensorRole sensorRole;

  @override
  bool operator ==(Object other) =>
      other is _StationRoleKey &&
      other.stationCode == stationCode &&
      other.sensorRole == sensorRole;

  @override
  int get hashCode => Object.hash(stationCode, sensorRole);
}
