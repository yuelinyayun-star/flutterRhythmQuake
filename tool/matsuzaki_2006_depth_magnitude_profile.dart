import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _minimumDepthKm = 5.0;
const _maximumDepthKm = 100.0;
const _depthStepKm = 5.0;
const _minimumObservations = 10;
const _defaultMaximumObservations = 100;
const _profileTieTolerance = 1e-10;
const _profileEnvelopeRmsIncrease = 0.05;

const _magnitudeSearchSpec = Matsuzaki2006ForwardSearchSpec(
  magnitudeScanStep: 0.1,
  refinementTolerance: 1e-7,
  objectiveTieTolerance: 1e-10,
  maximumRefinementIterations: 100,
);

void main(List<String> arguments) {
  final inputPath = _value(arguments, '--input');
  final outputDirectoryPath =
      _value(arguments, '--output-dir') ??
      '.dart_tool/matsuzaki_2006_depth_magnitude_profile';
  final maximumStations =
      _optionalInt(arguments, '--maximum-stations') ??
      _defaultMaximumObservations;
  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_depth_magnitude_profile.dart '
      '--input <annual.json> [--maximum-stations <count>] '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (maximumStations < _minimumObservations) {
    throw ArgumentError.value(
      maximumStations,
      '--maximum-stations',
      'Must be at least $_minimumObservations.',
    );
  }
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input file does not exist: $inputPath');
    exitCode = 66;
    return;
  }

  final decoded = jsonDecode(inputFile.readAsStringSync(encoding: utf8));
  if (decoded is! Map<String, Object?> ||
      decoded['year'] is! num ||
      decoded['events'] is! List<Object?>) {
    throw const FormatException('Invalid annual JMA intensity dataset.');
  }
  final year = (decoded['year']! as num).toInt();
  final rawEvents = decoded['events']! as List<Object?>;
  final inputSpec = Matsuzaki2006ArchiveInputSpec(
    initialSearchRadiusKm: 100,
    maximumHorizontalSearchDistanceKm: 250,
    minimumSearchDepthKm: _minimumDepthKm,
    maximumSearchDepthKm: _maximumDepthKm,
    minimumObservations: _minimumObservations,
    maximumObservations: maximumStations,
    minimumInstrumentalIntensity: 0.5,
  );
  const inputBuilder = Matsuzaki2006ArchiveInversionInputBuilder();
  final models = <String, Matsuzaki2006AttenuationModel>{
    'published': const Matsuzaki2006AttenuationModel(),
    'finiteFaultSemanticFrozen2017': const Matsuzaki2006AttenuationModel(
      coefficients:
          Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
    ),
  };
  final events = <Map<String, Object?>>[];
  final inputStatusCounts = <String, int>{};
  var eligibleEventCount = 0;

  for (final rawEvent in rawEvents) {
    if (rawEvent is! Map<String, Object?>) continue;
    final truth = _eligibleTruth(rawEvent);
    if (truth == null) continue;
    eligibleEventCount++;
    final input = inputBuilder.build(rawEvent: rawEvent, spec: inputSpec);
    _increment(inputStatusCounts, input.status.name);
    if (!input.isReady) continue;

    final modelResults = <String, Object?>{};
    for (final entry in models.entries) {
      modelResults[entry.key] = _modelProfiles(
        model: entry.value,
        observations: input.observations,
        truth: truth,
      );
    }
    events.add({
      'eventId': rawEvent['eventId'],
      'truth': truth.toJson(),
      'input': {
        'selectedObservationCount': input.observations.length,
        'domainSafeObservationCount': input.domainSafeObservationCount,
        'selectedStationIds': [
          for (final observation in input.observations) observation.id,
        ],
      },
      'models': modelResults,
    });
    stdout.writeln('profiled ${rawEvent['eventId']} (${events.length})');
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_depth_magnitude_profile_v1',
    'inputPath': inputPath,
    'year': year,
    'protocolStatus': '2019_opened_audit_diagnostic_not_blind',
    'truthUseBoundary':
        'Catalog latitude and longitude are fixed only in this explicit '
        'post-input diagnostic. Catalog magnitude is used only by the fixed '
        'magnitude branch. Neither branch is an unknown-event inversion.',
    'inputConstructionUsesCatalogTruth': false,
    'protocol': {
      'horizontalLocation': 'catalog_epicenter_fixed_for_diagnostic',
      'minimumDepthKm': _minimumDepthKm,
      'maximumDepthKm': _maximumDepthKm,
      'depthStepKm': _depthStepKm,
      'minimumObservations': _minimumObservations,
      'maximumObservations': maximumStations,
      'minimumInstrumentalIntensity': inputSpec.minimumInstrumentalIntensity,
      'optimizedMagnitudeBranch': {
        'magnitudeScanStep': _magnitudeSearchSpec.magnitudeScanStep,
        'refinementTolerance': _magnitudeSearchSpec.refinementTolerance,
        'objectiveTieTolerance': _magnitudeSearchSpec.objectiveTieTolerance,
      },
      'fixedMagnitudeBranch': 'catalog_mj',
      'profileTieTolerance': _profileTieTolerance,
      'profileEnvelopeRmsIncrease': _profileEnvelopeRmsIncrease,
    },
    'inputSummary': {
      'rawEventCount': rawEvents.length,
      'eligibleEventCount': eligibleEventCount,
      'profiledEventCount': events.length,
      'inputStatusCounts': _sortedCounts(inputStatusCounts),
    },
    'modelSummaries': {
      for (final modelName in models.keys)
        modelName: _modelSummary(events, modelName),
    },
    'events': events,
  };
  final outputDirectory = Directory(outputDirectoryPath)
    ..createSync(recursive: true);
  final jsonFile = File('${outputDirectory.path}/report.json');
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  final markdownFile = File('${outputDirectory.path}/report.md');
  markdownFile.writeAsStringSync(_markdown(report), encoding: utf8);
  stdout.writeln(jsonEncode(report['modelSummaries']));
  stdout.writeln('wrote ${jsonFile.path}');
  stdout.writeln('wrote ${markdownFile.path}');
}

