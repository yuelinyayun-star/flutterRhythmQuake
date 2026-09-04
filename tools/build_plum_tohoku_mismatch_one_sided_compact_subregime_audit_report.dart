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
    '.dart_tool/plum_tohoku_mismatch_one_sided_compact_subregime_audit/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_mismatch_one_sided_compact_subregime_audit.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _threshold = _Threshold('shindo4', 3.5);
const _focusFamily = 'mismatch/one_sided/compact';
const _transitionLabels = ['middle_transition_zone', 'other_family_samples'];
const _localMismatchBands = ['0.50_to_0.67', '0.67_to_0.85', 'gte_0.85'];
const _actualGapBands = [
  'lt_-2.0',
  '-2.0_to_-1.0',
  '-1.0_to_0.0',
  '0.0_to_1.0',
  'gte_1.0',
];
const _evidenceGapBands = ['lt_1.0', '1.0_to_2.0', '2.0_to_3.0', 'gte_3.0'];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuMismatchOneSidedCompactSubregimeAuditJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMismatchOneSidedCompactSubregimeAuditMarkdown(report),
  );

  stdout.writeln(
    'wrote PLUM Tohoku mismatch/one_sided/compact sub-regime audit report',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuMismatchOneSidedCompactSubregimeAuditJson({
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

  final validationFamilySamples = [
    for (final sample in validationSamples)
      if (sample.eventFamilyLabel == _focusFamily) sample,
  ];
  final remainderFamilySamples = [
    for (final sample in remainderSamples)
      if (sample.eventFamilyLabel == _focusFamily) sample,
  ];
  final remainderFamilyFalsePositives = [
    for (final sample in remainderFamilySamples)
      if (!sample.actualPositive) sample,
  ];

  return {
    'schemaVersion':
        'plum_tohoku_mismatch_one_sided_compact_subregime_audit_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku mismatch/one_sided/compact sub-regime audit',
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
      'family': _focusFamily,
    },
    'scope': {
      'removedDominantEvent': dominantEventId,
      'estimatedSourceRegion': _focusRegion,
      'minimumEvidenceCount': _focusMinimumEvidenceCount,
      'maximumNearestEvidenceDistanceKm':
          _focusMaximumNearestEvidenceDistanceKm,
      'baselineThresholdCrossingRequired': true,
    },
    'coverage': {
      'validationFamilySamples': validationFamilySamples.length,
      'remainderFamilySamples': remainderFamilySamples.length,
      'remainderFamilyFalsePositives': remainderFamilyFalsePositives.length,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'summaries': {
      'validationFamily': _summaryJson(validationFamilySamples),
      'remainderFamily': _summaryJson(remainderFamilySamples),
      'remainderFamilyFalsePositives': _summaryJson(
        remainderFamilyFalsePositives,
      ),
    },
    'subRegimeDefinitions': const {
      'middleTransitionLabel':
          'middle_transition_zone vs other_family_samples within mismatch/one_sided/compact',
      'localMismatchBand': {
        '0.50_to_0.67': '0.50 <= localBelowThresholdShare10Km < 0.67',
        '0.67_to_0.85': '0.67 <= localBelowThresholdShare10Km < 0.85',
        'gte_0.85': 'localBelowThresholdShare10Km >= 0.85',
      },
    },
    'transitionRows': _buildBandRows(
      validationFamilySamples,
      remainderFamilySamples,
      labels: _transitionLabels,
      selector: (sample) => sample.subRegimeTransitionLabel,
    ),
    'localMismatchRows': _buildBandRows(
      validationFamilySamples,
      remainderFamilySamples,
      labels: _localMismatchBands,
      selector: (sample) => sample.localMismatchBand,
    ),
    'gapCellRows': _buildGapCellRows(
      validationFamilySamples,
      remainderFamilySamples,
    ),
    'jointSubRegimeRows': _buildJointSubRegimeRows(
      validationFamilySamples,
      remainderFamilySamples,
    ),
    'remainderEventRows': _buildEventRows(remainderFamilySamples),
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

List<Map<String, Object?>> _buildBandRows(
  List<_Sample> validation,
  List<_Sample> remainder, {
  required List<String> labels,
  required String Function(_Sample sample) selector,
}) {
  return [
    for (final label in labels)
      _rowForSlice(
        label: label,
        validation: validation
            .where((sample) => selector(sample) == label)
            .toList(),
        validationTotal: validation.length,
        remainder: remainder
            .where((sample) => selector(sample) == label)
            .toList(),
        remainderTotal: remainder.length,
      ),
  ];
}

List<Map<String, Object?>> _buildGapCellRows(
  List<_Sample> validation,
  List<_Sample> remainder,
) {
  final rows = <Map<String, Object?>>[];
  for (final actualGapBand in _actualGapBands) {
    for (final evidenceGapBand in _evidenceGapBands) {
      final validationRows = validation
          .where(
            (sample) =>
                sample.actualGapBand == actualGapBand &&
                sample.evidenceGapBand == evidenceGapBand,
          )
          .toList();
      final remainderRows = remainder
          .where(
            (sample) =>
                sample.actualGapBand == actualGapBand &&
                sample.evidenceGapBand == evidenceGapBand,
          )
          .toList();
      if (validationRows.isEmpty && remainderRows.isEmpty) continue;
      rows.add({
        'actualGapBand': actualGapBand,
        'evidenceGapBand': evidenceGapBand,
        'validation': _sliceJson(validationRows, validation.length),
        'remainder': _sliceJson(remainderRows, remainder.length),
        'deltaShare':
            (remainder.isEmpty
                ? 0.0
                : remainderRows.length / remainder.length) -
            (validation.isEmpty
                ? 0.0
                : validationRows.length / validation.length),
      });
    }
  }
  rows.sort((left, right) {
    final byRemainder = _number(
      _map(right['remainder'])['count'],
    ).compareTo(_number(_map(left['remainder'])['count']));
    if (byRemainder != 0) return byRemainder;
    return _number(
      _map(right['validation'])['count'],
    ).compareTo(_number(_map(left['validation'])['count']));
  });
  return rows;
}

List<Map<String, Object?>> _buildJointSubRegimeRows(
  List<_Sample> validation,
  List<_Sample> remainder,
) {
  final keys = <String>{};
  for (final sample in [...validation, ...remainder]) {
    keys.add(sample.jointSubRegimeLabel);
  }
  final rows = <Map<String, Object?>>[];
  final ordered = keys.toList()..sort();
  for (final key in ordered) {
    final validationRows = validation
        .where((sample) => sample.jointSubRegimeLabel == key)
        .toList();
    final remainderRows = remainder
        .where((sample) => sample.jointSubRegimeLabel == key)
        .toList();
    if (validationRows.isEmpty && remainderRows.isEmpty) continue;
    rows.add(
      _rowForSlice(
        label: key,
        validation: validationRows,
        validationTotal: validation.length,
        remainder: remainderRows,
        remainderTotal: remainder.length,
      ),
    );
  }
  rows.sort((left, right) {
    final byRemainder = _number(
      _map(right['remainder'])['count'],
    ).compareTo(_number(_map(left['remainder'])['count']));
    if (byRemainder != 0) return byRemainder;
    return _number(
      _map(right['validation'])['count'],
    ).compareTo(_number(_map(left['validation'])['count']));
  });
  return rows;
}

Map<String, Object?> _rowForSlice({
  required String label,
  required List<_Sample> validation,
  required int validationTotal,
  required List<_Sample> remainder,
  required int remainderTotal,
}) {
  final validationJson = _sliceJson(validation, validationTotal);
  final remainderJson = _sliceJson(remainder, remainderTotal);
  return {
    'label': label,
    'validation': validationJson,
    'remainder': remainderJson,
    'deltaShare':
        _number(remainderJson['share']) - _number(validationJson['share']),
    'deltaMiddleTransitionShare':
        _number(remainderJson['middleTransitionShare']) -
        _number(validationJson['middleTransitionShare']),
    'deltaMeanLocalMismatch':
        _number(remainderJson['meanLocalMismatch']) -
        _number(validationJson['meanLocalMismatch']),
  };
}

Map<String, Object?> _sliceJson(List<_Sample> samples, int total) {
  final truePositiveCount = samples
      .where((sample) => sample.actualPositive)
      .length;
  final middleTransitionCount = samples
      .where((sample) => sample.isMiddleTransitionZone)
      .length;
  final plumOnlyFalsePositiveCount = samples
      .where((sample) => sample.plumOnlyFalsePositive)
      .length;
  final meanLocalMismatch = samples.isEmpty
      ? 0.0
      : samples
                .map((sample) => sample.localBelowThresholdShare10Km)
                .fold<double>(0.0, (sum, value) => sum + value) /
            samples.length;
  return {
    'count': samples.length,
    'share': total == 0 ? 0.0 : samples.length / total,
    'truePositiveCount': truePositiveCount,
    'falsePositiveCount': samples.length - truePositiveCount,
    'precision': samples.isEmpty ? 0.0 : truePositiveCount / samples.length,
    'middleTransitionCount': middleTransitionCount,
    'middleTransitionShare': samples.isEmpty
        ? 0.0
        : middleTransitionCount / samples.length,
    'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
    'meanLocalMismatch': meanLocalMismatch,
  };
}

Map<String, Object?> _summaryJson(List<_Sample> samples) => {
  'focusSampleCount': samples.length,
  'truePositiveCount': samples.where((sample) => sample.actualPositive).length,
  'falsePositiveCount': samples
      .where((sample) => !sample.actualPositive)
      .length,
  'precision': samples.isEmpty
      ? 0.0
      : samples.where((sample) => sample.actualPositive).length /
            samples.length,
  'middleTransitionCount': samples
      .where((sample) => sample.isMiddleTransitionZone)
      .length,
  'middleTransitionShare': samples.isEmpty
      ? 0.0
      : samples.where((sample) => sample.isMiddleTransitionZone).length /
            samples.length,
  'plumOnlyFalsePositiveCount': samples
      .where((sample) => sample.plumOnlyFalsePositive)
      .length,
};

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
  'schemaVersion': 'plum_tohoku_mismatch_one_sided_compact_subregime_audit_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method': 'PLUM Tohoku mismatch/one_sided/compact sub-regime audit',
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
    'family': _focusFamily,
  },
  'scope': {
    'removedDominantEvent': 'none',
    'estimatedSourceRegion': _focusRegion,
  },
  'coverage': const {
    'validationFamilySamples': 0,
    'remainderFamilySamples': 0,
    'remainderFamilyFalsePositives': 0,
  },
  'summaries': const {},
  'subRegimeDefinitions': const {},
  'transitionRows': const [],
  'localMismatchRows': const [],
  'gapCellRows': const [],
  'jointSubRegimeRows': const [],
  'remainderEventRows': const [],
  'errors': errors,
};

String plumTohokuMismatchOneSidedCompactSubregimeAuditMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final inputs = _map(report['inputs']);
  final scope = _map(report['scope']);
  final coverage = _map(report['coverage']);
  final summaries = _map(report['summaries']);
  final transitionRows = _list(report['transitionRows']);
  final localMismatchRows = _list(report['localMismatchRows']);
  final gapCellRows = _list(report['gapCellRows']);
  final jointSubRegimeRows = _list(report['jointSubRegimeRows']);
  final remainderEventRows = _list(report['remainderEventRows']);

  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku mismatch/one_sided/compact Sub-Regime Audit')
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
    ..writeln('- Family: `${inputs['family']}`')
    ..writeln('- Removed dominant event: `${scope['removedDominantEvent']}`')
    ..writeln(
      '- Validation family samples: `${coverage['validationFamilySamples']}`',
    )
    ..writeln(
      '- Remainder family samples: `${coverage['remainderFamilySamples']}`',
    )
    ..writeln(
      '- Remainder family false positives: '
      '`${coverage['remainderFamilyFalsePositives']}`',
    )
    ..writeln()
    ..writeln('## Family Summaries')
    ..writeln()
    ..writeln(
      '| Slice | Samples | TP | FP | Precision | Middle Transition | PLUM-only FP |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final key in const [
    'validationFamily',
    'remainderFamily',
    'remainderFamilyFalsePositives',
  ]) {
    final summary = _map(summaries[key]);
    buffer.writeln(
      '| `$key` | ${summary['focusSampleCount']} | ${summary['truePositiveCount']} | '
      '${summary['falsePositiveCount']} | ${_pct(summary['precision'])} | '
      '${summary['middleTransitionCount']} (${_pct(summary['middleTransitionShare'])}) | '
      '${summary['plumOnlyFalsePositiveCount']} |',
    );
  }

  void writeSliceSection(String title, List<Object?> rows) {
    buffer
      ..writeln()
      ..writeln('## $title')
      ..writeln()
      ..writeln(
        '| Label | Validation | Remainder | Delta Share | Delta Middle Transition | Delta Local Mismatch |',
      )
      ..writeln('| --- | --- | --- | ---: | ---: | ---: |');
    for (final raw in rows) {
      final row = _map(raw);
      buffer.writeln(
        '| `${row['label']}` | ${_sliceCell(_map(row['validation']))} | '
        '${_sliceCell(_map(row['remainder']))} | '
        '${_signedPct(row['deltaShare'])} | '
        '${_signedPct(row['deltaMiddleTransitionShare'])} | '
        '${_signed(row['deltaMeanLocalMismatch'])} |',
      );
    }
  }

  writeSliceSection('Transition Rows', transitionRows);
  writeSliceSection('Local Mismatch Rows', localMismatchRows);

  buffer
    ..writeln()
    ..writeln('## Gap Cells')
    ..writeln()
    ..writeln(
      '| Actual Gap | Evidence Gap | Validation | Remainder | Delta Share |',
    )
    ..writeln('| --- | --- | --- | --- | ---: |');
  for (final raw in gapCellRows.take(12)) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['actualGapBand']}` | `${row['evidenceGapBand']}` | '
      '${_sliceCell(_map(row['validation']))} | '
      '${_sliceCell(_map(row['remainder']))} | '
      '${_signedPct(row['deltaShare'])} |',
    );
  }

  writeSliceSection(
    'Joint Sub-Regime Rows',
    jointSubRegimeRows.take(12).toList(),
  );

  buffer
    ..writeln()
    ..writeln('## Remainder Events')
    ..writeln()
    ..writeln(
      '| Event | Samples | TP | FP | Precision | Middle Transition | Winner | Trigger Mix |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |');
  for (final raw in remainderEventRows.take(12)) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['eventId']}` | ${row['count']} | ${row['truePositiveCount']} | '
      '${row['falsePositiveCount']} | ${_pct(row['precision'])} | '
      '${row['middleTransitionCount']} (${_pct(row['middleTransitionShare'])}) | '
      '`${row['dominantWinnerFamily']}` | ${_mixCell(_map(row['sourceTriggerCounts']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report stays diagnostic-only and only tests whether a narrower '
      'frozen-only slice exists inside `mismatch/one_sided/compact`.',
    )
    ..writeln(
      '- It does not tune PLUM, mutate raw predicted intensity, or connect '
      'results to UI, wording, notification, or runtime policy.',
    )
    ..writeln();
  return buffer.toString();
}

