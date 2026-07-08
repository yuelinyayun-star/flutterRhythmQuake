import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/jma2001_travel_time_approximation.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

const _defaultInputDirectory = '.dart_tool/source_estimation_benchmark';
const _defaultOutputPath = '.dart_tool/kotoho7_truth_score_probe/report.json';
const _method = 'nied_gif_hyp_kotoho7_reference_replay_v1';

final Map<String, _StationLocation> _stationByCode = {
  for (final row in NiedStationDb.stations)
    (row['code'] as String): _StationLocation(
      latitude: (row['lat'] as num).toDouble(),
      longitude: (row['lng'] as num).toDouble(),
    ),
};

void main(List<String> args) {
  final inputDirectory = Directory(
    _argument(args, '--input') ?? _defaultInputDirectory,
  );
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final outputFile = File(outputPath);
  final cases = <Map<String, Object?>>[];

  if (inputDirectory.existsSync()) {
    final files =
        inputDirectory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.reference.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
      if (decoded is! Map<String, Object?>) continue;
      final summary = _summarizeCase(file, decoded);
      if (summary != null) cases.add(summary);
    }
  }

  final report = <String, Object?>{
    'schemaVersion': 'kotoho7_truth_score_probe_v1',
    'inputDirectory': inputDirectory.path,
    'method': _method,
    'purpose':
        'Offline article-error-level probe: compare current best/final source score against catalog truth using the same station membership and exported S flags.',
    'caseCount': cases.length,
    'cases': cases,
  };

  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  stdout.writeln('Wrote ${outputFile.path}');
}

Map<String, Object?>? _summarizeCase(File file, Map<String, Object?> json) {
  final frames = json['frames'];
  if (frames is! List) return null;
  final caseJson = _map(json['case']);
  final caseId =
      _string(caseJson['caseId']) ??
      file.uri.pathSegments.last.replaceAll('.reference.json', '');
  final truth = _map(caseJson['truth']);
  final truthLatitude = _double(truth['latitude']);
  final truthLongitude = _double(truth['longitude']);
  final truthDepthKm = _double(truth['depthKm']);
  if (truthLatitude == null || truthLongitude == null || truthDepthKm == null) {
    return null;
  }

  final methodFrames = <_FrameWithMethod>[];
  for (final rawFrame in frames) {
    final frame = _map(rawFrame);
    final method = _map(_map(frame['methods'])[_method]);
    final estimate = _map(method['estimate']);
    if (estimate.isEmpty) continue;
    methodFrames.add(_FrameWithMethod(frame: frame, method: method));
  }
  if (methodFrames.isEmpty) return null;

  final chronologicalFrames = List<_FrameWithMethod>.from(methodFrames);
  final errorSortedFrames = List<_FrameWithMethod>.from(methodFrames)
    ..sort((left, right) {
      final leftError = _double(left.method['errorKm']) ?? double.infinity;
      final rightError = _double(right.method['errorKm']) ?? double.infinity;
      return leftError.compareTo(rightError);
    });
  final bestFrame = errorSortedFrames.first;
  final finalFrame = chronologicalFrames.last;

  return {
    'caseId': caseId,
    'path': file.path,
    'truth': {
      'latitude': truthLatitude,
      'longitude': truthLongitude,
      'depthKm': truthDepthKm,
    },
    'bestFrame': _probeFrame(
      bestFrame,
      truthLatitude: truthLatitude,
      truthLongitude: truthLongitude,
      truthDepthKm: truthDepthKm,
    ),
    'finalFrame': _probeFrame(
      finalFrame,
      truthLatitude: truthLatitude,
      truthLongitude: truthLongitude,
      truthDepthKm: truthDepthKm,
    ),
  };
}