Map<String, Object?> _modelProfiles({
  required Matsuzaki2006AttenuationModel model,
  required List<Matsuzaki2006IntensityObservation> observations,
  required _CatalogTruth truth,
}) {
  final scorer = Matsuzaki2006ForwardResidualScorer(model: model);
  final optimizedPoints = <_DepthProfilePoint>[];
  final fixedPoints = <_DepthProfilePoint>[];
  for (
    var depthKm = _minimumDepthKm;
    depthKm <= _maximumDepthKm + 1e-9;
    depthKm += _depthStepKm
  ) {
    final source = Matsuzaki2006CandidateSource(
      latitude: truth.latitude,
      longitude: truth.longitude,
      depthKm: depthKm,
    );
    final score = scorer.score(
      observations: observations,
      source: source,
      minimumObservations: _minimumObservations,
      searchSpec: _magnitudeSearchSpec,
    );
    if (!score.isValid || score.solutions.isEmpty) {
      throw StateError(
        'Catalog-horizontal optimized profile became invalid at $depthKm km.',
      );
    }
    optimizedPoints.add(
      _DepthProfilePoint(
        depthKm: depthKm,
        rms: score.solutions.first.intensityRms,
        magnitudes: [
          for (final solution in score.solutions) solution.magnitude,
        ],
      ),
    );
    fixedPoints.add(
      _DepthProfilePoint(
        depthKm: depthKm,
        rms: _fixedMagnitudeRms(
          model: model,
          observations: observations,
          source: source,
          magnitude: truth.magnitude,
        ),
        magnitudes: [truth.magnitude],
      ),
    );
  }

  final catalogSource = Matsuzaki2006CandidateSource(
    latitude: truth.latitude,
    longitude: truth.longitude,
    depthKm: truth.depthKm,
  );
  final catalogOptimizedScore = scorer.score(
    observations: observations,
    source: catalogSource,
    minimumObservations: _minimumObservations,
    searchSpec: _magnitudeSearchSpec,
  );
  if (!catalogOptimizedScore.isValid ||
      catalogOptimizedScore.solutions.isEmpty) {
    throw StateError('Catalog source could not be scored.');
  }
  return {
    'optimizedMagnitude': _profileJson(
      points: optimizedPoints,
      truth: truth,
      catalogDepthRms: catalogOptimizedScore.solutions.first.intensityRms,
      catalogDepthMagnitudes: [
        for (final solution in catalogOptimizedScore.solutions)
          solution.magnitude,
      ],
    ),
    'fixedCatalogMagnitude': _profileJson(
      points: fixedPoints,
      truth: truth,
      catalogDepthRms: _fixedMagnitudeRms(
        model: model,
        observations: observations,
        source: catalogSource,
        magnitude: truth.magnitude,
      ),
      catalogDepthMagnitudes: [truth.magnitude],
    ),
    'catalogSourceStationResiduals': _catalogSourceResiduals(
      model: model,
      observations: observations,
      truth: truth,
    ),
  };
}

