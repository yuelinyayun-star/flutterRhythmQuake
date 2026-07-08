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
    '.dart_tool/plum_tohoku_mismatch_mass_shift_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_mismatch_mass_shift_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _localNeighbor10Km = 10.0;
const _localNeighbor20Km = 20.0;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusMinimumMargin = 1.0;
const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];
const _localConsistencyLabels = ['consistent', 'mixed', 'mismatch'];
const _geometrySpreadLabels = [
  'one_sided/compact',
  'one_sided/moderate',
  'one_sided/wide',
  'surrounded/compact',
  'surrounded/moderate',
  'surrounded/wide',
];
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

  final report = buildPlumTohokuMismatchMassShiftDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuMismatchMassShiftDiagnosticMarkdown(report),
  );

  stdout.writeln('wrote PLUM Tohoku mismatch mass-shift diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuMismatchMassShiftDiagnosticJson({
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
    'schemaVersion': 'plum_tohoku_mismatch_mass_shift_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku mismatch regime mass-shift diagnostic',
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
    'decompositionDefinitions': const {
      'localConsistencyBand': {
        'consistent': 'belowThresholdShare10Km < 0.25',
        'mixed': '0.25 <= belowThresholdShare10Km < 0.50',
        'mismatch': 'belowThresholdShare10Km >= 0.50',
      },
      'geometrySpread': {
        'one_sided/compact': 'quadrants < 3 and maxSpread < 20 km',
        'one_sided/moderate': 'quadrants < 3 and 20 <= maxSpread < 40 km',
        'one_sided/wide': 'quadrants < 3 and maxSpread >= 40 km',
        'surrounded/compact': 'quadrants >= 3 and maxSpread < 20 km',
        'surrounded/moderate': 'quadrants >= 3 and 20 <= maxSpread < 40 km',
        'surrounded/wide': 'quadrants >= 3 and maxSpread >= 40 km',
      },
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
    'transfers': {
      'localConsistency': _buildTransferRows(
        labels: _localConsistencyLabels,
        validationRows: _indexRows(validationJson['localConsistency']),
        testRows: _indexRows(testJson['localConsistency']),
        labelKey: 'label',
      ),
      'mismatchGeometrySpread': _buildTransferRows(
        labels: _geometrySpreadLabels,
        validationRows: _indexRows(validationJson['mismatchGeometrySpread']),
        testRows: _indexRows(testJson['mismatchGeometrySpread']),
        labelKey: 'label',
      ),
      'mismatchActualGapBand': _buildTransferRows(
        labels: _actualGapBands,
        validationRows: _indexRows(validationJson['mismatchActualGapBand']),
        testRows: _indexRows(testJson['mismatchActualGapBand']),
        labelKey: 'label',
      ),
      'mismatchEvidenceGapBand': _buildTransferRows(
        labels: _evidenceGapBands,
        validationRows: _indexRows(validationJson['mismatchEvidenceGapBand']),
        testRows: _indexRows(testJson['mismatchEvidenceGapBand']),
        labelKey: 'label',
      ),
    },
  };
}

Map<String, Map<String, Object?>> _indexRows(Object? rawRows) => {
      for (final raw in _list(rawRows))
        _map(raw)['label'] as String: _map(raw),
    };

