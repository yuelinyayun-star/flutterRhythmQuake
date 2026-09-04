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
    '.dart_tool/plum_tohoku_frozen_family_transfer_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_frozen_family_transfer_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _localNeighbor10Km = 10.0;
const _localNeighbor20Km = 20.0;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusMinimumMargin = 1.0;
const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuFrozenFamilyTransferDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuFrozenFamilyTransferDiagnosticMarkdown(report),
  );

  stdout.writeln('wrote PLUM Tohoku frozen family transfer diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuFrozenFamilyTransferDiagnosticJson({
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

            final shape = _buildShapeSample(
              event: event,
              variant: variant,
              targetStation: station,
              retainedStations: retained,
              threshold: threshold,
              plum: plum,
              jmaPredictedIntensity: jma,
            );
            splitAccumulator.threshold(threshold.label).add(shape);
          }
        }
      }
    }
  }

  return {
    'schemaVersion': 'plum_tohoku_frozen_family_transfer_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku frozen family transfer diagnostic',
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
    'familyDefinitions': const {
      'localConsistencyBand': {
        'consistent': 'median belowThresholdShare10Km < 0.25',
        'mixed': '0.25 <= median belowThresholdShare10Km < 0.50',
        'mismatch': 'median belowThresholdShare10Km >= 0.50',
      },
      'geometryBand': {
        'surrounded': 'median quadrant coverage >= 3.0',
        'one_sided': 'median quadrant coverage < 3.0',
      },
      'spreadBand': {
        'compact': 'median max spread < 20 km',
        'moderate': '20 <= median max spread < 40 km',
        'wide': 'median max spread >= 40 km',
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
          validation: splitAccumulators['validation']!.threshold(
            threshold.label,
          ),
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
  final validationFamilies = {
    for (final raw in _list(validationJson['familyAggregates']))
      _map(raw)['familyLabel'] as String: _map(raw),
  };
  final testFamilies = {
    for (final raw in _list(testJson['familyAggregates']))
      _map(raw)['familyLabel'] as String: _map(raw),
  };
  final orderedFamilies = {
    ...validationFamilies.keys,
    ...testFamilies.keys,
  }.toList()..sort();
  final transfer = [
    for (final familyLabel in orderedFamilies)
      {
        'familyLabel': familyLabel,
        'validationEventCount':
            validationFamilies[familyLabel]?['eventCount'] ?? 0,
        'validationFocusSampleCount':
            validationFamilies[familyLabel]?['focusSampleCount'] ?? 0,
        'validationTruePositiveCount':
            validationFamilies[familyLabel]?['truePositiveCount'] ?? 0,
        'validationFalsePositiveCount':
            validationFamilies[familyLabel]?['falsePositiveCount'] ?? 0,
        'validationPrecision': _number(
          validationFamilies[familyLabel]?['precision'],
        ),
        'testEventCount': testFamilies[familyLabel]?['eventCount'] ?? 0,
        'testFocusSampleCount':
            testFamilies[familyLabel]?['focusSampleCount'] ?? 0,
        'testTruePositiveCount':
            testFamilies[familyLabel]?['truePositiveCount'] ?? 0,
        'testFalsePositiveCount':
            testFamilies[familyLabel]?['falsePositiveCount'] ?? 0,
        'testPrecision': _number(testFamilies[familyLabel]?['precision']),
        'precisionDelta':
            _number(testFamilies[familyLabel]?['precision']) -
            _number(validationFamilies[familyLabel]?['precision']),
      },
  ];
  return {
    'validation': validationJson,
    'test': testJson,
    'familyTransfer': transfer,
  };
}

_ShapeSample _buildShapeSample({
  required StaticIntensityEvent event,
  required StaticIntensityVariant variant,
  required StaticIntensityStation targetStation,
  required List<StaticIntensityStation> retainedStations,
  required _Threshold threshold,
  required PlumLikeIntensityPrediction plum,
  required double jmaPredictedIntensity,
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
    if (propagated >= threshold.value) {
      supportingEvidence.add(
        _EvidenceStation(
          station: observed,
          targetDistanceKm: distance,
          propagatedIntensity: propagated,
        ),
      );
    }
  }

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
    _localNeighbor10Km,
  );
  final local20 = _localNeighborSummary(
    event.stations,
    targetStation,
    threshold.value,
    _localNeighbor20Km,
  );
  final supportShape = _supportShape(
    targetStation: targetStation,
    evidenceStations: supportingEvidence,
  );

  return _ShapeSample(
    eventId: event.eventId,
    variantId: variant.variantId,
    thresholdValue: threshold.value,
    actual: targetStation.intensity,
    plum: plum.intensity,
    jma: jmaPredictedIntensity,
    strongestEvidenceIntensity: strongestEvidence?.station.intensity,
    evidenceTargetGap: strongestEvidence == null
        ? double.nan
        : strongestEvidence.station.intensity - targetStation.intensity,
    localBelowThresholdShare10Km: local10.belowThresholdShare,
    localBelowThresholdShare20Km: local20.belowThresholdShare,
    supportingEvidenceCount: supportingEvidence.length,
    supportingEvidenceQuadrantCoverage: supportShape.quadrantCoverage,
    supportingEvidenceCentroidOffsetKm: supportShape.centroidOffsetKm,
    supportingEvidenceMeanDistanceKm: supportShape.meanDistanceKm,
    supportingEvidenceMaxSpreadKm: supportShape.maxSpreadKm,
  );
}

String plumTohokuFrozenFamilyTransferDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final familyDefinitions = _map(report['familyDefinitions']);
  final thresholds = _map(report['thresholds']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Frozen Family Transfer Diagnostic')
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
    ..writeln('- Neighbor windows: `${focusFilter['neighborWindowsKm']}`')
    ..writeln()
    ..writeln('## Family Definitions')
    ..writeln();

  for (final definitionKey in const [
    'localConsistencyBand',
    'geometryBand',
    'spreadBand',
  ]) {
    final definition = _map(familyDefinitions[definitionKey]);
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
    final validationSummary = _map(validation['summary']);
    final testSummary = _map(test['summary']);
    buffer
      ..writeln('## `${threshold.label}`')
      ..writeln()
      ..writeln('### Focus Summary')
      ..writeln()
      ..writeln('| Split | Samples | TP | FP | Precision | PLUM-only FP |')
      ..writeln('| --- | ---: | ---: | ---: | ---: | ---: |')
      ..writeln(
        '| validation | ${validationSummary['focusSampleCount']} | '
        '${validationSummary['truePositiveCount']} | '
        '${validationSummary['falsePositiveCount']} | '
        '${_pct(validationSummary['precision'])} | '
        '${validationSummary['plumOnlyFalsePositiveCount']} |',
      )
      ..writeln(
        '| test | ${testSummary['focusSampleCount']} | '
        '${testSummary['truePositiveCount']} | '
        '${testSummary['falsePositiveCount']} | '
        '${_pct(testSummary['precision'])} | '
        '${testSummary['plumOnlyFalsePositiveCount']} |',
      )
      ..writeln()
      ..writeln('### Family Transfer')
      ..writeln()
      ..writeln(
        '| Family | Val Events | Val Samples | Val TP | Val FP | Val Precision | Test Events | Test Samples | Test TP | Test FP | Test Precision | Delta |',
      )
      ..writeln(
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final raw in _list(thresholdReport['familyTransfer'])) {
      final row = _map(raw);
      buffer.writeln(
        '| `${row['familyLabel']}` | ${row['validationEventCount']} | '
        '${row['validationFocusSampleCount']} | ${row['validationTruePositiveCount']} | '
        '${row['validationFalsePositiveCount']} | ${_pct(row['validationPrecision'])} | '
        '${row['testEventCount']} | ${row['testFocusSampleCount']} | '
        '${row['testTruePositiveCount']} | ${row['testFalsePositiveCount']} | '
        '${_pct(row['testPrecision'])} | ${_signedPct(_number(row['precisionDelta']))} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Event Signatures')
      ..writeln()
      ..writeln(
        '| Split | Event | Family | Samples | TP | FP | Precision | PLUM-only FP | Below@10km | Quadrants | Max Spread | Strongest Evidence | Actual |',
      )
      ..writeln(
        '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final splitName in const ['validation', 'test']) {
      final split = splitName == 'validation' ? validation : test;
      for (final raw in _list(split['eventSignatures'])) {
        final event = _map(raw);
        buffer.writeln(
          '| $splitName | `${event['eventId']}` | `${event['familyLabel']}` | '
          '${event['focusSampleCount']} | ${event['truePositiveCount']} | '
          '${event['falsePositiveCount']} | ${_pct(event['precision'])} | '
          '${event['plumOnlyFalsePositiveCount']} | '
          '${_pct(event['medianLocalBelowThresholdShare10Km'])} | '
          '${_fmt(event['medianSupportingEvidenceQuadrantCoverage'])} | '
          '${_fmt(event['medianSupportingEvidenceMaxSpreadKm'])} | '
          '${_fmt(event['medianStrongestEvidenceIntensity'])} | '
          '${_fmt(event['medianActualIntensity'])} |',
        );
      }
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report is diagnostic-only. It freezes the validation-defined '
      'family labels and checks whether they transfer to the Tohoku frozen hotspot.',
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
  final samples = <_ShapeSample>[];

  void add(_ShapeSample sample) => samples.add(sample);

  Map<String, Object?> toJson() {
    final byEvent = <String, _EventAccumulator>{};
    for (final sample in samples) {
      byEvent.putIfAbsent(sample.eventId, _EventAccumulator.new).add(sample);
    }
    final eventSignatures =
        [
          for (final entry in byEvent.entries)
            entry.value.toJson(eventId: entry.key),
        ]..sort((left, right) {
          final bySamples = (right['focusSampleCount'] as int).compareTo(
            left['focusSampleCount'] as int,
          );
          if (bySamples != 0) return bySamples;
          return (right['falsePositiveCount'] as int).compareTo(
            left['falsePositiveCount'] as int,
          );
        });
    final familyAggregates = <String, _FamilyAccumulator>{};
    for (final raw in eventSignatures) {
      final familyLabel = raw['familyLabel'] as String;
      familyAggregates
          .putIfAbsent(familyLabel, _FamilyAccumulator.new)
          .add(raw);
    }
    final familyRows =
        [
          for (final entry in familyAggregates.entries)
            entry.value.toJson(familyLabel: entry.key),
        ]..sort((left, right) {
          final bySamples = (right['focusSampleCount'] as int).compareTo(
            left['focusSampleCount'] as int,
          );
          if (bySamples != 0) return bySamples;
          return (right['falsePositiveCount'] as int).compareTo(
            left['falsePositiveCount'] as int,
          );
        });
    final truePositiveCount = samples
        .where((sample) => sample.actualPositive)
        .length;
    final falsePositiveCount = samples.length - truePositiveCount;
    final plumOnlyFalsePositiveCount = samples
        .where((sample) => sample.plumOnlyFalsePositive)
        .length;
    return {
      'summary': {
        'focusSampleCount': samples.length,
        'truePositiveCount': truePositiveCount,
        'falsePositiveCount': falsePositiveCount,
        'precision': samples.isEmpty ? 0.0 : truePositiveCount / samples.length,
        'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
      },
      'familyAggregates': familyRows,
      'eventSignatures': eventSignatures,
    };
  }
}

class _EventAccumulator {
  final samples = <_ShapeSample>[];

  void add(_ShapeSample sample) => samples.add(sample);

  Map<String, Object?> toJson({required String eventId}) {
    final truePositiveCount = samples
        .where((sample) => sample.actualPositive)
        .length;
    final falsePositiveCount = samples.length - truePositiveCount;
    final plumOnlyFalsePositiveCount = samples
        .where((sample) => sample.plumOnlyFalsePositive)
        .length;
    final medianBelow10 = _median(
      samples.map((sample) => sample.localBelowThresholdShare10Km),
    );
    final medianQuadrants = _median(
      samples.map(
        (sample) => sample.supportingEvidenceQuadrantCoverage.toDouble(),
      ),
    );
    final medianMaxSpread = _median(
      samples.map((sample) => sample.supportingEvidenceMaxSpreadKm),
    );
    return {
      'eventId': eventId,
      'familyLabel': _familyLabel(
        medianLocalBelowThresholdShare10Km: medianBelow10,
        medianSupportingEvidenceQuadrantCoverage: medianQuadrants,
        medianSupportingEvidenceMaxSpreadKm: medianMaxSpread,
      ),
      'focusSampleCount': samples.length,
      'truePositiveCount': truePositiveCount,
      'falsePositiveCount': falsePositiveCount,
      'precision': samples.isEmpty ? 0.0 : truePositiveCount / samples.length,
      'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
      'medianStrongestEvidenceIntensity': _median(
        samples.map((sample) => sample.strongestEvidenceIntensity),
      ),
      'medianActualIntensity': _median(samples.map((sample) => sample.actual)),
      'medianLocalBelowThresholdShare10Km': medianBelow10,
      'medianSupportingEvidenceQuadrantCoverage': medianQuadrants,
      'medianSupportingEvidenceMaxSpreadKm': medianMaxSpread,
    };
  }
}

class _FamilyAccumulator {
  int eventCount = 0;
  int focusSampleCount = 0;
  int truePositiveCount = 0;
  int falsePositiveCount = 0;
  int plumOnlyFalsePositiveCount = 0;

  void add(Map<String, Object?> eventRow) {
    eventCount++;
    focusSampleCount += eventRow['focusSampleCount'] as int;
    truePositiveCount += eventRow['truePositiveCount'] as int;
    falsePositiveCount += eventRow['falsePositiveCount'] as int;
    plumOnlyFalsePositiveCount += eventRow['plumOnlyFalsePositiveCount'] as int;
  }

  Map<String, Object?> toJson({required String familyLabel}) => {
    'familyLabel': familyLabel,
    'eventCount': eventCount,
    'focusSampleCount': focusSampleCount,
    'truePositiveCount': truePositiveCount,
    'falsePositiveCount': falsePositiveCount,
    'precision': focusSampleCount == 0
        ? 0.0
        : truePositiveCount / focusSampleCount,
    'plumOnlyFalsePositiveCount': plumOnlyFalsePositiveCount,
  };
}

class _ShapeSample {
  final String eventId;
  final String variantId;
  final double thresholdValue;
  final double actual;
  final double plum;
  final double jma;
  final double? strongestEvidenceIntensity;
  final double evidenceTargetGap;
  final double localBelowThresholdShare10Km;
  final double localBelowThresholdShare20Km;
  final int supportingEvidenceCount;
  final int supportingEvidenceQuadrantCoverage;
  final double supportingEvidenceCentroidOffsetKm;
  final double supportingEvidenceMeanDistanceKm;
  final double supportingEvidenceMaxSpreadKm;

  const _ShapeSample({
    required this.eventId,
    required this.variantId,
    required this.thresholdValue,
    required this.actual,
    required this.plum,
    required this.jma,
    required this.strongestEvidenceIntensity,
    required this.evidenceTargetGap,
    required this.localBelowThresholdShare10Km,
    required this.localBelowThresholdShare20Km,
    required this.supportingEvidenceCount,
    required this.supportingEvidenceQuadrantCoverage,
    required this.supportingEvidenceCentroidOffsetKm,
    required this.supportingEvidenceMeanDistanceKm,
    required this.supportingEvidenceMaxSpreadKm,
  });

  bool get actualPositive => actual >= thresholdValue;

  bool get plumOnlyFalsePositive =>
      !actualPositive && plum >= thresholdValue && jma < thresholdValue;
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

String _familyLabel({
  required double medianLocalBelowThresholdShare10Km,
  required double medianSupportingEvidenceQuadrantCoverage,
  required double medianSupportingEvidenceMaxSpreadKm,
}) {
  final localConsistency = medianLocalBelowThresholdShare10Km < 0.25
      ? 'consistent'
      : medianLocalBelowThresholdShare10Km < 0.50
      ? 'mixed'
      : 'mismatch';
  final geometry = medianSupportingEvidenceQuadrantCoverage >= 3.0
      ? 'surrounded'
      : 'one_sided';
  final spread = medianSupportingEvidenceMaxSpreadKm < 20.0
      ? 'compact'
      : medianSupportingEvidenceMaxSpreadKm < 40.0
      ? 'moderate'
      : 'wide';
  return '$localConsistency/$geometry/$spread';
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
  'schemaVersion': 'plum_tohoku_frozen_family_transfer_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method': 'PLUM Tohoku frozen family transfer diagnostic',
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
    'maximumNearestEvidenceDistanceKm': _focusMaximumNearestEvidenceDistanceKm,
    'minimumPredictionMarginShindo': _focusMinimumMargin,
    'baselineThresholdCrossingRequired': true,
    'neighborWindowsKm': [_localNeighbor10Km, _localNeighbor20Km],
  },
  'familyDefinitions': const {
    'localConsistencyBand': {
      'consistent': 'median belowThresholdShare10Km < 0.25',
      'mixed': '0.25 <= median belowThresholdShare10Km < 0.50',
      'mismatch': 'median belowThresholdShare10Km >= 0.50',
    },
    'geometryBand': {
      'surrounded': 'median quadrant coverage >= 3.0',
      'one_sided': 'median quadrant coverage < 3.0',
    },
    'spreadBand': {
      'compact': 'median max spread < 20 km',
      'moderate': '20 <= median max spread < 40 km',
      'wide': 'median max spread >= 40 km',
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

double _median(Iterable<double?> values) {
  final filtered = [
    for (final value in values)
      if (value != null && value.isFinite) value,
  ]..sort();
  if (filtered.isEmpty) return 0.0;
  final middle = filtered.length ~/ 2;
  if (filtered.length.isOdd) return filtered[middle];
  return (filtered[middle - 1] + filtered[middle]) / 2.0;
}

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _signedPct(double value) {
  final percent = value * 100;
  final sign = percent >= 0 ? '+' : '';
  return '$sign${percent.toStringAsFixed(1)}pp';
}

String _fmt(Object? value) {
  final number = _number(value);
  if (!number.isFinite) return '0.00';
  return number.toStringAsFixed(2);
}