List<Map<String, Object?>> _catalogSourceResiduals({
  required Matsuzaki2006AttenuationModel model,
  required List<Matsuzaki2006IntensityObservation> observations,
  required _CatalogTruth truth,
}) {
  return [
    for (final observation in observations)
      _catalogSourceResidual(
        model: model,
        observation: observation,
        truth: truth,
      ),
  ];
}

Map<String, Object?> _catalogSourceResidual({
  required Matsuzaki2006AttenuationModel model,
  required Matsuzaki2006IntensityObservation observation,
  required _CatalogTruth truth,
}) {
  final sourceDistanceKm =
      Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
        sourceLatitude: truth.latitude,
        sourceLongitude: truth.longitude,
        stationLatitude: observation.latitude,
        stationLongitude: observation.longitude,
        depthKm: truth.depthKm,
      );
  final predictedIntensity = model.predictIntensity(
    magnitude: truth.magnitude,
    sourceDistanceKm: sourceDistanceKm,
    depthKm: truth.depthKm,
  );
  return {
    'stationId': observation.id,
    'sourceDistanceKm': sourceDistanceKm,
    'catalogDepthKm': truth.depthKm,
    'observedIntensity': observation.intensity,
    'predictedIntensity': predictedIntensity,
    'residual': observation.intensity - predictedIntensity,
  };
}

Map<String, Object?> _profileJson({
  required List<_DepthProfilePoint> points,
  required _CatalogTruth truth,
  required double catalogDepthRms,
  required List<double> catalogDepthMagnitudes,
}) {
  final minimumRms = points.map((point) => point.rms).reduce(math.min);
  final best = points
      .where((point) => point.rms - minimumRms <= _profileTieTolerance)
      .toList();
  final envelope = points
      .where(
        (point) =>
            point.rms - minimumRms <= _profileEnvelopeRmsIncrease + 1e-12,
      )
      .toList();
  final bestDepthErrors = [
    for (final point in best) (point.depthKm - truth.depthKm).abs(),
  ];
  final bestMagnitudeErrors = [
    for (final point in best)
      for (final magnitude in point.magnitudes)
        (magnitude - truth.magnitude).abs(),
  ];
  final touchesMinimum = best.any(
    (point) => (point.depthKm - _minimumDepthKm).abs() <= 1e-9,
  );
  final touchesMaximum = best.any(
    (point) => (point.depthKm - _maximumDepthKm).abs() <= 1e-9,
  );
  return {
    'minimumRms': minimumRms,
    'bestDepthsKm': [for (final point in best) point.depthKm],
    'bestDepthAbsoluteErrorKmMaximumEquivalent': bestDepthErrors.reduce(
      math.max,
    ),
    'bestMagnitudeAbsoluteErrorMaximumEquivalent': bestMagnitudeErrors.reduce(
      math.max,
    ),
    'hardDepthBoundaryReached': touchesMinimum || touchesMaximum,
    'hardDepthBoundaryContacts': [
      if (touchesMinimum) 'depthMinimum',
      if (touchesMaximum) 'depthMaximum',
    ],
    'catalogDepthRms': catalogDepthRms,
    'catalogDepthRmsIncreaseFromMinimum': catalogDepthRms - minimumRms,
    'catalogDepthMagnitudes': catalogDepthMagnitudes,
    'depthEnvelope': {
      'maximumRmsIncrease': _profileEnvelopeRmsIncrease,
      'minimumDepthKm': envelope.map((point) => point.depthKm).reduce(math.min),
      'maximumDepthKm': envelope.map((point) => point.depthKm).reduce(math.max),
      'catalogDepthInsideNumericRange':
          truth.depthKm >= envelope.first.depthKm &&
          truth.depthKm <= envelope.last.depthKm,
    },
    'points': [for (final point in points) point.toJson()],
  };
}

