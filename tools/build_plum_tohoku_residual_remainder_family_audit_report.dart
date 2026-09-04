import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_tohoku_residual_remainder_family_audit/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_residual_remainder_family_audit.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _threshold = _Threshold('shindo4', 3.5);

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuResidualRemainderFamilyAuditJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuResidualRemainderFamilyAuditMarkdown(report),
  );

  stdout.writeln('wrote PLUM Tohoku residual remainder family audit report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuResidualRemainderFamilyAuditJson({
  String dataDirectory = _defaultDataDirectory,
  String modelPath = _defaultModelPath,
}) {
  final errors = <String>[];
  final modelFile = File(modelPath);
  final splitFile = File('$dataDirectory/splits.json');
  final annualFiles = [
    File('$dataDirectory/jma_final_intensity_2020.json'),
    File('$dataDirectory/jma_final_intensity_2021.json'),
    File('$dataDirectory/jma_final_intensity_2022.json'),
  ];
  if (!modelFile.existsSync()) errors.add('model_missing:$modelPath');
  if (!splitFile.existsSync()) {
    errors.add('split_manifest_missing:${splitFile.path}');
  }
  for (final file in annualFiles) {
    if (!file.existsSync()) errors.add('annual_dataset_missing:${file.path}');
  }
  if (errors.isNotEmpty) {
    return _emptyReport(
      errors: errors,
      dataDirectory: dataDirectory,
      modelPath: modelPath,
    );
  }

  final annualDatasets = [
    for (final file in annualFiles)
      decodeJmaIntensityDataset(file.readAsStringSync()),
  ];
  final splits =
      jsonDecode(splitFile.readAsStringSync()) as Map<String, Object?>;
  final synthetic = const SyntheticRevealDatasetBuilder(
    generatedSplits: ['validation', 'test'],
  ).build(annualDatasets: annualDatasets, splitManifest: splits);

  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumPredictor = const PlumLikeIntensityPredictor(
    radiusKm: _plumRadiusKm,
    dampingPer10Km: _plumDampingPer10Km,
  );
  final plumR20D050 = const PlumLikeIntensityPredictor(
    radiusKm: 20.0,
    dampingPer10Km: 0.50,
  );
  final plumR30D075 = const PlumLikeIntensityPredictor(
    radiusKm: 30.0,
    dampingPer10Km: 0.75,
  );

  final validationAccumulator = _SplitAccumulator();
  final testAccumulator = _SplitAccumulator();
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

  for (final splitName in const ['validation', 'test']) {
    final dataset = synthetic.datasetsBySplit[splitName]!;
    final splitAccumulator = splitName == 'validation'
        ? validationAccumulator
        : testAccumulator;
    for (final rawEvent in _list(dataset['events'])) {
      final event = StaticIntensityEvent.fromJson(_map(rawEvent));
      final magnitude = event.magnitude;
      if (magnitude == null || !magnitude.isFinite) {
        skippedMissingMagnitude++;
        continue;
      }
      final stationsById = {
        for (final station in event.stations) station.stationId: station,
      };
      for (final variant in event.variants) {
        final retained = [
          for (final id in variant.retainedStationIds)
            if (stationsById[id] != null) stationsById[id]!,
        ];
        final estimate = locator.locate(retained);
        if (estimate == null) {
          skippedNoEstimate++;
          continue;
        }
        splitAccumulator.variantCount++;
        if (_eventLatitudeBucket(estimate.latitude) != _focusRegion) continue;
        for (final station in event.stations) {
          splitAccumulator.stationForecastCount++;
          final jma = jmaPredictor
              .predict(
                magnitude: magnitude,
                sourceLatitude: estimate.latitude,
                sourceLongitude: estimate.longitude,
                depthKm: estimate.depthKm,
                stationLatitude: station.latitude,
                stationLongitude: station.longitude,
              )
              .intensity;
          final plum = plumPredictor.predict(
            targetStation: station,
            observedStations: retained,
          );
          final baselineRaw = math.max(jma, plum.intensity);
          if (baselineRaw < _threshold.value) continue;
          if (plum.evidenceCount < _focusMinimumEvidenceCount) continue;
          if (!plum.nearestEvidenceDistanceKm.isFinite ||
              plum.nearestEvidenceDistanceKm >=
                  _focusMaximumNearestEvidenceDistanceKm) {
            continue;
          }
          final r20 = plumR20D050.predict(
            targetStation: station,
            observedStations: retained,
          );
          final r30D075 = plumR30D075.predict(
            targetStation: station,
            observedStations: retained,
          );
          splitAccumulator.add(
            _buildSample(
              event: event,
              variant: variant,
              targetStation: station,
              retainedStations: retained,
              threshold: _threshold,
              jmaPredictedIntensity: jma,
              plum: plum,
              r20: r20.intensity,
              r30D075: r30D075.intensity,
            ),
          );
        }
      }
    }
  }

  final validationSamples = validationAccumulator.samples;
  final testSamples = testAccumulator.samples;
  final dominantEventId = _dominantEventId(testSamples);
  final remainderSamples = [
    for (final sample in testSamples)
      if (sample.eventId != dominantEventId) sample,
  ];
  final remainderFalsePositives = [
    for (final sample in remainderSamples)
      if (!sample.actualPositive) sample,
  ];
  final remainderPlumOnlyFalsePositives = [
    for (final sample in remainderSamples)
      if (sample.plumOnlyFalsePositive) sample,
  ];
  final remainderPlumHigherFalsePositives = [
    for (final sample in remainderSamples)
      if (!sample.actualPositive && sample.sourceWinnerFamily == 'plum_higher')
        sample,
  ];

  final validationFamilyRows = _buildFamilyRows(validationSamples);
  final remainderFamilyRows = _buildFamilyRows(remainderSamples);
  final remainderFalsePositiveFamilyRows = _buildFamilyRows(
    remainderFalsePositives,
  );
  final plumOnlyFalsePositiveFamilyRows = _buildFamilyRows(
    remainderPlumOnlyFalsePositives,
  );
  final plumHigherFalsePositiveFamilyRows = _buildFamilyRows(
    remainderPlumHigherFalsePositives,
  );

  return {
    'schemaVersion': 'plum_tohoku_residual_remainder_family_audit_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku residual remainder family audit',
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'suppressionApplied': false,
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'modelPath': modelPath,
      'splits': ['validation', 'test'],
      'threshold': _threshold.label,
    },
    'focusFilter': {
      'estimatedSourceRegion': _focusRegion,
      'minimumEvidenceCount': _focusMinimumEvidenceCount,
      'maximumNearestEvidenceDistanceKm':
          _focusMaximumNearestEvidenceDistanceKm,
      'baselineThresholdCrossingRequired': true,
      'plumMarginGateApplied': false,
    },
    'dominantEvent': {
      'eventId': dominantEventId,
      'removedFromTest': dominantEventId != 'none',
    },
    'coverage': {
      'validationVariants': validationAccumulator.variantCount,
      'testVariants': testAccumulator.variantCount,
      'validationStationForecasts': validationAccumulator.stationForecastCount,
      'testStationForecasts': testAccumulator.stationForecastCount,
      'remainderFocusSamples': remainderSamples.length,
      'remainderFalsePositives': remainderFalsePositives.length,
      'remainderPlumOnlyFalsePositives': remainderPlumOnlyFalsePositives.length,
      'remainderPlumHigherFalsePositives':
          remainderPlumHigherFalsePositives.length,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'summaries': {
      'validation': _summaryJson(validationSamples),
      'remainder': _summaryJson(remainderSamples),
      'remainderFalsePositives': _summaryJson(remainderFalsePositives),
      'remainderPlumOnlyFalsePositives': _summaryJson(
        remainderPlumOnlyFalsePositives,
      ),
      'remainderPlumHigherFalsePositives': _summaryJson(
        remainderPlumHigherFalsePositives,
      ),
    },
    'familyDefinitions': const {
      'eventFamily':
          'localConsistency/geometry/spread where localConsistency uses below-threshold share within 10km, geometry uses supporting quadrants, spread uses max support spread',
      'dominanceQuestion':
          'whether remainder plum_only / plum_higher false positives collapse into one stable family',
    },
    'validationFamilyRows': validationFamilyRows,
    'remainderFamilyRows': remainderFamilyRows,
    'remainderFalsePositiveFamilyRows': remainderFalsePositiveFamilyRows,
    'remainderPlumOnlyFalsePositiveFamilyRows': plumOnlyFalsePositiveFamilyRows,
    'remainderPlumHigherFalsePositiveFamilyRows':
        plumHigherFalsePositiveFamilyRows,
    'dominanceSummary': {
      'remainderAll': _dominanceSummary(remainderFamilyRows),
      'remainderFalsePositives': _dominanceSummary(
        remainderFalsePositiveFamilyRows,
      ),
      'remainderPlumOnlyFalsePositives': _dominanceSummary(
        plumOnlyFalsePositiveFamilyRows,
      ),
      'remainderPlumHigherFalsePositives': _dominanceSummary(
        plumHigherFalsePositiveFamilyRows,
      ),
    },
    'remainderEventRows': _buildEventRows(remainderSamples),
    'errors': errors,
  };
}