List<Map<String, Object?>> _buildTransferRows({
  required List<String> labels,
  required Map<String, Map<String, Object?>> validationRows,
  required Map<String, Map<String, Object?>> testRows,
  required String labelKey,
}) {
  return [
    for (final label in labels)
      {
        'label': label,
        'validationCount': validationRows[label]?['count'] ?? 0,
        'validationShare': _number(validationRows[label]?['share']),
        'validationPrecision': _number(validationRows[label]?['precision']),
        'testCount': testRows[label]?['count'] ?? 0,
        'testShare': _number(testRows[label]?['share']),
        'testPrecision': _number(testRows[label]?['precision']),
        'shareDelta':
            _number(testRows[label]?['share']) -
            _number(validationRows[label]?['share']),
        'precisionDelta':
            _number(testRows[label]?['precision']) -
            _number(validationRows[label]?['precision']),
      },
  ];
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
  final supportShape = _supportShape(
    targetStation: targetStation,
    evidenceStations: supportingEvidence,
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
    supportingEvidenceQuadrantCoverage: supportShape.quadrantCoverage,
    supportingEvidenceMaxSpreadKm: supportShape.maxSpreadKm,
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

String plumTohokuMismatchMassShiftDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final definitions = _map(report['decompositionDefinitions']);
  final thresholds = _map(report['thresholds']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Mismatch Regime Mass-Shift Diagnostic')
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
    ..writeln('## Definitions')
    ..writeln();

  for (final definitionKey in const [
    'localConsistencyBand',
    'geometrySpread',
    'actualGapBand',
    'evidenceGapBand',
  ]) {
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
    final transfers = _map(thresholdReport['transfers']);
    final validationSummary = _map(validation['summary']);
    final testSummary = _map(test['summary']);
    buffer
      ..writeln('## `${threshold.label}`')
      ..writeln()
      ..writeln('### Focus Summary')
      ..writeln()
      ..writeln('| Split | Samples | TP | FP | Precision | Mismatch Share |')
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |')
      ..writeln(
        '| validation | ${validationSummary['focusSampleCount']} | '
        '${validationSummary['truePositiveCount']} | '
        '${validationSummary['falsePositiveCount']} | '
        '${_pct(validationSummary['precision'])} | '
        '${_pct(validationSummary['mismatchShare'])} |',
      )
      ..writeln(
        '| test | ${testSummary['focusSampleCount']} | '
        '${testSummary['truePositiveCount']} | '
        '${testSummary['falsePositiveCount']} | '
        '${_pct(testSummary['precision'])} | '
        '${_pct(testSummary['mismatchShare'])} |',
      );

    _writeTransferSection(
      buffer: buffer,
      title: '### Local-Consistency Mass Shift',
      rows: _list(transfers['localConsistency']),
    );
    _writeTransferSection(
      buffer: buffer,
      title: '### Mismatch Geometry/Spread Mass Shift',
      rows: _list(transfers['mismatchGeometrySpread']),
    );
    _writeTransferSection(
      buffer: buffer,
      title: '### Mismatch Actual-Gap Mass Shift',
      rows: _list(transfers['mismatchActualGapBand']),
    );
    _writeTransferSection(
      buffer: buffer,
      title: '### Mismatch Evidence-Gap Mass Shift',
      rows: _list(transfers['mismatchEvidenceGapBand']),
    );
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report is diagnostic-only. It decomposes why frozen test shifts '
      'so much focus mass into already-weak mismatch regimes.',
    )
    ..writeln(
      '- It does not tune PLUM, suppress predictions, or authorize production '
      'UI/wording/notification changes.',
    )
    ..writeln();
  return buffer.toString();
}

void _writeTransferSection({
  required StringBuffer buffer,
  required String title,
  required List<Object?> rows,
}) {
  buffer
    ..writeln()
    ..writeln(title)
    ..writeln()
    ..writeln(
      '| Bucket | Val Count | Val Share | Val Precision | Test Count | Test Share | Test Precision | Share Delta | Precision Delta |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final raw in rows) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['label']}` | ${row['validationCount']} | '
      '${_pct(row['validationShare'])} | ${_pct(row['validationPrecision'])} | '
      '${row['testCount']} | ${_pct(row['testShare'])} | '
      '${_pct(row['testPrecision'])} | ${_signedPct(_number(row['shareDelta']))} | '
      '${_signedPct(_number(row['precisionDelta']))} |',
    );
  }
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
    final truePositiveCount = samples.where((sample) => sample.actualPositive).length;
    final falsePositiveCount = samples.length - truePositiveCount;
    final mismatchSamples = [
      for (final sample in samples)
        if (sample.localConsistencyLabel == 'mismatch') sample,
    ];
    return {
      'summary': {
        'focusSampleCount': samples.length,
        'truePositiveCount': truePositiveCount,
        'falsePositiveCount': falsePositiveCount,
        'precision': samples.isEmpty ? 0.0 : truePositiveCount / samples.length,
        'mismatchShare': samples.isEmpty ? 0.0 : mismatchSamples.length / samples.length,
      },
      'localConsistency': _bucketRows(
        labels: _localConsistencyLabels,
        samples: samples,
        labelOf: (sample) => sample.localConsistencyLabel,
        denominator: samples.length,
      ),
      'mismatchGeometrySpread': _bucketRows(
        labels: _geometrySpreadLabels,
        samples: mismatchSamples,
        labelOf: (sample) => sample.geometrySpreadLabel,
        denominator: mismatchSamples.length,
      ),
      'mismatchActualGapBand': _bucketRows(
        labels: _actualGapBands,
        samples: mismatchSamples,
        labelOf: (sample) => sample.actualGapBand,
        denominator: mismatchSamples.length,
      ),
      'mismatchEvidenceGapBand': _bucketRows(
        labels: _evidenceGapBands,
        samples: mismatchSamples,
        labelOf: (sample) => sample.evidenceGapBand,
        denominator: mismatchSamples.length,
      ),
    };
  }
}

List<Map<String, Object?>> _bucketRows({
  required List<String> labels,
  required List<_Sample> samples,
  required String Function(_Sample) labelOf,
  required int denominator,
}) {
  return [
    for (final label in labels) _bucketRow(label, samples, labelOf, denominator),
  ];
}