double _fixedMagnitudeRms({
  required Matsuzaki2006AttenuationModel model,
  required List<Matsuzaki2006IntensityObservation> observations,
  required Matsuzaki2006CandidateSource source,
  required double magnitude,
}) {
  var squaredResidualSum = 0.0;
  for (final observation in observations) {
    final sourceDistanceKm =
        Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
          sourceLatitude: source.latitude,
          sourceLongitude: source.longitude,
          stationLatitude: observation.latitude,
          stationLongitude: observation.longitude,
          depthKm: source.depthKm,
        );
    final predicted = model.predictIntensity(
      magnitude: magnitude,
      sourceDistanceKm: sourceDistanceKm,
      depthKm: source.depthKm,
    );
    final residual = observation.intensity - predicted;
    squaredResidualSum += residual * residual;
  }
  return math.sqrt(squaredResidualSum / observations.length);
}

Map<String, Object?> _modelSummary(
  List<Map<String, Object?>> events,
  String modelName,
) {
  final modelResults = [
    for (final event in events)
      ((event['models']! as Map<String, Object?>)[modelName]!
          as Map<String, Object?>),
  ];
  final residuals = [
    for (final result in modelResults)
      for (final residual
          in (result['catalogSourceStationResiduals']! as List<Object?>))
        residual! as Map<String, Object?>,
  ];
  final eventResidualSummaries = [
    for (final result in modelResults)
      _residualSummary(
        (result['catalogSourceStationResiduals']! as List<Object?>)
            .cast<Map<String, Object?>>(),
      ),
  ];
  final eventMeanResiduals = [
    for (final summary in eventResidualSummaries)
      (summary['meanResidual']! as num).toDouble(),
  ];
  final depthMaximumEventMeanResiduals = <double>[];
  final depthMinimumEventMeanResiduals = <double>[];
  for (var index = 0; index < modelResults.length; index++) {
    final contacts =
        ((modelResults[index]['optimizedMagnitude']!
                    as Map<String, Object?>)['hardDepthBoundaryContacts']!
                as List<Object?>)
            .whereType<String>();
    final meanResidual = eventMeanResiduals[index];
    if (contacts.contains('depthMaximum')) {
      depthMaximumEventMeanResiduals.add(meanResidual);
    }
    if (contacts.contains('depthMinimum')) {
      depthMinimumEventMeanResiduals.add(meanResidual);
    }
  }
  Map<String, Object?> summarize(String branch) {
    final profiles = [
      for (final result in modelResults)
        (result[branch]! as Map<String, Object?>),
    ];
    List<double> values(String key) => profiles
        .map((profile) => profile[key])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    final contacts = <String, int>{};
    for (final profile in profiles) {
      for (final contact
          in (profile['hardDepthBoundaryContacts']! as List<Object?>)
              .whereType<String>()) {
        _increment(contacts, contact);
      }
    }
    final envelopeWidths = [
      for (final profile in profiles)
        ((profile['depthEnvelope']! as Map<String, Object?>)['maximumDepthKm']!
                    as num)
                .toDouble() -
            ((profile['depthEnvelope']!
                        as Map<String, Object?>)['minimumDepthKm']!
                    as num)
                .toDouble(),
    ];
    return {
      'eventCount': profiles.length,
      'hardDepthBoundaryEventCount': profiles
          .where((profile) => profile['hardDepthBoundaryReached'] == true)
          .length,
      'hardDepthBoundaryContactCounts': _sortedCounts(contacts),
      'bestDepthAbsoluteErrorKmMedian': _percentile(
        values('bestDepthAbsoluteErrorKmMaximumEquivalent'),
        0.5,
      ),
      'bestMagnitudeAbsoluteErrorMedian': _percentile(
        values('bestMagnitudeAbsoluteErrorMaximumEquivalent'),
        0.5,
      ),
      'depthEnvelopeWidthKmMedian': _percentile(envelopeWidths, 0.5),
      'catalogDepthInsideNumericEnvelopeCount': profiles.where((profile) {
        final envelope = profile['depthEnvelope']! as Map<String, Object?>;
        return envelope['catalogDepthInsideNumericRange'] == true;
      }).length,
      'catalogDepthRmsIncreaseFromMinimumMedian': _percentile(
        values('catalogDepthRmsIncreaseFromMinimum'),
        0.5,
      ),
    };
  }

  final optimizedBoundary = <String, bool>{};
  for (var index = 0; index < events.length; index++) {
    optimizedBoundary[events[index]['eventId']! as String] =
        (modelResults[index]['optimizedMagnitude']!
            as Map<String, Object?>)['hardDepthBoundaryReached'] ==
        true;
  }
  var relievedByFixedMagnitude = 0;
  var createdByFixedMagnitude = 0;
  for (var index = 0; index < events.length; index++) {
    final eventId = events[index]['eventId']! as String;
    final fixedBoundary =
        (modelResults[index]['fixedCatalogMagnitude']!
            as Map<String, Object?>)['hardDepthBoundaryReached'] ==
        true;
    if (optimizedBoundary[eventId]! && !fixedBoundary) {
      relievedByFixedMagnitude++;
    } else if (!optimizedBoundary[eventId]! && fixedBoundary) {
      createdByFixedMagnitude++;
    }
  }
  return {
    'optimizedMagnitude': summarize('optimizedMagnitude'),
    'fixedCatalogMagnitude': summarize('fixedCatalogMagnitude'),
    'boundaryRelievedByFixingCatalogMagnitude': relievedByFixedMagnitude,
    'boundaryCreatedByFixingCatalogMagnitude': createdByFixedMagnitude,
    'catalogSourceStationWeightedResiduals': _residualSummary(residuals),
    'catalogSourceEventEqualResiduals': {
      'eventCount': eventResidualSummaries.length,
      'meanOfEventMeanResiduals':
          eventMeanResiduals.reduce((left, right) => left + right) /
          eventMeanResiduals.length,
      'meanOfEventRms':
          eventResidualSummaries
              .map((summary) => (summary['rms']! as num).toDouble())
              .reduce((left, right) => left + right) /
          eventResidualSummaries.length,
      'positiveEventMeanResidualCount': eventMeanResiduals
          .where((value) => value > 0)
          .length,
      'negativeEventMeanResidualCount': eventMeanResiduals
          .where((value) => value < 0)
          .length,
      'eventMeanResidualMedian': _percentile(eventMeanResiduals, 0.5),
      'depthMaximumEventMeanResidualMedian': _percentile(
        depthMaximumEventMeanResiduals,
        0.5,
      ),
      'depthMinimumEventMeanResidualMedian': _percentile(
        depthMinimumEventMeanResiduals,
        0.5,
      ),
    },
    'catalogSourceResidualsByDistance': {
      '1_to_less_than_15_km': _residualSummary(
        residuals.where((residual) {
          final distance = (residual['sourceDistanceKm']! as num).toDouble();
          return distance >= 1 && distance < 15;
        }).toList(),
      ),
      '15_to_less_than_30_km': _residualSummary(
        residuals.where((residual) {
          final distance = (residual['sourceDistanceKm']! as num).toDouble();
          return distance >= 15 && distance < 30;
        }).toList(),
      ),
      '30_to_less_than_100_km': _residualSummary(
        residuals.where((residual) {
          final distance = (residual['sourceDistanceKm']! as num).toDouble();
          return distance >= 30 && distance < 100;
        }).toList(),
      ),
      '100_to_500_km': _residualSummary(
        residuals.where((residual) {
          final distance = (residual['sourceDistanceKm']! as num).toDouble();
          return distance >= 100 && distance <= 500;
        }).toList(),
      ),
    },
    'catalogSourceResidualsByDepth': {
      '5_to_less_than_30_km': _residualSummary(
        residuals.where((residual) {
          final depth = (residual['catalogDepthKm']! as num).toDouble();
          return depth >= 5 && depth < 30;
        }).toList(),
      ),
      '30_to_less_than_100_km': _residualSummary(
        residuals.where((residual) {
          final depth = (residual['catalogDepthKm']! as num).toDouble();
          return depth >= 30 && depth < 100;
        }).toList(),
      ),
      '100_km': _residualSummary(
        residuals.where((residual) {
          final depth = (residual['catalogDepthKm']! as num).toDouble();
          return (depth - 100).abs() <= 1e-9;
        }).toList(),
      ),
    },
  };
}