_Sample _buildSample({
  required StaticIntensityEvent event,
  required StaticIntensityVariant variant,
  required StaticIntensityStation targetStation,
  required List<StaticIntensityStation> retainedStations,
  required _Threshold threshold,
  required double jmaPredictedIntensity,
  required PlumLikeIntensityPrediction plum,
  required double r20,
  required double r30D075,
}) {
  final supportingEvidence = _supportingEvidence(
    retainedStations: retainedStations,
    targetStation: targetStation,
    threshold: threshold.value,
  );
  final strongestEvidence = supportingEvidence.isEmpty
      ? null
      : supportingEvidence.reduce((left, right) {
          if (left.propagatedIntensity == right.propagatedIntensity) {
            return left.targetDistanceKm <= right.targetDistanceKm
                ? left
                : right;
          }
          return left.propagatedIntensity >= right.propagatedIntensity
              ? left
              : right;
        });
  final local10 = _localNeighborSummary(
    event.stations,
    targetStation,
    threshold.value,
    10.0,
  );
  final supportShape = _supportShape(
    targetStation: targetStation,
    evidenceStations: supportingEvidence,
  );

  return _Sample(
    eventId: event.eventId,
    variantId: variant.variantId,
    stationId: targetStation.stationId,
    thresholdValue: threshold.value,
    actual: targetStation.intensity,
    jma: jmaPredictedIntensity,
    plum: plum.intensity,
    r20: r20,
    r30D075: r30D075,
    evidenceTargetGap: strongestEvidence == null
        ? double.nan
        : strongestEvidence.station.intensity - targetStation.intensity,
    localBelowThresholdShare10Km: local10.belowThresholdShare,
    supportingEvidenceQuadrantCoverage: supportShape.quadrantCoverage,
    supportingEvidenceMaxSpreadKm: supportShape.maxSpreadKm,
  );
}