Map<String, Object?> _probeFrame(
  _FrameWithMethod item, {
  required double truthLatitude,
  required double truthLongitude,
  required double truthDepthKm,
}) {
  final frame = item.frame;
  final method = item.method;
  final estimate = _map(method['estimate']);
  final diagnostics = _map(estimate['diagnostics']);
  final cache = _map(diagnostics['stateful_source_cache']);
  final assignedCodes = _stringSet(cache['assigned_station_codes']).toList()
    ..sort();
  var stationTimes = _stationObservedAtByCode(
    cache['assigned_station_observed_times'],
  );
  if (stationTimes.isEmpty) {
    stationTimes = _stationObservedAtByCode(
      _map(frame['sourceTriggerMetadata'])['station_trigger_observation_times'],
    );
  }
  final stationPsCache = _map(cache['station_ps_cache']);
  final sFlagCodes = _stringSet(stationPsCache['s_flag_station_codes']);
  final records = <_StationTimingRecord>[];
  for (final code in assignedCodes) {
    final observedAt = stationTimes[code];
    final location = _stationByCode[code];
    if (observedAt == null || location == null) continue;
    records.add(
      _StationTimingRecord(
        code: code,
        observedAt: observedAt,
        latitude: location.latitude,
        longitude: location.longitude,
        sFlag: sFlagCodes.contains(code),
      ),
    );
  }
  records.sort((left, right) {
    final timeCmp = left.observedAt.compareTo(right.observedAt);
    if (timeCmp != 0) return timeCmp;
    return left.code.compareTo(right.code);
  });

  final earliestObservedAt =
      _dateTime(cache['earliest_observed_at']) ??
      (records.isEmpty ? null : records.first.observedAt);
  final frameObservedAt = _dateTime(frame['observedAtJst']);
  final currentLatitude = _double(estimate['latitude']);
  final currentLongitude = _double(estimate['longitude']);
  final currentDepthKm = _double(estimate['depthKm']);
  final currentScore =
      currentLatitude == null ||
          currentLongitude == null ||
          currentDepthKm == null ||
          earliestObservedAt == null ||
          frameObservedAt == null
      ? null
      : _scoreArticleErrorLevel(
          records,
          earliestObservedAt: earliestObservedAt,
          observedAt: frameObservedAt,
          latitude: currentLatitude,
          longitude: currentLongitude,
          depthKm: currentDepthKm,
        );
  final truthScore = earliestObservedAt == null || frameObservedAt == null
      ? null
      : _scoreArticleErrorLevel(
          records,
          earliestObservedAt: earliestObservedAt,
          observedAt: frameObservedAt,
          latitude: truthLatitude,
          longitude: truthLongitude,
          depthKm: truthDepthKm,
        );

  return {
    'observedAtJst': frame['observedAtJst'],
    'errorKm': method['errorKm'],
    'current': {
      'latitude': currentLatitude,
      'longitude': currentLongitude,
      'depthKm': currentDepthKm,
      ...?currentScore?.toJson(),
    },
    'truthSameMembership': truthScore?.toJson(),
    'truthMinusCurrentScore': truthScore == null || currentScore == null
        ? null
        : _finiteOrNull(truthScore.score - currentScore.score),
    'assignedStationCount': assignedCodes.length,
    'scoredStationCount': records.length,
    'sFlagCount': sFlagCodes.length,
    'sFlagCodesMissingInReference': sFlagCodes.isEmpty,
  };
}

_ArticleScore _scoreArticleErrorLevel(
  List<_StationTimingRecord> records, {
  required DateTime earliestObservedAt,
  required DateTime observedAt,
  required double latitude,
  required double longitude,
  required double depthKm,
}) {
  if (records.isEmpty) return _ArticleScore.invalid();
  final currentElapsedSeconds =
      observedAt.difference(earliestObservedAt).inMilliseconds / 1000.0;
  final sGateOpen = currentElapsedSeconds > 15.0;
  final distances = <double>[];
  final originSamples = <double>[];
  final weights = <double>[];
  final residuals = <double>[];
  final phaseIndexes = <int>[];
  var sFlagCount = 0;

  for (final record in records) {
    final observedSeconds =
        record.observedAt.difference(earliestObservedAt).inMilliseconds /
        1000.0;
    final surfaceDistanceKm = _haversineKm(
      latitude,
      longitude,
      record.latitude,
      record.longitude,
    );
    distances.add(surfaceDistanceKm);
    final hypocentralDistanceKm = math.sqrt(
      surfaceDistanceKm * surfaceDistanceKm + depthKm * depthKm,
    );
    final pTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: true,
    );
    final sTravelSeconds = Jma2001TravelTimeApproximation.travelTimeSeconds(
      hypocentralDistanceKm: hypocentralDistanceKm,
      depthKm: depthKm,
      pWave: false,
    );
    final useS = sGateOpen && record.sFlag;
    if (record.sFlag) sFlagCount += 1;
    phaseIndexes.add(useS ? 1 : 0);
    originSamples.add(
      observedSeconds - (useS ? sTravelSeconds : pTravelSeconds),
    );
  }

  final firstDetectedDistanceKm = math.max(50.0, distances.first);
  for (final distance in distances) {
    weights.add(firstDetectedDistanceKm / math.max(50.0, distance));
  }
  final originOffsetSeconds = _mean(originSamples);
  var residualSum = 0.0;
  var weightedResidualSquares = 0.0;
  var weightSum = 0.0;
  var pCount = 0;
  var sCount = 0;
  var otherCount = 0;
  for (var index = 0; index < originSamples.length; index++) {
    final residual = (originSamples[index] - originOffsetSeconds).abs();
    residuals.add(residual);
    residualSum += residual;
    weightSum += weights[index];
    weightedResidualSquares += weights[index] * residual * residual;
    if (residual > 2.8) {
      otherCount += 1;
    } else if (phaseIndexes[index] == 1) {
      sCount += 1;
    } else {
      pCount += 1;
    }
  }
  final phaseCount = originSamples.length;
  final stationCountScale =
      30.0 +
      20000.0 / (1.0 + phaseCount * phaseCount) +
      2000.0 / (50.0 + phaseCount);
  final sFactor = math.max(
    0.25,
    1.0 - (sFlagCount * 3.0) / math.max(1, phaseCount),
  );
  final score =
      sFactor *
      (weightedResidualSquares / math.max(weightSum, phaseCount.toDouble())) *
      stationCountScale;
  return _ArticleScore(
    score: score,
    originOffsetSeconds: originOffsetSeconds,
    meanResidualSeconds: residuals.isEmpty ? 0 : residualSum / residuals.length,
    p90ResidualSeconds: _percentile(residuals, 0.9),
    pCount: pCount,
    sCount: sCount,
    otherCount: otherCount,
    sFactor: sFactor,
    weightSum: weightSum,
    weightedResidualSquares: weightedResidualSquares,
  );
}