String _sliceCell(Map<String, Object?> row) {
  return '${row['count']} / ${_pct(row['share'])}, '
      'P ${_pct(row['precision'])}, '
      'MT ${_pct(row['middleTransitionShare'])}, '
      'LM ${_number(row['meanLocalMismatch']).toStringAsFixed(2)}';
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

class _EventAccumulator {
  int count = 0;
  int truePositiveCount = 0;
  int middleTransitionCount = 0;
  final sourceTriggerCounts = <String, int>{};
  final sourceWinnerCounts = <String, int>{};

  void add(_Sample sample) {
    count++;
    if (sample.actualPositive) truePositiveCount++;
    if (sample.isMiddleTransitionZone) middleTransitionCount++;
    sourceTriggerCounts[sample.sourceTriggerFamily] =
        (sourceTriggerCounts[sample.sourceTriggerFamily] ?? 0) + 1;
    sourceWinnerCounts[sample.sourceWinnerFamily] =
        (sourceWinnerCounts[sample.sourceWinnerFamily] ?? 0) + 1;
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
    'sourceTriggerCounts': sourceTriggerCounts,
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

  String get subRegimeTransitionLabel => isMiddleTransitionZone
      ? 'middle_transition_zone'
      : 'other_family_samples';

  String get localMismatchBand {
    final share = localBelowThresholdShare10Km;
    if (share < 0.67) return '0.50_to_0.67';
    if (share < 0.85) return '0.67_to_0.85';
    return 'gte_0.85';
  }

  String get jointSubRegimeLabel =>
      '$subRegimeTransitionLabel|$localMismatchBand|$actualGapBand|$evidenceGapBand';
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

String _signedPct(Object? value) {
  final number = _number(value) * 100;
  final sign = number > 0 ? '+' : '';
  return '$sign${number.toStringAsFixed(1)}pp';
}

String _signed(Object? value) {
  final number = _number(value);
  final sign = number > 0 ? '+' : '';
  return '$sign${number.toStringAsFixed(2)}';
}