List<Map<String, Object?>> _buildFamilyRows(List<_Sample> samples) {
  final byFamily = <String, _FamilyAccumulator>{};
  for (final sample in samples) {
    byFamily
        .putIfAbsent(sample.eventFamilyLabel, _FamilyAccumulator.new)
        .add(sample);
  }
  final rows = [
    for (final entry in byFamily.entries) entry.value.toJson(family: entry.key),
  ];
  rows.sort((left, right) {
    final byCount = _number(right['count']).compareTo(_number(left['count']));
    if (byCount != 0) return byCount;
    return _number(
      right['falsePositiveCount'],
    ).compareTo(_number(left['falsePositiveCount']));
  });
  return rows;
}

Map<String, Object?> _dominanceSummary(List<Map<String, Object?>> familyRows) {
  if (familyRows.isEmpty) {
    return const {
      'topFamily': 'none',
      'topFamilyShare': 0.0,
      'top2CumulativeShare': 0.0,
      'top3CumulativeShare': 0.0,
      'familyCount': 0,
    };
  }
  final total = familyRows.fold<double>(
    0.0,
    (sum, row) => sum + _number(_map(row)['count']),
  );
  if (total == 0.0) {
    return {
      'topFamily': _map(familyRows.first)['family'],
      'topFamilyShare': 0.0,
      'top2CumulativeShare': 0.0,
      'top3CumulativeShare': 0.0,
      'familyCount': familyRows.length,
    };
  }
  double cumulative(int n) =>
      familyRows
          .take(n)
          .fold<double>(0.0, (sum, row) => sum + _number(_map(row)['count'])) /
      total;
  final top = _map(familyRows.first);
  return {
    'topFamily': top['family'],
    'topFamilyShare': _number(top['count']) / total,
    'top2CumulativeShare': cumulative(2),
    'top3CumulativeShare': cumulative(3),
    'familyCount': familyRows.length,
  };
}

