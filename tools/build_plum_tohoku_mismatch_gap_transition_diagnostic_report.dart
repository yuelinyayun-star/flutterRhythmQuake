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
    '.dart_tool/plum_tohoku_mismatch_gap_transition_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_mismatch_gap_transition_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _localNeighbor10Km = 10.0;
const _localNeighbor20Km = 20.0;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusMinimumMargin = 1.0;
const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];
const _actualGapBands = [
  'lt_-2.0',
  '-2.0_to_-1.0',
  '-1.0_to_0.0',
  '0.0_to_1.0',
  'gte_1.0',
];
const _evidenceGapBands = [
  'lt_1.0',
  '1.0_to_2.0',
  '2.0_to_3.0',
  'gte_3.0',
  'missing',
];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuMismatchGapTransitionDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMismatchGapTransitionDiagnosticMarkdown(report),
  );

  stdout.writeln('wrote PLUM Tohoku mismatch gap-transition diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuMismatchGapTransitionDiagnosticJson({
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

  final splitAccumulators = {
    'validation': _SplitAccumulator(),
    'test': _SplitAccumulator(),
  };
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

  for (final splitName in const ['validation', 'test']) {
    final dataset = synthetic.datasetsBySplit[splitName]!;
    final splitAccumulator = splitAccumulators[splitName]!;
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
        final estimatedRegion = _eventLatitudeBucket(estimate.latitude);
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
          for (final threshold in _thresholds) {
            final baselineRaw = math.max(jma, plum.intensity);
            final margin = plum.intensity - threshold.value;
            if (estimatedRegion != _focusRegion) continue;
            if (baselineRaw < threshold.value) continue;
            if (plum.evidenceCount < _focusMinimumEvidenceCount) continue;
            if (!plum.nearestEvidenceDistanceKm.isFinite ||
                plum.nearestEvidenceDistanceKm >=
                    _focusMaximumNearestEvidenceDistanceKm) {
              continue;
            }
            if (margin < _focusMinimumMargin) continue;

            final sample = _buildSample(
              event: event,
              targetStation: station,
              retainedStations: retained,
              threshold: threshold,
            );
            splitAccumulator.threshold(threshold.label).add(sample);
          }
        }
      }
    }
  }

  return {
    'schemaVersion': 'plum_tohoku_mismatch_gap_transition_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku mismatch gap-transition diagnostic',
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
    },
    'focusFilter': {
      'estimatedSourceRegion': _focusRegion,
      'minimumEvidenceCount': _focusMinimumEvidenceCount,
      'maximumNearestEvidenceDistanceKm':
          _focusMaximumNearestEvidenceDistanceKm,
      'minimumPredictionMarginShindo': _focusMinimumMargin,
      'baselineThresholdCrossingRequired': true,
      'neighborWindowsKm': [_localNeighbor10Km, _localNeighbor20Km],
    },
    'gapDefinitions': const {
      'actualGapBand': {
        'lt_-2.0': 'actual - threshold < -2.0',
        '-2.0_to_-1.0': '-2.0 <= actual - threshold < -1.0',
        '-1.0_to_0.0': '-1.0 <= actual - threshold < 0.0',
        '0.0_to_1.0': '0.0 <= actual - threshold < 1.0',
        'gte_1.0': 'actual - threshold >= 1.0',
      },
      'evidenceGapBand': {
        'lt_1.0': 'strongestEvidence - actual < 1.0',
        '1.0_to_2.0': '1.0 <= strongestEvidence - actual < 2.0',
        '2.0_to_3.0': '2.0 <= strongestEvidence - actual < 3.0',
        'gte_3.0': 'strongestEvidence - actual >= 3.0',
        'missing': 'no supporting evidence intensity available',
      },
    },
    'coverage': {
      'validationVariants': splitAccumulators['validation']!.variantCount,
      'testVariants': splitAccumulators['test']!.variantCount,
      'validationStationForecasts':
          splitAccumulators['validation']!.stationForecastCount,
      'testStationForecasts': splitAccumulators['test']!.stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'thresholds': {
      for (final threshold in _thresholds)
        threshold.label: _buildThresholdJson(
          validation: splitAccumulators['validation']!.threshold(threshold.label),
          test: splitAccumulators['test']!.threshold(threshold.label),
        ),
    },
    'errors': errors,
  };
}

