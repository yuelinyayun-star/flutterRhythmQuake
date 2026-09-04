import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_tohoku_focus_region_site_frozen_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_tohoku_focus_region_site_frozen_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _highBandMinPrecision = 0.75;
const _mediumBandMinPrecision = 0.55;
const _minSampleForBandAssignment = 20;
const _focusRegion = 'tohoku';
const _focusMinimumEvidenceCount = 8;
const _focusMaximumNearestEvidenceDistanceKm = 10.0;
const _focusMinimumMargin = 1.0;
const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];
const _siteBands = ['hokkaido', 'tohoku', 'kanto_chubu', 'west_south'];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumTohokuFocusRegionSiteFrozenDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    plumTohokuFocusRegionSiteFrozenDiagnosticMarkdown(report),
  );

  stdout.writeln(
    'wrote PLUM Tohoku focus region/site frozen diagnostic report',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumTohokuFocusRegionSiteFrozenDiagnosticJson({
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
  final plum = const PlumLikeIntensityPredictor(
    radiusKm: 30,
    dampingPer10Km: 0.50,
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
        final region = _latitudeBand(estimate.latitude);
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
          final plumPrediction = plum.predict(
            targetStation: station,
            observedStations: retained,
          );
          for (final threshold in _thresholds) {
            final baselineRaw = math.max(jma, plumPrediction.intensity);
            final margin = plumPrediction.intensity - threshold.value;
            if (baselineRaw < threshold.value) continue;
            if (region != _focusRegion) continue;
            if (plumPrediction.evidenceCount < _focusMinimumEvidenceCount) {
              continue;
            }
            if (!plumPrediction.nearestEvidenceDistanceKm.isFinite ||
                plumPrediction.nearestEvidenceDistanceKm >=
                    _focusMaximumNearestEvidenceDistanceKm) {
              continue;
            }
            if (margin < _focusMinimumMargin) continue;

            splitAccumulator
                .threshold(threshold.label)
                .add(
                  _RegionSiteSample(
                    actual: station.intensity,
                    baselineRaw: baselineRaw,
                    region: region,
                    site: _latitudeBand(station.latitude),
                  ),
                  threshold.value,
                );
          }
        }
      }
    }
  }

  final thresholds = <String, Object?>{};
  for (final threshold in _thresholds) {
    final validation = splitAccumulators['validation']!.threshold(
      threshold.label,
    );
    final test = splitAccumulators['test']!.threshold(threshold.label);
    final validationBands = validation.validationBandByJointKey();
    thresholds[threshold.label] = {
      'validation': validation.toJson(
        bandByJointKey: validationBands,
        includeTransfer: false,
      ),
      'test': test.toJson(
        bandByJointKey: validationBands,
        includeTransfer: true,
      ),
    };
  }

  return {
    'schemaVersion': 'plum_tohoku_focus_region_site_frozen_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM Tohoku focus region/site frozen diagnostic',
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'suppressionApplied': false,
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
      'validationBandThresholds': {
        'high': _highBandMinPrecision,
        'medium': _mediumBandMinPrecision,
        'minSampleForBandAssignment': _minSampleForBandAssignment,
      },
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
    },
    'bucketDefinitions': const {
      'regionBands': ['hokkaido', 'tohoku', 'kanto_chubu', 'west_south'],
      'siteBands': ['hokkaido', 'tohoku', 'kanto_chubu', 'west_south'],
      'regionSource': 'estimated_source_latitude',
      'siteSource': 'station_latitude',
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
    'thresholds': thresholds,
    'errors': errors,
  };
}