Map<String, Object?> _summaryJson(List<_Sample> samples) {
  final truePositiveCount = samples
      .where((sample) => sample.actualPositive)
      .length;
  final middleTransitionCount = samples
      .where((sample) => sample.isMiddleTransitionZone)
      .length;
  final plumOnlyFalsePositiveCount = samples
      .where((sample) => sample.plumOnlyFalsePositive)
      .length;
  return {
    'focusSampleCount': samples.length,
    'truePositiveCount': truePositiveCount,
    'falsePositiveCount': samples.length - truePositiveCount,
    'precision': samples.isEmpty ? 0.0 : truePositiveCount / samples.length,
    'middleTransitionCount': middleTransitionCount,
    'middleTransitionShare': samples.isEmpty
        ? 0.0
        : middleTransitionCount / samples.length,
    'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
  };
}

String _dominantEventId(List<_Sample> samples) {
  if (samples.isEmpty) return 'none';
  final counts = <String, int>{};
  for (final sample in samples) {
    counts[sample.eventId] = (counts[sample.eventId] ?? 0) + 1;
  }
  return counts.entries.reduce((left, right) {
    if (left.value == right.value) {
      return left.key.compareTo(right.key) <= 0 ? left : right;
    }
    return left.value > right.value ? left : right;
  }).key;
}

List<Map<String, Object?>> _buildEventRows(List<_Sample> samples) {
  final byEvent = <String, _EventAccumulator>{};
  for (final sample in samples) {
    byEvent.putIfAbsent(sample.eventId, _EventAccumulator.new).add(sample);
  }
  final rows = [
    for (final entry in byEvent.entries) entry.value.toJson(eventId: entry.key),
  ];
  rows.sort((left, right) {
    final byCount = _number(right['count']).compareTo(_number(left['count']));
    if (byCount != 0) return byCount;
    return _number(
      right['middleTransitionCount'],
    ).compareTo(_number(left['middleTransitionCount']));
  });
  return rows;
}

List<_EvidenceStation> _supportingEvidence({
  required List<StaticIntensityStation> retainedStations,
  required StaticIntensityStation targetStation,
  required double threshold,
}) {
  final supportingEvidence = <_EvidenceStation>[];
  for (final observed in retainedStations) {
    if (observed.stationId == targetStation.stationId) continue;
    final distance = QuakeCalculator.haversineDistance(
      targetStation.latitude,
      targetStation.longitude,
      observed.latitude,
      observed.longitude,
    );
    if (distance > _plumRadiusKm) continue;
    final propagated =
        observed.intensity - _plumDampingPer10Km * (distance / 10.0);
    if (propagated >= threshold) {
      supportingEvidence.add(
        _EvidenceStation(
          station: observed,
          targetDistanceKm: distance,
          propagatedIntensity: propagated,
        ),
      );
    }
  }
  return supportingEvidence;
}

_NeighborSummary _localNeighborSummary(
  List<StaticIntensityStation> stations,
  StaticIntensityStation target,
  double threshold,
  double radiusKm,
) {
  var count = 0;
  var below = 0;
  for (final station in stations) {
    if (station.stationId == target.stationId) continue;
    final distance = QuakeCalculator.haversineDistance(
      target.latitude,
      target.longitude,
      station.latitude,
      station.longitude,
    );
    if (distance > radiusKm) continue;
    count++;
    if (station.intensity < threshold) below++;
  }
  return _NeighborSummary(
    count: count,
    belowThresholdShare: count == 0 ? 0.0 : below / count,
  );
}

_SupportShape _supportShape({
  required StaticIntensityStation targetStation,
  required List<_EvidenceStation> evidenceStations,
}) {
  if (evidenceStations.isEmpty) {
    return const _SupportShape(quadrantCoverage: 0, maxSpreadKm: 0.0);
  }
  final quadrants = <int>{};
  var maxSpread = 0.0;
  for (final evidence in evidenceStations) {
    quadrants.add(
      _quadrant(
        targetLat: targetStation.latitude,
        targetLng: targetStation.longitude,
        lat: evidence.station.latitude,
        lng: evidence.station.longitude,
      ),
    );
  }
  for (var i = 0; i < evidenceStations.length; i++) {
    for (var j = i + 1; j < evidenceStations.length; j++) {
      final distance = QuakeCalculator.haversineDistance(
        evidenceStations[i].station.latitude,
        evidenceStations[i].station.longitude,
        evidenceStations[j].station.latitude,
        evidenceStations[j].station.longitude,
      );
      if (distance > maxSpread) maxSpread = distance;
    }
  }
  return _SupportShape(
    quadrantCoverage: quadrants.length,
    maxSpreadKm: maxSpread,
  );
}