Map<String, Object?> _residualSummary(List<Map<String, Object?>> residuals) {
  if (residuals.isEmpty) {
    return const {'stationCount': 0, 'meanResidual': null, 'rms': null};
  }
  var sum = 0.0;
  var squaredSum = 0.0;
  for (final residualRecord in residuals) {
    final residual = (residualRecord['residual']! as num).toDouble();
    sum += residual;
    squaredSum += residual * residual;
  }
  return {
    'stationCount': residuals.length,
    'meanResidual': sum / residuals.length,
    'rms': math.sqrt(squaredSum / residuals.length),
  };
}

_CatalogTruth? _eligibleTruth(Map<String, Object?> rawEvent) {
  final alternate = rawEvent['alternateHypocenters'];
  if (alternate is List<Object?> && alternate.isNotEmpty) return null;
  final raw = rawEvent['preferredHypocenter'];
  if (raw is! Map<String, Object?>) return null;
  final latitude = _number(raw['latitude']);
  final longitude = _number(raw['longitude']);
  final depthKm = _number(raw['depthKm']);
  final magnitude = _number(raw['magnitude']);
  final magnitudeType = (raw['magnitudeType'] as String?)?.trim();
  if (latitude == null ||
      latitude < -90 ||
      latitude > 90 ||
      longitude == null ||
      longitude < -180 ||
      longitude > 180 ||
      depthKm == null ||
      depthKm < _minimumDepthKm ||
      depthKm > _maximumDepthKm ||
      magnitude == null ||
      magnitude < Matsuzaki2006AttenuationModel.minimumMagnitude ||
      magnitude > Matsuzaki2006AttenuationModel.maximumMagnitude ||
      magnitudeType == null ||
      !Matsuzaki2006JmaBaselineEvaluator.supportedMagnitudeTypes.contains(
        magnitudeType,
      )) {
    return null;
  }
  return _CatalogTruth(
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    magnitude: magnitude,
  );
}

