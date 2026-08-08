import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

void main(List<String> arguments) {
  final baselinePath =
      _value(arguments, '--baseline') ??
      '.dart_tool/matsuzaki_2006_jma_baseline/report.json';
  final outputDirectory = Directory(
    _value(arguments, '--output-dir') ??
        '.dart_tool/matsuzaki_2006_candidate_scoring_diagnostic',
  );
  final baselineFile = File(baselinePath);
  if (!baselineFile.existsSync()) {
    stderr.writeln('Missing baseline report: $baselinePath');
    exitCode = 66;
    return;
  }

  final minimumStationCount = _intValue(arguments, '--min-stations') ?? 10;
  final maximumStationCount = _intValue(arguments, '--max-stations') ?? 50;
  final selectedYear = _intValue(arguments, '--year');
  if (minimumStationCount <= 0 || maximumStationCount < minimumStationCount) {
    stderr.writeln('Station limits must satisfy 0 < minimum <= maximum.');
    exitCode = 64;
    return;
  }
  const gridRadiusDegrees = 0.3;
  const gridStepDegrees = 0.1;
  const candidateTieTolerance = 1e-9;
  final modelSelection = _loadModel(arguments);
  final model = Matsuzaki2006AttenuationModel(
    coefficients: modelSelection.coefficients,
  );
  final rootScorer = Matsuzaki2006RootClusterScorer(model: model);
  final forwardScorer = Matsuzaki2006ForwardResidualScorer(model: model);
  const forwardSearchSpec = Matsuzaki2006ForwardSearchSpec(
    magnitudeScanStep: 0.05,
    refinementTolerance: 1e-8,
    objectiveTieTolerance: 1e-12,
    maximumRefinementIterations: 100,
  );

  final baseline =
      jsonDecode(baselineFile.readAsStringSync(encoding: utf8))
          as Map<String, Object?>;
  final rawEvents = baseline['events']! as List<Object?>;
  final diagnostics = <Map<String, Object?>>[];
  for (final rawEvent in rawEvents) {
    final event = rawEvent! as Map<String, Object?>;
    if (selectedYear != null && event['year'] != selectedYear) continue;
    final rawStations = event['stations']! as List<Object?>;
    if (rawStations.length < minimumStationCount ||
        rawStations.length > maximumStationCount) {
      continue;
    }
    final trueLatitude = (event['latitude']! as num).toDouble();
    final trueLongitude = (event['longitude']! as num).toDouble();
    final trueDepthKm = (event['depthKm']! as num).toDouble();
    final observations = rawStations.map((rawStation) {
      final station = rawStation! as Map<String, Object?>;
      return Matsuzaki2006IntensityObservation(
        id: station['stationId']! as String,
        latitude: (station['latitude']! as num).toDouble(),
        longitude: (station['longitude']! as num).toDouble(),
        intensity: (station['observedIntensity']! as num).toDouble(),
      );
    }).toList();
    final candidates = <Matsuzaki2006CandidateSource>[];
    for (var latitudeIndex = -3; latitudeIndex <= 3; latitudeIndex++) {
      for (var longitudeIndex = -3; longitudeIndex <= 3; longitudeIndex++) {
        candidates.add(
          Matsuzaki2006CandidateSource(
            latitude: trueLatitude + latitudeIndex * gridStepDegrees,
            longitude: trueLongitude + longitudeIndex * gridStepDegrees,
            depthKm: trueDepthKm,
          ),
        );
      }
    }

    final rootScores = [
      for (final candidate in candidates)
        rootScorer.score(
          observations: observations,
          source: candidate,
          minimumSolvedStations: observations.length,
          rejectCandidateWhenAnyStationHasNoRoot: true,
          clusterTieTolerance: 1e-12,
        ),
    ];
    final forwardScores = [
      for (final candidate in candidates)
        forwardScorer.score(
          observations: observations,
          source: candidate,
          minimumObservations: observations.length,
          searchSpec: forwardSearchSpec,
        ),
    ];
    final rootDiagnostic = _rootDiagnostic(
      scores: rootScores,
      trueLatitude: trueLatitude,
      trueLongitude: trueLongitude,
      candidateTieTolerance: candidateTieTolerance,
    );
    final forwardDiagnostic = _forwardDiagnostic(
      scores: forwardScores,
      trueLatitude: trueLatitude,
      trueLongitude: trueLongitude,
      candidateTieTolerance: candidateTieTolerance,
    );
    final catalogResiduals = [
      for (final rawStation in rawStations)
        () {
          final station = rawStation! as Map<String, Object?>;
          final observed = (station['observedIntensity']! as num).toDouble();
          final distance = (station['sourceDistanceKm']! as num).toDouble();
          return observed -
              model.predictIntensity(
                magnitude: (event['magnitude']! as num).toDouble(),
                sourceDistanceKm: distance,
                depthKm: trueDepthKm,
              );
        }(),
    ];
    diagnostics.add({
      'eventId': event['eventId'],
      'catalogLatitude': trueLatitude,
      'catalogLongitude': trueLongitude,
      'magnitude': event['magnitude'],
      'magnitudeType': event['magnitudeType'],
      'depthKm': trueDepthKm,
      'stationCount': observations.length,
      'candidateCount': candidates.length,
      'catalogForwardResidualMean': _mean(catalogResiduals),
      'catalogForwardResidualRms': _rms(catalogResiduals),
      'rootCluster': rootDiagnostic,
      'forwardResidual': forwardDiagnostic,
    });
  }

  final output = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_candidate_scoring_diagnostic_v1',
    'inputBaseline': baselinePath,
    'model': modelSelection.toJson(),
    'selection': {
      'minimumStationCount': minimumStationCount,
      'maximumStationCount': maximumStationCount,
      'fixedCatalogDepth': true,
      'year': selectedYear,
    },
    'grid': {
      'radiusDegrees': gridRadiusDegrees,
      'stepDegrees': gridStepDegrees,
      'candidateCountPerEvent': 49,
    },
    'forwardMagnitudeSearch': {
      'scanStep': forwardSearchSpec.magnitudeScanStep,
      'refinementTolerance': forwardSearchSpec.refinementTolerance,
      'objectiveTieTolerance': forwardSearchSpec.objectiveTieTolerance,
      'maximumRefinementIterations':
          forwardSearchSpec.maximumRefinementIterations,
    },
    'candidateTieTolerance': candidateTieTolerance,
    'summary': _summary(diagnostics),
    'events': diagnostics,
  };
  outputDirectory.createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  final markdownFile = File('${outputDirectory.path}/report.md');
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(output),
    encoding: utf8,
  );
  markdownFile.writeAsStringSync(_markdown(output), encoding: utf8);
  stdout.writeln(jsonEncode(output['summary']));
  stdout.writeln('wrote ${markdownFile.path}');
  stdout.writeln('wrote ${jsonFile.path}');
}