int _quadrant({
  required double targetLat,
  required double targetLng,
  required double lat,
  required double lng,
}) {
  final north = lat >= targetLat;
  final east = lng >= targetLng;
  if (north && east) return 0;
  if (north && !east) return 1;
  if (!north && east) return 2;
  return 3;
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
}) => {
  'schemaVersion': 'plum_tohoku_residual_remainder_family_audit_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method': 'PLUM Tohoku residual remainder family audit',
    'rawPredictedIntensityMutated': false,
    'frozenTestEvaluated': true,
    'productionReady': false,
    'productionUiConnected': false,
    'diagnosticOnly': true,
    'parametersTuned': false,
    'suppressionApplied': false,
    'plumRadiusKm': _plumRadiusKm,
    'plumDampingPer10Km': _plumDampingPer10Km,
  },
  'inputs': {
    'dataDirectory': dataDirectory,
    'modelPath': modelPath,
    'splits': ['validation', 'test'],
    'threshold': _threshold.label,
  },
  'focusFilter': {
    'estimatedSourceRegion': _focusRegion,
    'minimumEvidenceCount': _focusMinimumEvidenceCount,
    'maximumNearestEvidenceDistanceKm': _focusMaximumNearestEvidenceDistanceKm,
    'baselineThresholdCrossingRequired': true,
    'plumMarginGateApplied': false,
  },
  'dominantEvent': const {'eventId': 'none', 'removedFromTest': false},
  'coverage': const {
    'remainderFocusSamples': 0,
    'remainderFalsePositives': 0,
    'remainderPlumOnlyFalsePositives': 0,
    'remainderPlumHigherFalsePositives': 0,
  },
  'summaries': const {},
  'familyDefinitions': const {},
  'validationFamilyRows': const [],
  'remainderFamilyRows': const [],
  'remainderFalsePositiveFamilyRows': const [],
  'remainderPlumOnlyFalsePositiveFamilyRows': const [],
  'remainderPlumHigherFalsePositiveFamilyRows': const [],
  'dominanceSummary': const {},
  'remainderEventRows': const [],
  'errors': errors,
};