String plumTohokuFocusRegionSiteFrozenDiagnosticMarkdown(
  Map<String, Object?> report,
) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final focusFilter = _map(report['focusFilter']);
  final thresholds = _map(report['thresholds']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Tohoku Focus Region/Site Frozen Diagnostic')
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
      '- Minimum PLUM prediction margin: '
      '`${focusFilter['minimumPredictionMarginShindo']} shindo`',
    )
    ..writeln(
      '- Baseline threshold crossing required: '
      '`${focusFilter['baselineThresholdCrossingRequired']}`',
    )
    ..writeln();

  for (final threshold in _thresholds) {
    final row = _map(thresholds[threshold.label]);
    final validation = _map(row['validation']);
    final test = _map(row['test']);
    final validationBaseline = _map(validation['baseline']);
    final testBaseline = _map(test['baseline']);
    buffer
      ..writeln('## `${threshold.label}`')
      ..writeln()
      ..writeln('### Focus Baseline')
      ..writeln()
      ..writeln('| Split | Focus samples | TP | FP | Precision |')
      ..writeln('| --- | ---: | ---: | ---: | ---: |')
      ..writeln(
        '| validation | ${validation['focusSampleCount']} | '
        '${validationBaseline['truePositive']} | ${validationBaseline['falsePositive']} | '
        '${_pct(validationBaseline['precision'])} |',
      )
      ..writeln(
        '| test | ${test['focusSampleCount']} | '
        '${testBaseline['truePositive']} | ${testBaseline['falsePositive']} | '
        '${_pct(testBaseline['precision'])} |',
      )
      ..writeln()
      ..writeln('### Marginal Site Precision')
      ..writeln()
      ..writeln('| Site | Validation P+/P | Test P+/P | Delta |')
      ..writeln('| --- | ---: | ---: | ---: |');
    final validationSites = {
      for (final raw in _list(validation['marginalSite']))
        _map(raw)['site'] as String: _map(raw),
    };
    final testSites = {
      for (final raw in _list(test['marginalSite']))
        _map(raw)['site'] as String: _map(raw),
    };
    for (final site in _siteBands) {
      final left = validationSites[site] ?? const {};
      final right = testSites[site] ?? const {};
      buffer.writeln(
        '| `$site` | ${left['predictedPositive'] ?? 0} / ${_pct(left['precision'])} | '
        '${right['predictedPositive'] ?? 0} / ${_pct(right['precision'])} | '
        '${_signedPct(_number(right['precision']) - _number(left['precision']))} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Joint Buckets')
      ..writeln()
      ..writeln(
        '| Region | Site | Validation P+/P | Validation Band | Test P+/P | Delta |',
      )
      ..writeln('| --- | --- | ---: | --- | ---: | ---: |');
    final validationBuckets = {
      for (final rawBucket in _list(validation['jointBuckets']))
        '${_map(rawBucket)['region']}|${_map(rawBucket)['site']}': _map(
          rawBucket,
        ),
    };
    final testBuckets = {
      for (final rawBucket in _list(test['jointBuckets']))
        '${_map(rawBucket)['region']}|${_map(rawBucket)['site']}': _map(
          rawBucket,
        ),
    };
    final orderedKeys = validationBuckets.keys.toList()..sort();
    for (final key in orderedKeys) {
      final left = validationBuckets[key]!;
      final right = testBuckets[key] ?? const {};
      buffer.writeln(
        '| `${left['region']}` | `${left['site']}` | '
        '${left['predictedPositive']} / ${_pct(left['precision'])} | '
        '`${left['band']}` | '
        '${right['predictedPositive'] ?? 0} / ${_pct(right['precision'])} | '
        '${_signedPct(_number(right['precision']) - _number(left['precision']))} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Band Transfer')
      ..writeln()
      ..writeln(
        '| Band | Validation Buckets | Validation P+/P | Test P+/P | Delta |',
      )
      ..writeln('| --- | ---: | ---: | ---: | ---: |');
    final validationBands = _map(validation['bandSummary']);
    final testBands = _map(test['bandTransferSummary']);
    for (final band in const ['high', 'medium', 'low', 'insufficient']) {
      final left = _map(validationBands[band]);
      final right = _map(testBands[band]);
      buffer.writeln(
        '| `$band` | ${left['bucketCount'] ?? 0} | '
        '${left['predictedPositive'] ?? 0} / ${_pct(left['precision'])} | '
        '${right['predictedPositive'] ?? 0} / ${_pct(right['precision'])} | '
        '${_signedPct(_number(right['precision']) - _number(left['precision']))} |',
      );
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Diagnostic-only. This report checks whether the existing geographic '
      'region/site view transfers inside the `tohoku` hotspot before adding '
      'new production-facing calibration logic.',
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
  int focusSampleCount = 0;
  final baseline = _PredictedBucket();
  final jointBuckets = <String, _RegionSiteBucket>{};
  final marginalSite = <String, _PredictedBucket>{};

  void add(_RegionSiteSample sample, double threshold) {
    focusSampleCount++;
    final actualPositive = sample.actual >= threshold;
    baseline.add(actualPositive: actualPositive);
    final jointKey = '${sample.region}|${sample.site}';
    jointBuckets
        .putIfAbsent(jointKey, _RegionSiteBucket.new)
        .add(
          region: sample.region,
          site: sample.site,
          actualPositive: actualPositive,
        );
    marginalSite
        .putIfAbsent(sample.site, _PredictedBucket.new)
        .add(actualPositive: actualPositive);
  }

  Map<String, String> validationBandByJointKey() => {
    for (final entry in jointBuckets.entries) entry.key: _bandFor(entry.value),
  };

  Map<String, Object?> toJson({
    required Map<String, String> bandByJointKey,
    required bool includeTransfer,
  }) {
    final ordered = jointBuckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final bandSummary = {
      'high': _BandAccumulator(),
      'medium': _BandAccumulator(),
      'low': _BandAccumulator(),
      'insufficient': _BandAccumulator(),
    };
    final bandTransferSummary = {
      'high': _BandAccumulator(),
      'medium': _BandAccumulator(),
      'low': _BandAccumulator(),
      'insufficient': _BandAccumulator(),
    };
    final jointJson = <Map<String, Object?>>[];
    for (final entry in ordered) {
      final bucket = entry.value;
      final localBand = _bandFor(bucket);
      bandSummary[localBand]!.addBucket(bucket);
      final projectedBand = bandByJointKey[entry.key] ?? 'unseen';
      if (includeTransfer && bandTransferSummary.containsKey(projectedBand)) {
        bandTransferSummary[projectedBand]!.addBucket(bucket);
      }
      jointJson.add({
        'region': bucket.region,
        'site': bucket.site,
        'predictedPositive': bucket.predictedPositive,
        'truePositive': bucket.truePositive,
        'falsePositive': bucket.falsePositive,
        'precision': bucket.precision,
        'band': includeTransfer ? projectedBand : localBand,
        'localBand': localBand,
      });
    }
    return {
      'focusSampleCount': focusSampleCount,
      'baseline': baseline.toJson(),
      'marginalSite': [
        for (final site in _siteBands)
          {'site': site, ...?marginalSite[site]?.toJson()},
      ],
      'jointBuckets': jointJson,
      'bandSummary': {
        for (final entry in bandSummary.entries)
          entry.key: entry.value.toJson(),
      },
      if (includeTransfer)
        'bandTransferSummary': {
          for (final entry in bandTransferSummary.entries)
            entry.key: entry.value.toJson(),
        },
    };
  }

  String _bandFor(_RegionSiteBucket bucket) {
    if (bucket.predictedPositive < _minSampleForBandAssignment) {
      return 'insufficient';
    }
    if (bucket.precision >= _highBandMinPrecision) return 'high';
    if (bucket.precision >= _mediumBandMinPrecision) return 'medium';
    return 'low';
  }
}

class _RegionSiteSample {
  final double actual;
  final double baselineRaw;
  final String region;
  final String site;

  const _RegionSiteSample({
    required this.actual,
    required this.baselineRaw,
    required this.region,
    required this.site,
  });
}

class _RegionSiteBucket {
  String region = '';
  String site = '';
  int predictedPositive = 0;
  int truePositive = 0;
  int falsePositive = 0;

  void add({
    required String region,
    required String site,
    required bool actualPositive,
  }) {
    this.region = region;
    this.site = site;
    predictedPositive++;
    if (actualPositive) {
      truePositive++;
    } else {
      falsePositive++;
    }
  }

  double get precision =>
      predictedPositive == 0 ? 0.0 : truePositive / predictedPositive;
}

class _PredictedBucket {
  int predictedPositive = 0;
  int truePositive = 0;
  int falsePositive = 0;

  void add({required bool actualPositive}) {
    predictedPositive++;
    if (actualPositive) {
      truePositive++;
    } else {
      falsePositive++;
    }
  }

  double get precision =>
      predictedPositive == 0 ? 0.0 : truePositive / predictedPositive;

  Map<String, Object?> toJson() => {
    'predictedPositive': predictedPositive,
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'precision': precision,
  };
}

class _BandAccumulator {
  int bucketCount = 0;
  int predictedPositive = 0;
  int truePositive = 0;
  int falsePositive = 0;

  void addBucket(_RegionSiteBucket bucket) {
    bucketCount++;
    predictedPositive += bucket.predictedPositive;
    truePositive += bucket.truePositive;
    falsePositive += bucket.falsePositive;
  }

  double get precision =>
      predictedPositive == 0 ? 0.0 : truePositive / predictedPositive;

  Map<String, Object?> toJson() => {
    'bucketCount': bucketCount,
    'predictedPositive': predictedPositive,
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'precision': precision,
  };
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
  'schemaVersion': 'plum_tohoku_focus_region_site_frozen_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method': 'PLUM Tohoku focus region/site frozen diagnostic',
    'rawPredictedIntensityMutated': false,
    'frozenTestEvaluated': true,
    'productionReady': false,
    'productionUiConnected': false,
    'diagnosticOnly': true,
    'parametersTuned': false,
    'suppressionApplied': false,
    'plumRadiusKm': _plumRadiusKm,
    'plumDampingPer10Km': _plumDampingPer10Km,
    'validationBandThresholds': {
      'high': _highBandMinPrecision,
      'medium': _mediumBandMinPrecision,
      'minSampleForBandAssignment': _minSampleForBandAssignment,
    },
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
  },
  'bucketDefinitions': const {
    'regionBands': ['hokkaido', 'tohoku', 'kanto_chubu', 'west_south'],
    'siteBands': ['hokkaido', 'tohoku', 'kanto_chubu', 'west_south'],
    'regionSource': 'estimated_source_latitude',
    'siteSource': 'station_latitude',
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

String _latitudeBand(double latitude) {
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