String _markdown(Map<String, Object?> report) {
  final summaries = report['modelSummaries']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Depth-Magnitude Profile')
    ..writeln()
    ..writeln('Year: `${report['year']}`')
    ..writeln()
    ..writeln('Protocol status: `${report['protocolStatus']}`')
    ..writeln()
    ..writeln(
      'Catalog horizontal location is fixed only for this explicit structural '
      'diagnostic. The RMS + 0.05 envelope is not a confidence interval.',
    )
    ..writeln()
    ..writeln('## Models')
    ..writeln();
  for (final entry in summaries.entries) {
    buffer
      ..writeln('### ${entry.key}')
      ..writeln()
      ..writeln('```json')
      ..writeln(const JsonEncoder.withIndent('  ').convert(entry.value))
      ..writeln('```')
      ..writeln();
  }
  return buffer.toString();
}

double? _percentile(List<double> values, double fraction) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final position = (sorted.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final weight = position - lower;
  return sorted[lower] * (1 - weight) + sorted[upper] * weight;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  return index >= 0 && index + 1 < arguments.length
      ? arguments[index + 1]
      : null;
}

int? _optionalInt(List<String> arguments, String name) {
  final raw = _value(arguments, name);
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null) throw FormatException('$name must be an integer.');
  return value;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

void _increment(Map<String, int> counts, String key) {
  counts[key] = (counts[key] ?? 0) + 1;
}

Map<String, int> _sortedCounts(Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  return {for (final key in keys) key: counts[key]!};
}

class _DepthProfilePoint {
  const _DepthProfilePoint({
    required this.depthKm,
    required this.rms,
    required this.magnitudes,
  });

  final double depthKm;
  final double rms;
  final List<double> magnitudes;

  Map<String, Object?> toJson() => {
    'depthKm': depthKm,
    'rms': rms,
    'magnitudes': magnitudes,
  };
}

class _CatalogTruth {
  const _CatalogTruth({
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
  });

  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
  };
}