Map<String, Object?> _rootDiagnostic({
  required List<Matsuzaki2006RootClusterScore> scores,
  required double trueLatitude,
  required double trueLongitude,
  required double candidateTieTolerance,
}) {
  final validScores = scores.where((score) => score.isValid).toList();
  final catalogScore = scores.firstWhere(
    (score) =>
        (score.source.latitude - trueLatitude).abs() < 1e-12 &&
        (score.source.longitude - trueLongitude).abs() < 1e-12,
  );
  if (validScores.isEmpty) {
    return {
      'solved': false,
      'validCandidateCount': 0,
      'catalogCandidateValid': catalogScore.isValid,
      'catalogInvalidReason': catalogScore.invalidReason?.name,
    };
  }
  final minimumScore = validScores
      .map((score) => score.minimumMagnitudeRms!)
      .reduce((a, b) => a < b ? a : b);
  final bestScores = validScores
      .where(
        (score) =>
            score.minimumMagnitudeRms! - minimumScore <= candidateTieTolerance,
      )
      .toList();
  return {
    'solved': true,
    'validCandidateCount': validScores.length,
    'catalogCandidateValid': catalogScore.isValid,
    'catalogScore': catalogScore.minimumMagnitudeRms,
    'catalogInvalidReason': catalogScore.invalidReason?.name,
    'minimumScore': minimumScore,
    ..._bestCandidateGeometry(bestScores, trueLatitude, trueLongitude),
  };
}

Map<String, Object?> _forwardDiagnostic({
  required List<Matsuzaki2006ForwardCandidateScore> scores,
  required double trueLatitude,
  required double trueLongitude,
  required double candidateTieTolerance,
}) {
  final validScores = scores.where((score) => score.isValid).toList();
  final catalogScore = scores.firstWhere(
    (score) =>
        (score.source.latitude - trueLatitude).abs() < 1e-12 &&
        (score.source.longitude - trueLongitude).abs() < 1e-12,
  );
  if (validScores.isEmpty) {
    return {
      'solved': false,
      'validCandidateCount': 0,
      'catalogCandidateValid': catalogScore.isValid,
      'catalogInvalidReason': catalogScore.invalidReason?.name,
    };
  }
  final minimumScore = validScores
      .map((score) => score.minimumIntensityRms!)
      .reduce((a, b) => a < b ? a : b);
  final bestScores = validScores
      .where(
        (score) =>
            score.minimumIntensityRms! - minimumScore <= candidateTieTolerance,
      )
      .toList();
  return {
    'solved': true,
    'validCandidateCount': validScores.length,
    'catalogCandidateValid': catalogScore.isValid,
    'catalogScore': catalogScore.minimumIntensityRms,
    'minimumScore': minimumScore,
    'bestFittedMagnitudes': [
      for (final score in bestScores)
        [for (final solution in score.solutions) solution.magnitude],
    ],
    ..._bestCandidateGeometry(bestScores, trueLatitude, trueLongitude),
  };
}