Map<String, Object?> _buildThresholdJson({
  required _ThresholdAccumulator validation,
  required _ThresholdAccumulator test,
}) {
  final validationJson = validation.toJson();
  final testJson = test.toJson();
  return {
    'validation': validationJson,
    'test': testJson,
    'transferMatrix': _buildTransferMatrix(
      validationCells: _indexCells(validationJson['cells']),
      testCells: _indexCells(testJson['cells']),
    ),
  };
}

Map<String, Map<String, Object?>> _indexCells(Object? rawRows) => {
      for (final raw in _list(rawRows))
        '${_map(raw)['actualGapBand']}|${_map(raw)['evidenceGapBand']}': _map(raw),
    };

List<Map<String, Object?>> _buildTransferMatrix({
  required Map<String, Map<String, Object?>> validationCells,
  required Map<String, Map<String, Object?>> testCells,
}) {
  final rows = <Map<String, Object?>>[];
  for (final actualGapBand in _actualGapBands) {
    for (final evidenceGapBand in _evidenceGapBands) {
      final key = '$actualGapBand|$evidenceGapBand';
      rows.add({
        'actualGapBand': actualGapBand,
        'evidenceGapBand': evidenceGapBand,
        'validationCount': validationCells[key]?['count'] ?? 0,
        'validationShare': _number(validationCells[key]?['share']),
        'validationPrecision': _number(validationCells[key]?['precision']),
        'testCount': testCells[key]?['count'] ?? 0,
        'testShare': _number(testCells[key]?['share']),
        'testPrecision': _number(testCells[key]?['precision']),
        'shareDelta':
            _number(testCells[key]?['share']) -
            _number(validationCells[key]?['share']),
        'precisionDelta':
            _number(testCells[key]?['precision']) -
            _number(validationCells[key]?['precision']),
      });
    }
  }
  return rows;
}