String plumTohokuResidualRemainderFamilyAuditMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final dominantEvent = _map(report['dominantEvent']);
  final summaries = _map(report['summaries']);
  final dominanceSummary = _map(report['dominanceSummary']);
  final validationFamilyRows = _list(report['validationFamilyRows']);
  final remainderFamilyRows = _list(report['remainderFamilyRows']);
  final remainderFalsePositiveFamilyRows = _list(
    report['remainderFalsePositiveFamilyRows'],
  );
  final remainderPlumOnlyFalsePositiveFamilyRows = _list(
    report['remainderPlumOnlyFalsePositiveFamilyRows'],
  );
  final remainderPlumHigherFalsePositiveFamilyRows = _list(
    report['remainderPlumHigherFalsePositiveFamilyRows'],
  );
  final remainderEventRows = _list(report['remainderEventRows']);

  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Residual Remainder Family Audit')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Method: `${policy['method']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln('- Production UI connected: `${policy['productionUiConnected']}`')
    ..writeln('- Diagnostic only: `${policy['diagnosticOnly']}`')
    ..writeln('- Parameters tuned: `${policy['parametersTuned']}`')
    ..writeln('- Suppression applied: `${policy['suppressionApplied']}`')
    ..writeln(
      '- Raw predicted intensity mutated: '
      '`${policy['rawPredictedIntensityMutated']}`',
    )
    ..writeln()
    ..writeln('## Scope')
    ..writeln()
    ..writeln('- Removed dominant event: `${dominantEvent['eventId']}`')
    ..writeln(
      '- Estimated-source region: `${focusFilter['estimatedSourceRegion']}`',
    )
    ..writeln(
      '- Minimum evidence count: `${focusFilter['minimumEvidenceCount']}`',
    )
    ..writeln(
      '- Maximum nearest evidence distance: '
      '`${focusFilter['maximumNearestEvidenceDistanceKm']} km`',
    )
    ..writeln(
      '- Remainder focus samples: `${coverage['remainderFocusSamples']}`',
    )
    ..writeln(
      '- Remainder false positives: `${coverage['remainderFalsePositives']}`',
    )
    ..writeln(
      '- Remainder PLUM-only false positives: '
      '`${coverage['remainderPlumOnlyFalsePositives']}`',
    )
    ..writeln(
      '- Remainder PLUM-higher false positives: '
      '`${coverage['remainderPlumHigherFalsePositives']}`',
    )
    ..writeln()
    ..writeln('## Slice Summaries')
    ..writeln()
    ..writeln(
      '| Slice | Samples | TP | FP | Precision | Middle Transition | PLUM-only FP |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final name in const [
    'validation',
    'remainder',
    'remainderFalsePositives',
    'remainderPlumOnlyFalsePositives',
    'remainderPlumHigherFalsePositives',
  ]) {
    final summary = _map(summaries[name]);
    buffer.writeln(
      '| `$name` | ${summary['focusSampleCount']} | ${summary['truePositiveCount']} | '
      '${summary['falsePositiveCount']} | ${_pct(summary['precision'])} | '
      '${summary['middleTransitionCount']} (${_pct(summary['middleTransitionShare'])}) | '
      '${summary['plumOnlyFalsePositiveCount']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Dominance Summary')
    ..writeln()
    ..writeln(
      '| Slice | Top Family | Top Share | Top-2 | Top-3 | Family Count |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: |');
  for (final name in const [
    'remainderAll',
    'remainderFalsePositives',
    'remainderPlumOnlyFalsePositives',
    'remainderPlumHigherFalsePositives',
  ]) {
    final summary = _map(dominanceSummary[name]);
    buffer.writeln(
      '| `$name` | `${summary['topFamily']}` | ${_pct(summary['topFamilyShare'])} | '
      '${_pct(summary['top2CumulativeShare'])} | '
      '${_pct(summary['top3CumulativeShare'])} | ${summary['familyCount']} |',
    );
  }

  void writeFamilySection(String title, List<Object?> rows) {
    buffer
      ..writeln()
      ..writeln('## $title')
      ..writeln()
      ..writeln(
        '| Family | Count | TP | FP | Precision | Middle Transition | PLUM-only FP |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final raw in rows.take(12)) {
      final row = _map(raw);
      buffer.writeln(
        '| `${row['family']}` | ${row['count']} | ${row['truePositiveCount']} | '
        '${row['falsePositiveCount']} | ${_pct(row['precision'])} | '
        '${row['middleTransitionCount']} (${_pct(row['middleTransitionShare'])}) | '
        '${row['plumOnlyFalsePositiveCount']} |',
      );
    }
  }

  writeFamilySection('Validation Families', validationFamilyRows);
  writeFamilySection('Remainder Families', remainderFamilyRows);
  writeFamilySection(
    'Remainder False-Positive Families',
    remainderFalsePositiveFamilyRows,
  );
  writeFamilySection(
    'Remainder PLUM-Only False-Positive Families',
    remainderPlumOnlyFalsePositiveFamilyRows,
  );
  writeFamilySection(
    'Remainder PLUM-Higher False-Positive Families',
    remainderPlumHigherFalsePositiveFamilyRows,
  );

  buffer
    ..writeln()
    ..writeln('## Remainder Events')
    ..writeln()
    ..writeln(
      '| Event | Samples | TP | FP | Precision | Middle Transition | Winner | Family | Trigger Mix | Winner Mix |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |',
    );
  for (final raw in remainderEventRows.take(12)) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['eventId']}` | ${row['count']} | ${row['truePositiveCount']} | '
      '${row['falsePositiveCount']} | ${_pct(row['precision'])} | '
      '${row['middleTransitionCount']} (${_pct(row['middleTransitionShare'])}) | '
      '`${row['dominantWinnerFamily']}` | `${row['dominantEventFamily']}` | '
      '${_mixCell(_map(row['sourceTriggerCounts']))} | '
      '${_mixCell(_map(row['sourceWinnerCounts']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report stays diagnostic-only and only audits whether the '
      'leave-top-event-out remainder forms a stable transferable family.',
    )
    ..writeln(
      '- It does not tune PLUM, mutate raw predicted intensity, or connect '
      'results to UI, wording, notification, or runtime policy.',
    )
    ..writeln();
  return buffer.toString();
}

String _mixCell(Map<String, Object?> mix) {
  final entries = mix.entries.toList()
    ..sort(
      (left, right) => _number(right.value).compareTo(_number(left.value)),
    );
  return entries
      .where((entry) => _number(entry.value) > 0)
      .map((entry) => '${entry.key}:${entry.value}')
      .join(', ');
}

class _SplitAccumulator {
  int variantCount = 0;
  int stationForecastCount = 0;
  final samples = <_Sample>[];

  void add(_Sample sample) => samples.add(sample);
}

class _FamilyAccumulator {
  int count = 0;
  int truePositiveCount = 0;
  int middleTransitionCount = 0;
  int plumOnlyFalsePositiveCount = 0;

  void add(_Sample sample) {
    count++;
    if (sample.actualPositive) truePositiveCount++;
    if (sample.isMiddleTransitionZone) middleTransitionCount++;
    if (sample.plumOnlyFalsePositive) plumOnlyFalsePositiveCount++;
  }

  Map<String, Object?> toJson({required String family}) => {
    'family': family,
    'count': count,
    'truePositiveCount': truePositiveCount,
    'falsePositiveCount': count - truePositiveCount,
    'precision': count == 0 ? 0.0 : truePositiveCount / count,
    'middleTransitionCount': middleTransitionCount,
    'middleTransitionShare': count == 0 ? 0.0 : middleTransitionCount / count,
    'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
  };
}

class _EventAccumulator {
  int count = 0;
  int truePositiveCount = 0;
  int middleTransitionCount = 0;
  final sourceTriggerCounts = <String, int>{};
  final sourceWinnerCounts = <String, int>{};
  final eventFamilyCounts = <String, int>{};

  void add(_Sample sample) {
    count++;
    if (sample.actualPositive) truePositiveCount++;
    if (sample.isMiddleTransitionZone) middleTransitionCount++;
    sourceTriggerCounts[sample.sourceTriggerFamily] =
        (sourceTriggerCounts[sample.sourceTriggerFamily] ?? 0) + 1;
    sourceWinnerCounts[sample.sourceWinnerFamily] =
        (sourceWinnerCounts[sample.sourceWinnerFamily] ?? 0) + 1;
    eventFamilyCounts[sample.eventFamilyLabel] =
        (eventFamilyCounts[sample.eventFamilyLabel] ?? 0) + 1;
  }

  Map<String, Object?> toJson({required String eventId}) => {
    'eventId': eventId,
    'count': count,
    'truePositiveCount': truePositiveCount,
    'falsePositiveCount': count - truePositiveCount,
    'precision': count == 0 ? 0.0 : truePositiveCount / count,
    'middleTransitionCount': middleTransitionCount,
    'middleTransitionShare': count == 0 ? 0.0 : middleTransitionCount / count,
    'dominantWinnerFamily': _maxKey(sourceWinnerCounts),
    'dominantEventFamily': _maxKey(eventFamilyCounts),
    'sourceTriggerCounts': sourceTriggerCounts,
    'sourceWinnerCounts': sourceWinnerCounts,
  };
}

String _maxKey(Map<String, int> counts) {
  if (counts.isEmpty) return 'none';
  var bestKey = counts.keys.first;
  var bestValue = counts[bestKey]!;
  for (final entry in counts.entries.skip(1)) {
    if (entry.value > bestValue) {
      bestKey = entry.key;
      bestValue = entry.value;
    }
  }
  return bestKey;
}

class _Sample {
  final String eventId;
  final String variantId;
  final String stationId;
  final double thresholdValue;
  final double actual;
  final double jma;
  final double plum;
  final double r20;
  final double r30D075;
  final double evidenceTargetGap;
  final double localBelowThresholdShare10Km;
  final int supportingEvidenceQuadrantCoverage;
  final double supportingEvidenceMaxSpreadKm;

  const _Sample({
    required this.eventId,
    required this.variantId,
    required this.stationId,
    required this.thresholdValue,
    required this.actual,
    required this.jma,
    required this.plum,
    required this.r20,
    required this.r30D075,
    required this.evidenceTargetGap,
    required this.localBelowThresholdShare10Km,
    required this.supportingEvidenceQuadrantCoverage,
    required this.supportingEvidenceMaxSpreadKm,
  });

  bool get actualPositive => actual >= thresholdValue;

  bool get plumOnlyFalsePositive =>
      !actualPositive && plum >= thresholdValue && jma < thresholdValue;

  String get sourceTriggerFamily {
    final jmaPositive = jma >= thresholdValue;
    final plumPositive = plum >= thresholdValue;
    if (jmaPositive && !plumPositive) return 'jma_only';
    if (plumPositive && !jmaPositive) return 'plum_only';
    return 'both';
  }

  String get sourceWinnerFamily {
    if ((plum - jma).abs() < 1e-9) return 'tied';
    return plum > jma ? 'plum_higher' : 'jma_higher';
  }

  String get localConsistencyLabel {
    if (localBelowThresholdShare10Km < 0.25) return 'consistent';
    if (localBelowThresholdShare10Km < 0.50) return 'mixed';
    return 'mismatch';
  }

  String get geometryBand =>
      supportingEvidenceQuadrantCoverage >= 3 ? 'surrounded' : 'one_sided';

  String get spreadBand {
    if (supportingEvidenceMaxSpreadKm < 20.0) return 'compact';
    if (supportingEvidenceMaxSpreadKm < 40.0) return 'moderate';
    return 'wide';
  }

  String get eventFamilyLabel =>
      '$localConsistencyLabel/$geometryBand/$spreadBand';

  String get actualGapBand {
    final gap = actual - thresholdValue;
    if (gap < -2.0) return 'lt_-2.0';
    if (gap < -1.0) return '-2.0_to_-1.0';
    if (gap < 0.0) return '-1.0_to_0.0';
    if (gap < 1.0) return '0.0_to_1.0';
    return 'gte_1.0';
  }

  String get evidenceGapBand {
    if (!evidenceTargetGap.isFinite) return 'missing';
    if (evidenceTargetGap < 1.0) return 'lt_1.0';
    if (evidenceTargetGap < 2.0) return '1.0_to_2.0';
    if (evidenceTargetGap < 3.0) return '2.0_to_3.0';
    return 'gte_3.0';
  }

  bool get isMiddleTransitionZone =>
      localConsistencyLabel == 'mismatch' &&
      const ['-1.0_to_0.0', '0.0_to_1.0'].contains(actualGapBand) &&
      const ['1.0_to_2.0', '2.0_to_3.0'].contains(evidenceGapBand);
}

class _EvidenceStation {
  final StaticIntensityStation station;
  final double targetDistanceKm;
  final double propagatedIntensity;

  const _EvidenceStation({
    required this.station,
    required this.targetDistanceKm,
    required this.propagatedIntensity,
  });
}

class _NeighborSummary {
  final int count;
  final double belowThresholdShare;

  const _NeighborSummary({
    required this.count,
    required this.belowThresholdShare,
  });
}

class _SupportShape {
  final int quadrantCoverage;
  final double maxSpreadKm;

  const _SupportShape({
    required this.quadrantCoverage,
    required this.maxSpreadKm,
  });
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _eventLatitudeBucket(double latitude) {
  if (latitude >= 41.0) return 'hokkaido';
  if (latitude >= 37.5) return 'tohoku';
  if (latitude >= 34.5) return 'kanto_chubu';
  return 'west_south';
}

StaticAttenuationModel _modelFromJson(Map<String, Object?> json) {
  return StaticAttenuationModel(
    modelId: json['modelId']?.toString() ?? 'static_intensity_attenuation_v1',
    logDistanceCoefficient: _number(json['logDistanceCoefficient']),
    linearDistanceCoefficient: _number(json['linearDistanceCoefficient']),
    nearDistanceKm: _number(json['nearDistanceKm']),
    huberDelta: _number(json['huberDelta']),
    residualScale: _number(json['residualScale']),
    centroidPenaltyPerKm: _number(json['centroidPenaltyPerKm']),
    depthClassesKm: [
      for (final raw in _list(json['depthClassesKm'])) _number(raw),
    ],
  );
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

String _pct(Object? value) => '${(_number(value) * 100).toStringAsFixed(1)}%';