Map<String, Object?> _bestCandidateGeometry(
  List<Object> scores,
  double trueLatitude,
  double trueLongitude,
) {
  final candidates = [
    for (final rawScore in scores)
      switch (rawScore) {
        Matsuzaki2006RootClusterScore score => score.source,
        Matsuzaki2006ForwardCandidateScore score => score.source,
        _ => throw StateError('Unsupported candidate score type.'),
      },
  ];
  final errors = [
    for (final source in candidates)
      QuakeCalculator.haversineDistance(
        trueLatitude,
        trueLongitude,
        source.latitude,
        source.longitude,
      ),
  ];
  return {
    'bestCandidateCount': candidates.length,
    'catalogCandidateAmongBest': errors.any((error) => error < 1e-9),
    'bestLocationErrorMinKm': errors.reduce((a, b) => a < b ? a : b),
    'bestLocationErrorMaxKm': errors.reduce((a, b) => a > b ? a : b),
    'bestCandidates': [
      for (var index = 0; index < candidates.length; index++)
        {
          'latitude': candidates[index].latitude,
          'longitude': candidates[index].longitude,
          'latitudeOffsetDegrees': candidates[index].latitude - trueLatitude,
          'longitudeOffsetDegrees': candidates[index].longitude - trueLongitude,
          'locationErrorKm': errors[index],
        },
    ],
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> events) {
  final rootSolved = events
      .where((event) => (event['rootCluster']! as Map)['solved'] == true)
      .toList();
  final forwardSolved = events
      .where((event) => (event['forwardResidual']! as Map)['solved'] == true)
      .toList();
  List<double> errors(List<Map<String, Object?>> source, String method) => [
    for (final event in source)
      (((event[method]! as Map)['bestLocationErrorMinKm'])! as num).toDouble(),
  ];
  final rootErrors = errors(rootSolved, 'rootCluster');
  final forwardErrors = errors(forwardSolved, 'forwardResidual');
  bool touchesBoundary(Map<String, Object?> event, String method) {
    final bestCandidates =
        (event[method]! as Map<String, Object?>)['bestCandidates']!
            as List<Object?>;
    return bestCandidates.any((rawCandidate) {
      final candidate = rawCandidate! as Map<String, Object?>;
      final latitudeOffset = (candidate['latitudeOffsetDegrees']! as num)
          .toDouble()
          .abs();
      final longitudeOffset = (candidate['longitudeOffsetDegrees']! as num)
          .toDouble()
          .abs();
      return latitudeOffset >= 0.3 - 1e-10 || longitudeOffset >= 0.3 - 1e-10;
    });
  }

  bool fittedMagnitudeAtBound(Map<String, Object?> event, double boundary) {
    final groups =
        (event['forwardResidual']!
                as Map<String, Object?>)['bestFittedMagnitudes']!
            as List<Object?>;
    return groups
        .expand((rawGroup) => rawGroup! as List<Object?>)
        .any(
          (rawMagnitude) =>
              ((rawMagnitude! as num).toDouble() - boundary).abs() < 1e-7,
        );
  }

  return {
    'selectedEvents': events.length,
    'rootClusterSolvedEvents': rootSolved.length,
    'rootClusterCatalogValidEvents': events
        .where(
          (event) =>
              (event['rootCluster']! as Map)['catalogCandidateValid'] == true,
        )
        .length,
    'rootClusterMeanBestLocationErrorKm': _mean(rootErrors),
    'rootClusterMedianBestLocationErrorKm': _median(rootErrors),
    'rootClusterBestTouchesGridBoundaryEvents': rootSolved
        .where((event) => touchesBoundary(event, 'rootCluster'))
        .length,
    'forwardSolvedEvents': forwardSolved.length,
    'forwardCatalogAmongBestEvents': forwardSolved
        .where(
          (event) =>
              (event['forwardResidual']! as Map)['catalogCandidateAmongBest'] ==
              true,
        )
        .length,
    'forwardMeanBestLocationErrorKm': _mean(forwardErrors),
    'forwardMedianBestLocationErrorKm': _median(forwardErrors),
    'forwardBestTouchesGridBoundaryEvents': forwardSolved
        .where((event) => touchesBoundary(event, 'forwardResidual'))
        .length,
    'forwardBestMagnitudeAtLowerBoundEvents': forwardSolved
        .where(
          (event) => fittedMagnitudeAtBound(
            event,
            Matsuzaki2006AttenuationModel.minimumMagnitude,
          ),
        )
        .length,
    'forwardBestMagnitudeAtUpperBoundEvents': forwardSolved
        .where(
          (event) => fittedMagnitudeAtBound(
            event,
            Matsuzaki2006AttenuationModel.maximumMagnitude,
          ),
        )
        .length,
  };
}

String _markdown(Map<String, Object?> report) {
  final summary = report['summary']! as Map<String, Object?>;
  final events = report['events']! as List<Object?>;
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Candidate Scoring Diagnostic')
    ..writeln()
    ..writeln('Catalog depth is fixed. The horizontal grid is centered on the')
    ..writeln('catalog epicenter with radius 0.3 degrees and step 0.1 degrees.')
    ..writeln('Model: `${(report['model']! as Map<String, Object?>)['name']}`.')
    ..writeln(
      'Station range: '
      '${(report['selection']! as Map<String, Object?>)['minimumStationCount']}'
      '-${(report['selection']! as Map<String, Object?>)['maximumStationCount']}.',
    )
    ..writeln(
      'Year: '
      '${(report['selection']! as Map<String, Object?>)['year'] ?? 'all'}.',
    )
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('|---|---:|');
  for (final entry in summary.entries) {
    final value = entry.value;
    buffer.writeln(
      '| ${entry.key} | ${value is double ? value.toStringAsFixed(3) : value} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Events')
    ..writeln()
    ..writeln(
      '| Event | Stations | Root solved | Root error km | Forward error km |',
    )
    ..writeln('|---|---:|---|---:|---:|');
  for (final rawEvent in events) {
    final event = rawEvent! as Map<String, Object?>;
    final root = event['rootCluster']! as Map<String, Object?>;
    final forward = event['forwardResidual']! as Map<String, Object?>;
    buffer.writeln(
      '| `${event['eventId']}` | ${event['stationCount']} | '
      '${root['solved']} | ${_formatNullable(root['bestLocationErrorMinKm'])} | '
      '${_formatNullable(forward['bestLocationErrorMinKm'])} |',
    );
  }
  return buffer.toString();
}

double _mean(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

String _formatNullable(Object? value) =>
    value is num ? value.toDouble().toStringAsFixed(3) : '-';

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

int? _intValue(List<String> arguments, String name) {
  final raw = _value(arguments, name);
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null) {
    throw FormatException('$name must be an integer: $raw');
  }
  return value;
}

_ModelSelection _loadModel(List<String> arguments) {
  final reportPath = _value(arguments, '--coefficients-report');
  if (reportPath == null) {
    return const _ModelSelection(
      name: 'published',
      source: 'Matsuzaki et al. 2006 equation 12',
      coefficients: Matsuzaki2006AttenuationCoefficients.published,
    );
  }
  final reportFile = File(reportPath);
  if (!reportFile.existsSync()) {
    throw ArgumentError.value(
      reportPath,
      '--coefficients-report',
      'File does not exist.',
    );
  }
  final modelName =
      _value(arguments, '--coefficients-model') ?? 'globalStationWeighted';
  final report =
      jsonDecode(reportFile.readAsStringSync(encoding: utf8))
          as Map<String, Object?>;
  final fits = report['fits'];
  if (fits is! Map<String, Object?> ||
      fits[modelName] is! Map<String, Object?>) {
    throw FormatException('Calibration report has no fit named $modelName.');
  }
  final fit = fits[modelName]! as Map<String, Object?>;
  final raw = fit['coefficients'];
  if (raw is! Map<String, Object?>) {
    throw FormatException('Fit $modelName has no coefficient object.');
  }
  double number(String key) {
    final value = raw[key];
    if (value is! num || !value.toDouble().isFinite) {
      throw FormatException('Invalid coefficient $key in fit $modelName.');
    }
    return value.toDouble();
  }

  return _ModelSelection(
    name: modelName,
    source: reportPath,
    coefficients: Matsuzaki2006AttenuationCoefficients(
      magnitudeCoefficient: number('magnitudeCoefficient'),
      logDistanceCoefficient: number('logDistanceCoefficient'),
      saturationCoefficient: number('saturationCoefficient'),
      saturationMagnitudeExponent: number('saturationMagnitudeExponent'),
      depthCoefficient: number('depthCoefficient'),
      intercept: number('intercept'),
    ),
  );
}

class _ModelSelection {
  const _ModelSelection({
    required this.name,
    required this.source,
    required this.coefficients,
  });

  final String name;
  final String source;
  final Matsuzaki2006AttenuationCoefficients coefficients;

  Map<String, Object> toJson() => {
    'name': name,
    'source': source,
    'coefficients': coefficients.toJson(),
  };
}

double _rms(List<double> values) {
  if (values.isEmpty) return 0;
  final squareSum = values
      .map((value) => value * value)
      .reduce((left, right) => left + right);
  return math.sqrt(squareSum / values.length);
}