_Sample _buildSample({
  required StaticIntensityEvent event,
  required StaticIntensityStation targetStation,
  required List<StaticIntensityStation> retainedStations,
  required _Threshold threshold,
}) {
  final local10 = _localNeighborSummary(
    event.stations,
    targetStation,
    threshold.value,
    _localNeighbor10Km,
  );
  final local20 = _localNeighborSummary(
    event.stations,
    targetStation,
    threshold.value,
    _localNeighbor20Km,
  );
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
  return _Sample(
    actual: targetStation.intensity,
    thresholdValue: threshold.value,
    strongestEvidenceIntensity: strongestEvidence?.station.intensity,
    localBelowThresholdShare10Km: local10.belowThresholdShare,
    localBelowThresholdShare20Km: local20.belowThresholdShare,
  );
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
    final propagated = observed.intensity -
        _plumDampingPer10Km * (distance / 10.0);
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

String plumTohokuMismatchGapTransitionDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final definitions = _map(report['gapDefinitions']);
  final thresholds = _map(report['thresholds']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Mismatch Gap-Transition Diagnostic')
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
    ..writeln('## Coverage')
    ..writeln()
    ..writeln('| Split | Variants | Station forecasts |')
    ..writeln('| --- | ---: | ---: |')
    ..writeln(
      '| validation | ${coverage['validationVariants']} | '
      '${coverage['validationStationForecasts']} |',
    )
    ..writeln(
      '| test | ${coverage['testVariants']} | '
      '${coverage['testStationForecasts']} |',
    )
    ..writeln()
    ..writeln('## Focus Filter')
    ..writeln()
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
      '- Minimum prediction margin: '
      '`${focusFilter['minimumPredictionMarginShindo']} shindo`',
    )
    ..writeln(
      '- Baseline threshold crossing required: '
      '`${focusFilter['baselineThresholdCrossingRequired']}`',
    )
    ..writeln(
      '- Neighbor windows: `${focusFilter['neighborWindowsKm']}`',
    )
    ..writeln()
    ..writeln('## Gap Definitions')
    ..writeln();

  for (final definitionKey in const ['actualGapBand', 'evidenceGapBand']) {
    final definition = _map(definitions[definitionKey]);
    buffer.writeln('- `$definitionKey`');
    for (final entry in definition.entries) {
      buffer.writeln('  - `${entry.key}`: ${entry.value}');
    }
  }
  buffer.writeln();

  for (final threshold in _thresholds) {
    final thresholdReport = _map(thresholds[threshold.label]);
    final validation = _map(thresholdReport['validation']);
    final test = _map(thresholdReport['test']);
    final transferMatrix = _list(thresholdReport['transferMatrix']);
    final validationSummary = _map(validation['summary']);
    final testSummary = _map(test['summary']);
    buffer
      ..writeln('## `${threshold.label}`')
      ..writeln()
      ..writeln('### Mismatch Summary')
      ..writeln()
      ..writeln('| Split | Mismatch Samples | Mismatch Precision |')
      ..writeln('| --- | ---: | ---: |')
      ..writeln(
        '| validation | ${validationSummary['mismatchSampleCount']} | '
        '${_pct(validationSummary['mismatchPrecision'])} |',
      )
      ..writeln(
        '| test | ${testSummary['mismatchSampleCount']} | '
        '${_pct(testSummary['mismatchPrecision'])} |',
      )
      ..writeln()
      ..writeln('### Gap Transition Matrix')
      ..writeln()
      ..writeln(
        '| Actual Gap | Evidence Gap | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |',
      )
      ..writeln(
        '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final raw in transferMatrix) {
      final row = _map(raw);
      if ((row['validationCount'] as int) == 0 && (row['testCount'] as int) == 0) {
        continue;
      }
      buffer.writeln(
        '| `${row['actualGapBand']}` | `${row['evidenceGapBand']}` | '
        '${row['validationCount']} | ${_pct(row['validationShare'])} | '
        '${_pct(row['validationPrecision'])} | ${row['testCount']} | '
        '${_pct(row['testShare'])} | ${_pct(row['testPrecision'])} | '
        '${_signedPct(_number(row['shareDelta']))} | '
        '${_signedPct(_number(row['precisionDelta']))} |',
      );
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report is diagnostic-only. It checks whether frozen test creates '
      'new mismatch gap-transition cells that validation did not cover.',
    )
    ..writeln(
      '- It does not tune PLUM, suppress predictions, or authorize production '
      'UI/wording/notification changes.',
    )
    ..writeln();
  return buffer.toString();
}

class _SplitAccumulator {
  int variantCount = 0;
  int stationForecastCount = 0;
  final thresholds = <String, _ThresholdAccumulator>{};

  _ThresholdAccumulator threshold(String label) =>
      thresholds.putIfAbsent(label, _ThresholdAccumulator.new);
}

class _ThresholdAccumulator {
  final samples = <_Sample>[];

  void add(_Sample sample) => samples.add(sample);

  Map<String, Object?> toJson() {
    final mismatchSamples = [
      for (final sample in samples)
        if (sample.localConsistencyLabel == 'mismatch') sample,
    ];
    return {
      'summary': {
        'mismatchSampleCount': mismatchSamples.length,
        'mismatchPrecision': mismatchSamples.isEmpty
            ? 0.0
            : mismatchSamples.where((sample) => sample.actualPositive).length /
                mismatchSamples.length,
      },
      'cells': [
        for (final actualGapBand in _actualGapBands)
          for (final evidenceGapBand in _evidenceGapBands)
            _cellRow(
              actualGapBand: actualGapBand,
              evidenceGapBand: evidenceGapBand,
              mismatchSamples: mismatchSamples,
            ),
      ],
    };
  }
}

Map<String, Object?> _cellRow({
  required String actualGapBand,
  required String evidenceGapBand,
  required List<_Sample> mismatchSamples,
}) {
  final bucket = [
    for (final sample in mismatchSamples)
      if (sample.actualGapBand == actualGapBand &&
          sample.evidenceGapBand == evidenceGapBand)
        sample,
  ];
  final tp = bucket.where((sample) => sample.actualPositive).length;
  return {
    'actualGapBand': actualGapBand,
    'evidenceGapBand': evidenceGapBand,
    'count': bucket.length,
    'share': mismatchSamples.isEmpty ? 0.0 : bucket.length / mismatchSamples.length,
    'precision': bucket.isEmpty ? 0.0 : tp / bucket.length,
  };
}

class _Sample {
  final double actual;
  final double thresholdValue;
  final double? strongestEvidenceIntensity;
  final double localBelowThresholdShare10Km;
  final double localBelowThresholdShare20Km;

  const _Sample({
    required this.actual,
    required this.thresholdValue,
    required this.strongestEvidenceIntensity,
    required this.localBelowThresholdShare10Km,
    required this.localBelowThresholdShare20Km,
  });

  bool get actualPositive => actual >= thresholdValue;

  String get localConsistencyLabel {
    if (localBelowThresholdShare10Km < 0.25) return 'consistent';
    if (localBelowThresholdShare10Km < 0.50) return 'mixed';
    return 'mismatch';
  }

  String get actualGapBand {
    final gap = actual - thresholdValue;
    if (gap < -2.0) return 'lt_-2.0';
    if (gap < -1.0) return '-2.0_to_-1.0';
    if (gap < 0.0) return '-1.0_to_0.0';
    if (gap < 1.0) return '0.0_to_1.0';
    return 'gte_1.0';
  }

  String get evidenceGapBand {
    final strongest = strongestEvidenceIntensity;
    if (strongest == null || !strongest.isFinite) return 'missing';
    final gap = strongest - actual;
    if (gap < 1.0) return 'lt_1.0';
    if (gap < 2.0) return '1.0_to_2.0';
    if (gap < 3.0) return '2.0_to_3.0';
    return 'gte_3.0';
  }
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

  const _NeighborSummary({required this.count, required this.belowThresholdShare});
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

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
}) => {
        'schemaVersion': 'plum_tohoku_mismatch_gap_transition_diagnostic_v1',
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'status': 'fail',
        'policy': {
          'method': 'PLUM Tohoku mismatch gap-transition diagnostic',
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
        },
        'focusFilter': {
          'estimatedSourceRegion': _focusRegion,
          'minimumEvidenceCount': _focusMinimumEvidenceCount,
          'maximumNearestEvidenceDistanceKm':
              _focusMaximumNearestEvidenceDistanceKm,
          'minimumPredictionMarginShindo': _focusMinimumMargin,
          'baselineThresholdCrossingRequired': true,
          'neighborWindowsKm': [_localNeighbor10Km, _localNeighbor20Km],
        },
        'gapDefinitions': const {
          'actualGapBand': {
            'lt_-2.0': 'actual - threshold < -2.0',
            '-2.0_to_-1.0': '-2.0 <= actual - threshold < -1.0',
            '-1.0_to_0.0': '-1.0 <= actual - threshold < 0.0',
            '0.0_to_1.0': '0.0 <= actual - threshold < 1.0',
            'gte_1.0': 'actual - threshold >= 1.0',
          },
          'evidenceGapBand': {
            'lt_1.0': 'strongestEvidence - actual < 1.0',
            '1.0_to_2.0': '1.0 <= strongestEvidence - actual < 2.0',
            '2.0_to_3.0': '2.0 <= strongestEvidence - actual < 3.0',
            'gte_3.0': 'strongestEvidence - actual >= 3.0',
            'missing': 'no supporting evidence intensity available',
          },
        },
        'coverage': {
          'validationVariants': 0,
          'testVariants': 0,
          'validationStationForecasts': 0,
          'testStationForecasts': 0,
          'skippedMissingMagnitudeEvents': 0,
          'skippedNoSourceEstimateVariants': 0,
        },
        'thresholds': const {},
        'errors': errors,
      };

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

String _eventLatitudeBucket(double latitude) {
  if (latitude >= 41) return 'hokkaido';
  if (latitude >= 37.5) return 'tohoku';
  if (latitude >= 34.5) return 'kanto_chubu';
  return 'west_south';
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _signedPct(double value) {
  final percent = value * 100;
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}pp';
}