Map<String, Object?> _bucketRow(
  String label,
  List<_Sample> samples,
  String Function(_Sample) labelOf,
  int denominator,
) {
  final bucket = [
    for (final sample in samples)
      if (labelOf(sample) == label) sample,
  ];
  final truePositiveCount = bucket.where((sample) => sample.actualPositive).length;
  final falsePositiveCount = bucket.length - truePositiveCount;
  return {
    'label': label,
    'count': bucket.length,
    'share': denominator == 0 ? 0.0 : bucket.length / denominator,
    'truePositiveCount': truePositiveCount,
    'falsePositiveCount': falsePositiveCount,
    'precision': bucket.isEmpty ? 0.0 : truePositiveCount / bucket.length,
  };
}

class _Sample {
  final double actual;
  final double thresholdValue;
  final double? strongestEvidenceIntensity;
  final double localBelowThresholdShare10Km;
  final double localBelowThresholdShare20Km;
  final int supportingEvidenceQuadrantCoverage;
  final double supportingEvidenceMaxSpreadKm;

  const _Sample({
    required this.actual,
    required this.thresholdValue,
    required this.strongestEvidenceIntensity,
    required this.localBelowThresholdShare10Km,
    required this.localBelowThresholdShare20Km,
    required this.supportingEvidenceQuadrantCoverage,
    required this.supportingEvidenceMaxSpreadKm,
  });

  bool get actualPositive => actual >= thresholdValue;

  String get localConsistencyLabel {
    if (localBelowThresholdShare10Km < 0.25) return 'consistent';
    if (localBelowThresholdShare10Km < 0.50) return 'mixed';
    return 'mismatch';
  }

  String get geometrySpreadLabel {
    final geometry =
        supportingEvidenceQuadrantCoverage >= 3 ? 'surrounded' : 'one_sided';
    final spread = supportingEvidenceMaxSpreadKm < 20.0
        ? 'compact'
        : supportingEvidenceMaxSpreadKm < 40.0
            ? 'moderate'
            : 'wide';
    return '$geometry/$spread';
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

class _SupportShape {
  final int quadrantCoverage;
  final double centroidOffsetKm;
  final double meanDistanceKm;
  final double maxSpreadKm;

  const _SupportShape({
    required this.quadrantCoverage,
    required this.centroidOffsetKm,
    required this.meanDistanceKm,
    required this.maxSpreadKm,
  });
}

_SupportShape _supportShape({
  required StaticIntensityStation targetStation,
  required List<_EvidenceStation> evidenceStations,
}) {
  if (evidenceStations.isEmpty) {
    return const _SupportShape(
      quadrantCoverage: 0,
      centroidOffsetKm: 0.0,
      meanDistanceKm: 0.0,
      maxSpreadKm: 0.0,
    );
  }
  final quadrants = <int>{};
  var latSum = 0.0;
  var lngSum = 0.0;
  var distanceSum = 0.0;
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
    latSum += evidence.station.latitude;
    lngSum += evidence.station.longitude;
    distanceSum += evidence.targetDistanceKm;
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
  final centroidLat = latSum / evidenceStations.length;
  final centroidLng = lngSum / evidenceStations.length;
  return _SupportShape(
    quadrantCoverage: quadrants.length,
    centroidOffsetKm: QuakeCalculator.haversineDistance(
      targetStation.latitude,
      targetStation.longitude,
      centroidLat,
      centroidLng,
    ),
    meanDistanceKm: distanceSum / evidenceStations.length,
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
        'schemaVersion': 'plum_tohoku_mismatch_mass_shift_diagnostic_v1',
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
        'status': 'fail',
        'policy': {
          'method': 'PLUM Tohoku mismatch regime mass-shift diagnostic',
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
        'decompositionDefinitions': const {
          'localConsistencyBand': {
            'consistent': 'belowThresholdShare10Km < 0.25',
            'mixed': '0.25 <= belowThresholdShare10Km < 0.50',
            'mismatch': 'belowThresholdShare10Km >= 0.50',
          },
          'geometrySpread': {
            'one_sided/compact': 'quadrants < 3 and maxSpread < 20 km',
            'one_sided/moderate': 'quadrants < 3 and 20 <= maxSpread < 40 km',
            'one_sided/wide': 'quadrants < 3 and maxSpread >= 40 km',
            'surrounded/compact': 'quadrants >= 3 and maxSpread < 20 km',
            'surrounded/moderate': 'quadrants >= 3 and 20 <= maxSpread < 40 km',
            'surrounded/wide': 'quadrants >= 3 and maxSpread >= 40 km',
          },
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