class _FrameWithMethod {
  final Map<String, Object?> frame;
  final Map<String, Object?> method;

  const _FrameWithMethod({required this.frame, required this.method});
}

class _StationLocation {
  final double latitude;
  final double longitude;

  const _StationLocation({required this.latitude, required this.longitude});
}

class _StationTimingRecord {
  final String code;
  final DateTime observedAt;
  final double latitude;
  final double longitude;
  final bool sFlag;

  const _StationTimingRecord({
    required this.code,
    required this.observedAt,
    required this.latitude,
    required this.longitude,
    required this.sFlag,
  });
}

class _ArticleScore {
  final double score;
  final double originOffsetSeconds;
  final double meanResidualSeconds;
  final double p90ResidualSeconds;
  final int pCount;
  final int sCount;
  final int otherCount;
  final double sFactor;
  final double weightSum;
  final double weightedResidualSquares;

  const _ArticleScore({
    required this.score,
    required this.originOffsetSeconds,
    required this.meanResidualSeconds,
    required this.p90ResidualSeconds,
    required this.pCount,
    required this.sCount,
    required this.otherCount,
    required this.sFactor,
    required this.weightSum,
    required this.weightedResidualSquares,
  });

  factory _ArticleScore.invalid() => const _ArticleScore(
    score: double.infinity,
    originOffsetSeconds: 0,
    meanResidualSeconds: double.infinity,
    p90ResidualSeconds: double.infinity,
    pCount: 0,
    sCount: 0,
    otherCount: 0,
    sFactor: 1,
    weightSum: 0,
    weightedResidualSquares: double.infinity,
  );

  Map<String, Object?> toJson() => {
    'score': _finiteOrNull(score),
    'originOffsetSeconds': _finiteOrNull(originOffsetSeconds),
    'meanResidualSeconds': _finiteOrNull(meanResidualSeconds),
    'p90ResidualSeconds': _finiteOrNull(p90ResidualSeconds),
    'pCount': pCount,
    'sCount': sCount,
    'otherCount': otherCount,
    'sFactor': _finiteOrNull(sFactor),
    'weightSum': _finiteOrNull(weightSum),
    'weightedResidualSquares': _finiteOrNull(weightedResidualSquares),
  };
}

Map<String, DateTime> _stationObservedAtByCode(Object? value) {
  final source = _map(value);
  if (source.isEmpty) return const <String, DateTime>{};
  final result = <String, DateTime>{};
  for (final entry in source.entries) {
    final timing = _map(entry.value);
    final sourceName = _string(timing['observed_time_source']);
    final observedAt = sourceName == 'scratch_ten_plus_1_at'
        ? _dateTime(timing['scratch_ten_plus_1_at']) ??
              _dateTime(timing['first_trigger_at']) ??
              _dateTime(timing['first_rise_at'])
        : _dateTime(timing['first_trigger_at']) ??
              _dateTime(timing['first_rise_at']) ??
              _dateTime(timing['scratch_ten_plus_1_at']);
    if (observedAt != null) result[entry.key] = observedAt;
  }
  return result;
}

Set<String> _stringSet(Object? value) {
  if (value is! List) return <String>{};
  return value.whereType<String>().where((item) => item.isNotEmpty).toSet();
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

DateTime? _dateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

double _mean(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double _percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
  return sorted[index];
}

double _haversineKm(
  double latitude1,
  double longitude1,
  double latitude2,
  double longitude2,
) {
  const earthRadiusKm = 6371.0;
  final dLat = _radians(latitude2 - latitude1);
  final dLon = _radians(longitude2 - longitude1);
  final lat1 = _radians(latitude1);
  final lat2 = _radians(latitude2);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _radians(double degrees) => degrees * math.pi / 180.0;

double? _finiteOrNull(double value) => value.isFinite ? value : null;

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
