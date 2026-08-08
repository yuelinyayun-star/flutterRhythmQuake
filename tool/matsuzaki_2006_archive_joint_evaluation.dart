import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/intensity_reconstruction/experiments/experiment_1/experiment_1.dart';

const _defaultInputSpec = Matsuzaki2006ArchiveInputSpec(
  initialSearchRadiusKm: 100,
  maximumHorizontalSearchDistanceKm: 250,
  minimumSearchDepthKm: 5,
  maximumSearchDepthKm: 100,
  minimumObservations: 10,
  maximumObservations: 30,
  minimumInstrumentalIntensity: 0.5,
);

const _stationBiasTrainingYears = <int>[
  2010,
  2011,
  2012,
  2013,
  2014,
  2015,
  2016,
];

const _stages = <Matsuzaki2006JointSearchStage>[
  Matsuzaki2006JointSearchStage(
    latitudeStepDegrees: 0.5,
    longitudeStepDegrees: 0.5,
    depthStepKm: 20,
  ),
  Matsuzaki2006JointSearchStage.refinePreviousCandidates(
    latitudeStepDegrees: 0.1,
    longitudeStepDegrees: 0.1,
    depthStepKm: 10,
    maximumSeedCount: 6,
    seedRmsIncrease: 0.10,
  ),
  Matsuzaki2006JointSearchStage.refinePreviousCandidates(
    latitudeStepDegrees: 0.025,
    longitudeStepDegrees: 0.025,
    depthStepKm: 5,
    maximumSeedCount: 6,
    seedRmsIncrease: 0.05,
  ),
];

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
      '.dart_tool/matsuzaki_2006_archive_joint_evaluation';
  final maximumEvents = _optionalInt(arguments, '--maximum-events');
  final stationBiasK = _optionalInt(arguments, '--station-bias-k');
  final stationBiasMinimumEvents =
      _optionalInt(arguments, '--station-bias-min-events') ?? 2;
  final stationBiasInputDirectory =
      _value(arguments, '--station-bias-input-dir') ??
      'tmp/jma_intensity_nearfield_expansion';
  final protocolStatus =
      _value(arguments, '--protocol-status') ??
      '2019_opened_audit_draft_not_blind';
  final maximumStations =
      _optionalInt(arguments, '--maximum-stations') ??
      _defaultInputSpec.maximumObservations;
  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tool/matsuzaki_2006_archive_joint_evaluation.dart '
      '--input <annual.json> [--maximum-events <count>] '
      '[--maximum-stations <count>] '
      '[--station-bias-k <count>] '
      '[--station-bias-min-events <count>] '
      '[--station-bias-input-dir <directory>] '
      '[--protocol-status <status>] '
      '[--output-dir <directory>]',
    );
    exitCode = 64;
    return;
  }
  if (maximumEvents != null && maximumEvents <= 0) {
    throw ArgumentError.value(
      maximumEvents,
      '--maximum-events',
      'Must be positive.',
    );
  }
  if (maximumStations < _defaultInputSpec.minimumObservations) {
    throw ArgumentError.value(
      maximumStations,
      '--maximum-stations',
      'Must be at least ${_defaultInputSpec.minimumObservations}.',
    );
  }
  if (stationBiasK != null && stationBiasK < 0) {
    throw ArgumentError.value(
      stationBiasK,
      '--station-bias-k',
      'Must be non-negative.',
    );
  }
  if (stationBiasK != null && stationBiasMinimumEvents < 2) {
    throw ArgumentError.value(
      stationBiasMinimumEvents,
      '--station-bias-min-events',
      'Must be at least two.',
    );
  }
  if (protocolStatus.trim().isEmpty) {
    throw ArgumentError.value(
      protocolStatus,
      '--protocol-status',
      'Must not be empty.',
    );
  }
  final inputSpec = Matsuzaki2006ArchiveInputSpec(
    initialSearchRadiusKm: _defaultInputSpec.initialSearchRadiusKm,
    maximumHorizontalSearchDistanceKm:
        _defaultInputSpec.maximumHorizontalSearchDistanceKm,
    minimumSearchDepthKm: _defaultInputSpec.minimumSearchDepthKm,
    maximumSearchDepthKm: _defaultInputSpec.maximumSearchDepthKm,
    minimumObservations: _defaultInputSpec.minimumObservations,
    maximumObservations: maximumStations,
    minimumInstrumentalIntensity:
        _defaultInputSpec.minimumInstrumentalIntensity,
  );
  inputSpec.validate();
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
  const inputBuilder = Matsuzaki2006ArchiveInversionInputBuilder();
  final models = <String, Matsuzaki2006AttenuationModel>{
    'published': const Matsuzaki2006AttenuationModel(),
    'finiteFaultSemanticFrozen2017': const Matsuzaki2006AttenuationModel(
      coefficients:
          Matsuzaki2006AttenuationCoefficients.finiteFaultSemanticFrozen2017,
    ),
  };
  final stationBiasModels = stationBiasK == null
      ? const <String, Matsuzaki2006StationBiasModel>{}
      : {
          for (final entry in models.entries)
            entry.key: _trainStationBiasModel(
              inputDirectory: stationBiasInputDirectory,
              model: entry.value,
              minimumTrainingEventCount: stationBiasMinimumEvents,
            ),
        };
  final inputStatusCounts = <String, int>{};
  final events = <Map<String, Object?>>[];
  var eligibleEventCount = 0;
  var evaluatedEventCount = 0;

  for (final rawEvent in rawEvents) {
    if (rawEvent is! Map<String, Object?>) continue;
    final truth = _eligibleTruth(rawEvent, inputSpec);
    if (truth == null) continue;
    eligibleEventCount++;
    final input = inputBuilder.build(rawEvent: rawEvent, spec: inputSpec);
    _increment(inputStatusCounts, input.status.name);
    if (!input.isReady) continue;
    if (maximumEvents != null && evaluatedEventCount >= maximumEvents) break;
    evaluatedEventCount++;

    final modelResults = <String, Object?>{};
    for (final entry in models.entries) {
      final searchSpec = Matsuzaki2006JointSearchSpec(
        initialHorizontalBounds: input.initialHorizontalBounds!,
        hardHorizontalBounds: input.hardHorizontalBounds!,
        minimumDepthKm: inputSpec.minimumSearchDepthKm,
        maximumDepthKm: inputSpec.maximumSearchDepthKm,
        radialSearchConstraint: input.radialSearchConstraint,
        stages: _stages,
        horizontalExpansionDegrees: 0.5,
        maximumHorizontalExpansionRounds: 8,
        maximumCandidateEvaluations: 30000,
        minimumObservations: inputSpec.minimumObservations,
        equivalentObjectiveTolerance: 1e-8,
        resolutionRmsIncrease: 0.05,
        magnitudeSearchSpec: _magnitudeSearchSpec,
      );
      final stopwatch = Stopwatch()..start();
      final result = Matsuzaki2006JointInverter(
        model: entry.value,
        stationBiasModel: stationBiasModels[entry.key],
        stationBiasShrinkage: Matsuzaki2006StationBiasShrinkage(
          pseudoEventCount: stationBiasK ?? 0,
        ),
      ).invert(observations: input.observations, searchSpec: searchSpec);
      stopwatch.stop();
      modelResults[entry.key] = _resultJson(
        result: result,
        truth: truth,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      );
    }
    events.add({
      'eventId': rawEvent['eventId'],
      'originTime': truth.originTime,
      'truth': truth.toJson(),
      'input': {
        'status': input.status.name,
        'anchorLatitude': input.anchorLatitude,
        'anchorLongitude': input.anchorLongitude,
        'rawObservationCount': input.rawObservationCount,
        'validObservationCount': input.validObservationCount,
        'domainSafeObservationCount': input.domainSafeObservationCount,
        'selectedObservationCount': input.observations.length,
        'selectedStationIds': [
          for (final observation in input.observations) observation.id,
        ],
      },
      'models': modelResults,
    });
    stdout.writeln(
      'evaluated ${rawEvent['eventId']} ($evaluatedEventCount'
      '${maximumEvents == null ? '' : '/$maximumEvents'})',
    );
  }

  final report = <String, Object?>{
    'schemaVersion': 'matsuzaki_2006_archive_joint_evaluation_v1',
    'inputPath': inputPath,
    'year': year,
    'maximumEvents': maximumEvents,
    'stationBias': stationBiasK == null
        ? {'enabled': false}
        : {
            'enabled': true,
            'inputDirectory': stationBiasInputDirectory,
            'trainingYears': _stationBiasTrainingYears,
            'minimumTrainingEventCount': stationBiasMinimumEvents,
            'pseudoEventCount': stationBiasK,
            'formula': 'model_prediction + b * n / (n + k)',
            'missingStationPolicy':
                'unavailable or coordinate-mismatched stations remain uncorrected',
          },
    'truthUseBoundary':
        'Catalog truth is read for eligibility and only compared after each '
        'inversion result is complete.',
    'inputConstructionUsesCatalogTruth': false,
    'protocolStatus': protocolStatus,
    'protocol': _protocolJson(inputSpec),
    'inputSummary': {
      'rawEventCount': rawEvents.length,
      'eligibleEventCountBeforeMaximumEventLimit': eligibleEventCount,
      'evaluatedEventCount': evaluatedEventCount,
      'inputStatusCountsBeforeMaximumEventLimit': _sortedCounts(
        inputStatusCounts,
      ),
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

Map<String, Object?> _resultJson({
  required Matsuzaki2006JointInversionResult result,
  required _CatalogTruth truth,
  required int elapsedMilliseconds,
}) {
  final candidateMetrics = [
    for (final candidate in result.bestCandidates)
      {
        'latitude': candidate.source.latitude,
        'longitude': candidate.source.longitude,
        'depthKm': candidate.source.depthKm,
        'magnitude': candidate.magnitude,
        'intensityRms': candidate.intensityRms,
        'meanIntensityResidual': candidate.meanIntensityResidual,
        'epicentralErrorKm':
            Matsuzaki2006PointSourceGeometry.hypocentralDistanceBetween(
              sourceLatitude: truth.latitude,
              sourceLongitude: truth.longitude,
              stationLatitude: candidate.source.latitude,
              stationLongitude: candidate.source.longitude,
              depthKm: 0,
            ),
        'depthAbsoluteErrorKm': (candidate.source.depthKm - truth.depthKm)
            .abs(),
        'magnitudeAbsoluteError': (candidate.magnitude - truth.magnitude).abs(),
      },
  ];
  double? minimumMetric(String key) => candidateMetrics.isEmpty
      ? null
      : candidateMetrics
            .map((candidate) => (candidate[key]! as num).toDouble())
            .reduce((left, right) => left < right ? left : right);
  double? maximumMetric(String key) => candidateMetrics.isEmpty
      ? null
      : candidateMetrics
            .map((candidate) => (candidate[key]! as num).toDouble())
            .reduce((left, right) => left > right ? left : right);
  return {
    'status': result.status.name,
    'isConverged': result.isConverged,
    'candidateEvaluationCount': result.candidateEvaluationCount,
    'elapsedMilliseconds': elapsedMilliseconds,
    'hardBoundaryContacts': [
      for (final boundary in result.hardBoundaryContacts) boundary.name,
    ]..sort(),
    'bestEquivalentCandidateCount': candidateMetrics.length,
    'minimumIntensityRms': result.bestCandidates.isEmpty
        ? null
        : result.bestCandidates.first.intensityRms,
    'epicentralErrorKmMinimumEquivalent': minimumMetric('epicentralErrorKm'),
    'epicentralErrorKmMaximumEquivalent': maximumMetric('epicentralErrorKm'),
    'depthAbsoluteErrorKmMinimumEquivalent': minimumMetric(
      'depthAbsoluteErrorKm',
    ),
    'depthAbsoluteErrorKmMaximumEquivalent': maximumMetric(
      'depthAbsoluteErrorKm',
    ),
    'magnitudeAbsoluteErrorMinimumEquivalent': minimumMetric(
      'magnitudeAbsoluteError',
    ),
    'magnitudeAbsoluteErrorMaximumEquivalent': maximumMetric(
      'magnitudeAbsoluteError',
    ),
    'resolutionEnvelope': result.resolutionEnvelope == null
        ? null
        : {
            'maximumRmsIncrease': result.resolutionEnvelope!.maximumRmsIncrease,
            'minimumLatitude': result.resolutionEnvelope!.minimumLatitude,
            'maximumLatitude': result.resolutionEnvelope!.maximumLatitude,
            'minimumLongitude': result.resolutionEnvelope!.minimumLongitude,
            'maximumLongitude': result.resolutionEnvelope!.maximumLongitude,
            'minimumDepthKm': result.resolutionEnvelope!.minimumDepthKm,
            'maximumDepthKm': result.resolutionEnvelope!.maximumDepthKm,
            'minimumMagnitude': result.resolutionEnvelope!.minimumMagnitude,
            'maximumMagnitude': result.resolutionEnvelope!.maximumMagnitude,
          },
    'bestCandidates': candidateMetrics,
  };
}

Map<String, Object?> _modelSummary(
  List<Map<String, Object?>> events,
  String modelName,
) {
  final results = [
    for (final event in events)
      ((event['models']! as Map<String, Object?>)[modelName]!
          as Map<String, Object?>),
  ];
  final converged = results
      .where((result) => result['isConverged'] == true)
      .toList();
  final withCandidates = results
      .where((result) => result['epicentralErrorKmMaximumEquivalent'] != null)
      .toList();
  final hardBoundaryContactCounts = <String, int>{};
  for (final result in results) {
    final contacts = result['hardBoundaryContacts']! as List<Object?>;
    for (final contact in contacts.whereType<String>()) {
      _increment(hardBoundaryContactCounts, contact);
    }
  }
  List<double> values(List<Map<String, Object?>> source, String key) => source
      .map((result) => result[key])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList();
  return {
    'evaluatedEventCount': results.length,
    'statusCounts': _sortedCounts(
      {
        for (final status in Matsuzaki2006JointInversionStatus.values)
          status.name: results
              .where((result) => result['status'] == status.name)
              .length,
      }..removeWhere((key, value) => value == 0),
    ),
    'convergedEventCount': converged.length,
    'convergedRate': results.isEmpty ? null : converged.length / results.length,
    'eventCountWithCandidates': withCandidates.length,
    'hardBoundaryContactCounts': _sortedCounts(hardBoundaryContactCounts),
    'convergedEpicentralErrorKmMedian': _percentile(
      values(converged, 'epicentralErrorKmMaximumEquivalent'),
      0.5,
    ),
    'convergedEpicentralErrorKmP90': _percentile(
      values(converged, 'epicentralErrorKmMaximumEquivalent'),
      0.9,
    ),
    'convergedDepthAbsoluteErrorKmMedian': _percentile(
      values(converged, 'depthAbsoluteErrorKmMaximumEquivalent'),
      0.5,
    ),
    'convergedMagnitudeAbsoluteErrorMedian': _percentile(
      values(converged, 'magnitudeAbsoluteErrorMaximumEquivalent'),
      0.5,
    ),
    'allCandidateEpicentralErrorKmMedian': _percentile(
      values(withCandidates, 'epicentralErrorKmMaximumEquivalent'),
      0.5,
    ),
    'allCandidateEpicentralErrorKmP90': _percentile(
      values(withCandidates, 'epicentralErrorKmMaximumEquivalent'),
      0.9,
    ),
    'allCandidateDepthAbsoluteErrorKmMedian': _percentile(
      values(withCandidates, 'depthAbsoluteErrorKmMaximumEquivalent'),
      0.5,
    ),
    'allCandidateMagnitudeAbsoluteErrorMedian': _percentile(
      values(withCandidates, 'magnitudeAbsoluteErrorMaximumEquivalent'),
      0.5,
    ),
    'candidateEvaluationCountMedian': _percentile(
      values(results, 'candidateEvaluationCount'),
      0.5,
    ),
    'elapsedMillisecondsMedian': _percentile(
      values(results, 'elapsedMilliseconds'),
      0.5,
    ),
  };
}

Map<String, Object?> _protocolJson(Matsuzaki2006ArchiveInputSpec inputSpec) => {
  'input': {
    'anchor': 'mean_coordinate_of_maximum_instrumental_intensity_stations',
    'initialSearchRadiusKm': inputSpec.initialSearchRadiusKm,
    'hardSearchRadiusKm': inputSpec.maximumHorizontalSearchDistanceKm,
    'minimumDepthKm': inputSpec.minimumSearchDepthKm,
    'maximumDepthKm': inputSpec.maximumSearchDepthKm,
    'minimumObservations': inputSpec.minimumObservations,
    'maximumObservations': inputSpec.maximumObservations,
    'minimumInstrumentalIntensity': inputSpec.minimumInstrumentalIntensity,
  },
  'stages': [
    for (final stage in _stages)
      {
        'latitudeStepDegrees': stage.latitudeStepDegrees,
        'longitudeStepDegrees': stage.longitudeStepDegrees,
        'depthStepKm': stage.depthStepKm,
        'refinesPreviousCandidates': stage.refinesPreviousCandidates,
        'maximumRefinementSeedCount': stage.maximumRefinementSeedCount,
        'refinementSeedRmsIncrease': stage.refinementSeedRmsIncrease,
      },
  ],
  'horizontalExpansionDegrees': 0.5,
  'maximumHorizontalExpansionRounds': 8,
  'maximumCandidateEvaluations': 30000,
  'equivalentObjectiveTolerance': 1e-8,
  'resolutionRmsIncrease': 0.05,
  'magnitudeSearch': {
    'scanStep': _magnitudeSearchSpec.magnitudeScanStep,
    'refinementTolerance': _magnitudeSearchSpec.refinementTolerance,
    'objectiveTieTolerance': _magnitudeSearchSpec.objectiveTieTolerance,
    'maximumRefinementIterations':
        _magnitudeSearchSpec.maximumRefinementIterations,
  },
};

Matsuzaki2006StationBiasModel _trainStationBiasModel({
  required String inputDirectory,
  required Matsuzaki2006AttenuationModel model,
  required int minimumTrainingEventCount,
}) {
  final trainer = Matsuzaki2006StationBiasTrainer();
  for (final year in _stationBiasTrainingYears) {
    final path = '$inputDirectory/jma_final_intensity_$year.json';
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('Missing station-bias training input: $path');
    }
    final decoded = jsonDecode(file.readAsStringSync(encoding: utf8));
    if (decoded is! Map<String, Object?> ||
        decoded['year'] is! num ||
        (decoded['year']! as num).toInt() != year) {
      throw FormatException('Invalid station-bias training input: $path');
    }
    final baseline = Matsuzaki2006JmaBaselineEvaluator(
      model: model,
    ).evaluate([decoded]);
    final semanticApplication =
        Matsuzaki2006SourceBackedDistanceOverrides.applyUnambiguousCalibrationOverrides(
          baseline.events,
          calibrationYears: {year},
          model: model,
        );
    trainer.addEvents(semanticApplication.events);
  }
  return trainer.build(minimumTrainingEventCount: minimumTrainingEventCount);
}

_CatalogTruth? _eligibleTruth(
  Map<String, Object?> rawEvent,
  Matsuzaki2006ArchiveInputSpec inputSpec,
) {
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
      depthKm < inputSpec.minimumSearchDepthKm ||
      depthKm > inputSpec.maximumSearchDepthKm ||
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
    originTime: (raw['originTime'] as String?) ?? '',
    latitude: latitude,
    longitude: longitude,
    depthKm: depthKm,
    magnitude: magnitude,
  );
}

String _markdown(Map<String, Object?> report) {
  final summaries = report['modelSummaries']! as Map<String, Object?>;
  final buffer = StringBuffer()
    ..writeln('# Matsuzaki 2006 Archive Joint Evaluation')
    ..writeln()
    ..writeln('Year: `${report['year']}`')
    ..writeln()
    ..writeln('Protocol status: `${report['protocolStatus']}`')
    ..writeln()
    ..writeln(
      'Catalog truth is used only for eligibility and post-inversion error '
      'measurement. It is not used to construct observations or search bounds.',
    )
    ..writeln()
    ..writeln('## Models')
    ..writeln();
  for (final entry in summaries.entries) {
    buffer
      ..writeln('### ${entry.key}')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('|---|---:|');
    final summary = entry.value! as Map<String, Object?>;
    for (final metric in summary.entries) {
      buffer.writeln('| ${metric.key} | ${metric.value} |');
    }
    buffer.writeln();
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

class _CatalogTruth {
  const _CatalogTruth({
    required this.originTime,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
  });

  final String originTime;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;

  Map<String, Object?> toJson() => {
    'originTime': originTime,
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
  };
}
