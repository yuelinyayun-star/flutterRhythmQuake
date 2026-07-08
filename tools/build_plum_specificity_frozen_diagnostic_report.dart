import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/replay/jma_intensity_dataset.dart';
import 'package:flutterrhythmquake/core/replay/synthetic_reveal_dataset.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDataDirectory = 'tmp/jma_intensity_pretraining';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_specificity_frozen_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_specificity_frozen_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];
const _regions = ['hokkaido', 'tohoku', 'kanto_chubu', 'west_south'];
const _distances = [
  '000_030km',
  '030_060km',
  '060_100km',
  '100_200km',
  'gt_200km',
];
const _maskRates = ['20pct', '50pct', '80pct'];
const _evidenceCounts = ['0', '1', '2_3', '4_7', 'gte_8'];
const _nearestEvidenceDistances = [
  'no_evidence',
  '000_010km',
  '010_020km',
  '020_030km',
];
const _strongestEvidenceIntensities = [
  'no_evidence',
  'lt_1_5',
  '1_5_2_5',
  '2_5_3_5',
  'gte_3_5',
];
const _predictionMargins = [
  'negative',
  '000_025',
  '025_050',
  '050_100',
  'gte_100',
];

void main(List<String> args) {
  final dataDirectory =
      _argument(args, '--data-directory') ?? _defaultDataDirectory;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumSpecificityFrozenDiagnosticJson(
    dataDirectory: dataDirectory,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumSpecificityFrozenDiagnosticMarkdown(report));

  stdout.writeln('wrote PLUM specificity frozen diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumSpecificityFrozenDiagnosticJson({
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
  final acc = _ReportAccumulator();
  var skippedMissingMagnitude = 0;
  var skippedNoEstimate = 0;

  for (final splitName in const ['validation', 'test']) {
    final dataset = synthetic.datasetsBySplit[splitName]!;
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
        final splitAcc = acc.split(splitName);
        splitAcc.variantCount++;
        final region = _eventLatitudeBucket(estimate.latitude);
        final maskRate = _maskRateBucket(variant.maskRate);

        for (final station in event.stations) {
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
          final strongestEvidenceIntensity =
              plum.strongestEvidenceStationId == null
              ? null
              : stationsById[plum.strongestEvidenceStationId]?.intensity;
          final distance = QuakeCalculator.haversineDistance(
            estimate.latitude,
            estimate.longitude,
            station.latitude,
            station.longitude,
          );
          final sample = _PlumSpecificitySample(
            actual: station.intensity,
            plum: plum.intensity,
            jma: jma,
            region: region,
            distanceBucket: _distanceBucket(distance),
            maskRateBucket: maskRate,
            evidenceCountBucket: _evidenceCountBucket(plum.evidenceCount),
            nearestEvidenceDistanceBucket: _nearestEvidenceDistanceBucket(
              plum.nearestEvidenceDistanceKm,
            ),
            strongestEvidenceIntensityBucket: _strongestEvidenceIntensityBucket(
              strongestEvidenceIntensity,
            ),
          );
          splitAcc.stationForecastCount++;
          for (final threshold in _thresholds) {
            splitAcc.threshold(threshold.label).add(sample, threshold.value);
          }
        }
      }
    }
  }

  if (acc.validation.stationForecastCount == 0 &&
      acc.test.stationForecastCount == 0) {
    errors.add('no_plum_specificity_station_forecasts');
  }

  return _assembleReport(
    errors: errors,
    dataDirectory: dataDirectory,
    modelPath: modelPath,
    skippedMissingMagnitude: skippedMissingMagnitude,
    skippedNoEstimate: skippedNoEstimate,
    acc: acc,
  );
}

Map<String, Object?> _assembleReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
  required int skippedMissingMagnitude,
  required int skippedNoEstimate,
  required _ReportAccumulator acc,
}) {
  final thresholds = <String, Object?>{};
  for (final threshold in _thresholds) {
    final validation = acc.validation.threshold(threshold.label);
    final test = acc.test.threshold(threshold.label);
    thresholds[threshold.label] = {
      'splits': {'validation': validation.toJson(), 'test': test.toJson()},
      'precisionDelta': test.overall.precision - validation.overall.precision,
      'specificityDelta':
          test.overall.specificity - validation.overall.specificity,
      'falsePositiveDelta':
          test.overall.falsePositive - validation.overall.falsePositive,
    };
  }
  return {
    'schemaVersion': 'plum_specificity_frozen_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': {
      'method': 'PLUM r30/d0.50 frozen specificity diagnostic',
      'rawPredictedIntensityMutated': false,
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
      'parametersTuned': false,
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
    },
    'inputs': {
      'dataDirectory': dataDirectory,
      'modelPath': modelPath,
      'splits': ['validation', 'test'],
    },
    'coverage': {
      'validationVariants': acc.validation.variantCount,
      'testVariants': acc.test.variantCount,
      'validationStationForecasts': acc.validation.stationForecastCount,
      'testStationForecasts': acc.test.stationForecastCount,
      'skippedMissingMagnitudeEvents': skippedMissingMagnitude,
      'skippedNoSourceEstimateVariants': skippedNoEstimate,
    },
    'thresholds': thresholds,
    'errors': errors,
  };
}

String plumSpecificityFrozenDiagnosticMarkdown(Map<String, Object?> report) {
  final policy = _map(report['policy']);
  final coverage = _map(report['coverage']);
  final thresholds = _map(report['thresholds']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Specificity Frozen Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Method: `${policy['method']}`')
    ..writeln('- Frozen test evaluated: `${policy['frozenTestEvaluated']}`')
    ..writeln('- Production ready: `${policy['productionReady']}`')
    ..writeln('- Production UI connected: `${policy['productionUiConnected']}`')
    ..writeln('- Diagnostic only: `${policy['diagnosticOnly']}`')
    ..writeln('- Parameters tuned: `${policy['parametersTuned']}`')
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
    ..writeln('## Method')
    ..writeln()
    ..writeln(
      '- This report isolates `PLUM r30/d0.50` specificity on validation and '
      'frozen test. It does not tune radius/damping, suppress predictions, or '
      'connect to UI/wording/notifications.',
    )
    ..writeln(
      '- Buckets split PLUM station forecasts by estimated-source region and '
      'distance, mask rate, PLUM evidence count, nearest evidence distance, '
      'strongest evidence intensity, and prediction margin above threshold.',
    )
    ..writeln(
      '- `plumOnlyFalsePositive` counts negative stations where PLUM crosses '
      'the threshold while JMA-style stays below it, matching the raw source '
      'diagnostic trigger-source decomposition.',
    )
    ..writeln();

  for (final threshold in _thresholds) {
    final t = _map(thresholds[threshold.label]);
    final splits = _map(t['splits']);
    buffer
      ..writeln('## `${threshold.label}`')
      ..writeln()
      ..writeln('### Overall')
      ..writeln()
      ..writeln(
        '| Split | TP | FP | FN | TN | Precision | Recall | Specificity | FPR | PLUM-only FP |',
      )
      ..writeln(
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
      );
    for (final splitName in const ['validation', 'test']) {
      final split = _map(splits[splitName]);
      final row = _map(split['overall']);
      buffer.writeln(
        '| $splitName | ${row['truePositive']} | ${row['falsePositive']} | '
        '${row['falseNegative']} | ${row['trueNegative']} | '
        '${_pct(row['precision'])} | ${_pct(row['recall'])} | '
        '${_pct(row['specificity'])} | '
        '${_pct(row['falsePositiveRate'])} | '
        '${row['plumOnlyFalsePositive']} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('### Delta (test - validation)')
      ..writeln()
      ..writeln('| Metric | Delta |')
      ..writeln('| --- | ---: |')
      ..writeln('| Precision | ${_signedPct(t['precisionDelta'])} |')
      ..writeln('| Specificity | ${_signedPct(t['specificityDelta'])} |')
      ..writeln('| FP count | ${t['falsePositiveDelta']} |')
      ..writeln();
    _writeBucketSection(
      buffer,
      title: 'Region Buckets',
      order: _regions,
      splits: splits,
      field: 'regionBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Estimated Source Distance Buckets',
      order: _distances,
      splits: splits,
      field: 'distanceBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Mask Rate Buckets',
      order: _maskRates,
      splits: splits,
      field: 'maskRateBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Evidence Count Buckets',
      order: _evidenceCounts,
      splits: splits,
      field: 'evidenceCountBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Nearest Evidence Distance Buckets',
      order: _nearestEvidenceDistances,
      splits: splits,
      field: 'nearestEvidenceDistanceBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Strongest Evidence Intensity Buckets',
      order: _strongestEvidenceIntensities,
      splits: splits,
      field: 'strongestEvidenceIntensityBuckets',
    );
    _writeBucketSection(
      buffer,
      title: 'Prediction Margin Buckets',
      order: _predictionMargins,
      splits: splits,
      field: 'predictionMarginBuckets',
    );
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Diagnostic-only. Results here identify PLUM r30/d0.50 specificity '
      'failure modes and do not authorize production intensity, UI, wording, '
      'notification, or parameter changes.',
    )
    ..writeln();
  return buffer.toString();
}

void _writeBucketSection(
  StringBuffer buffer, {
  required String title,
  required List<String> order,
  required Map<String, Object?> splits,
  required String field,
}) {
  buffer
    ..writeln('### $title')
    ..writeln()
    ..writeln(
      '| Bucket | Split | Count | TP | FP | FN | Precision | Recall | Specificity | PLUM-only FP |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final bucket in order) {
    for (final splitName in const ['validation', 'test']) {
      final split = _map(splits[splitName]);
      final buckets = _map(split[field]);
      final row = _map(buckets[bucket]);
      buffer.writeln(
        '| `$bucket` | $splitName | ${row['count'] ?? 0} | '
        '${row['truePositive'] ?? 0} | ${row['falsePositive'] ?? 0} | '
        '${row['falseNegative'] ?? 0} | ${_pct(row['precision'])} | '
        '${_pct(row['recall'])} | ${_pct(row['specificity'])} | '
        '${row['plumOnlyFalsePositive'] ?? 0} |',
      );
    }
  }
  buffer.writeln();
}

class _ReportAccumulator {
  final validation = _SplitAccumulator();
  final test = _SplitAccumulator();

  _SplitAccumulator split(String splitName) =>
      splitName == 'validation' ? validation : test;
}

class _SplitAccumulator {
  int variantCount = 0;
  int stationForecastCount = 0;
  final thresholds = <String, _ThresholdAccumulator>{};

  _ThresholdAccumulator threshold(String label) =>
      thresholds.putIfAbsent(label, _ThresholdAccumulator.new);
}

class _ThresholdAccumulator {
  final overall = _BucketStats();
  final regionBuckets = <String, _BucketStats>{};
  final distanceBuckets = <String, _BucketStats>{};
  final maskRateBuckets = <String, _BucketStats>{};
  final evidenceCountBuckets = <String, _BucketStats>{};
  final nearestEvidenceDistanceBuckets = <String, _BucketStats>{};
  final strongestEvidenceIntensityBuckets = <String, _BucketStats>{};
  final predictionMarginBuckets = <String, _BucketStats>{};

  void add(_PlumSpecificitySample sample, double threshold) {
    overall.add(sample, threshold);
    regionBuckets
        .putIfAbsent(sample.region, _BucketStats.new)
        .add(sample, threshold);
    distanceBuckets
        .putIfAbsent(sample.distanceBucket, _BucketStats.new)
        .add(sample, threshold);
    maskRateBuckets
        .putIfAbsent(sample.maskRateBucket, _BucketStats.new)
        .add(sample, threshold);
    evidenceCountBuckets
        .putIfAbsent(sample.evidenceCountBucket, _BucketStats.new)
        .add(sample, threshold);
    nearestEvidenceDistanceBuckets
        .putIfAbsent(sample.nearestEvidenceDistanceBucket, _BucketStats.new)
        .add(sample, threshold);
    strongestEvidenceIntensityBuckets
        .putIfAbsent(sample.strongestEvidenceIntensityBucket, _BucketStats.new)
        .add(sample, threshold);
    predictionMarginBuckets
        .putIfAbsent(
          _predictionMarginBucket(sample.plum - threshold),
          _BucketStats.new,
        )
        .add(sample, threshold);
  }

  Map<String, Object?> toJson() => {
    'overall': overall.toJson(),
    'regionBuckets': _bucketJson(regionBuckets),
    'distanceBuckets': _bucketJson(distanceBuckets),
    'maskRateBuckets': _bucketJson(maskRateBuckets),
    'evidenceCountBuckets': _bucketJson(evidenceCountBuckets),
    'nearestEvidenceDistanceBuckets': _bucketJson(
      nearestEvidenceDistanceBuckets,
    ),
    'strongestEvidenceIntensityBuckets': _bucketJson(
      strongestEvidenceIntensityBuckets,
    ),
    'predictionMarginBuckets': _bucketJson(predictionMarginBuckets),
  };
}

class _BucketStats {
  int count = 0;
  int truePositive = 0;
  int falsePositive = 0;
  int falseNegative = 0;
  int trueNegative = 0;
  int plumOnlyFalsePositive = 0;

  void add(_PlumSpecificitySample sample, double threshold) {
    count++;
    final actualPos = sample.actual >= threshold;
    final plumPos = sample.plum >= threshold;
    final jmaPos = sample.jma >= threshold;
    if (actualPos && plumPos) {
      truePositive++;
    } else if (!actualPos && plumPos) {
      falsePositive++;
      if (!jmaPos) plumOnlyFalsePositive++;
    } else if (actualPos && !plumPos) {
      falseNegative++;
    } else {
      trueNegative++;
    }
  }

  double get precision => truePositive + falsePositive == 0
      ? 0.0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0.0
      : truePositive / (truePositive + falseNegative);
  double get specificity => trueNegative + falsePositive == 0
      ? 0.0
      : trueNegative / (trueNegative + falsePositive);
  double get falsePositiveRate => trueNegative + falsePositive == 0
      ? 0.0
      : falsePositive / (trueNegative + falsePositive);

  Map<String, Object?> toJson() => {
    'count': count,
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'trueNegative': trueNegative,
    'precision': precision,
    'recall': recall,
    'specificity': specificity,
    'falsePositiveRate': falsePositiveRate,
    'plumOnlyFalsePositive': plumOnlyFalsePositive,
    'plumOnlyFalsePositiveShareOfFp': falsePositive == 0
        ? 0.0
        : plumOnlyFalsePositive / falsePositive,
  };
}

class _PlumSpecificitySample {
  final double actual;
  final double plum;
  final double jma;
  final String region;
  final String distanceBucket;
  final String maskRateBucket;
  final String evidenceCountBucket;
  final String nearestEvidenceDistanceBucket;
  final String strongestEvidenceIntensityBucket;

  const _PlumSpecificitySample({
    required this.actual,
    required this.plum,
    required this.jma,
    required this.region,
    required this.distanceBucket,
    required this.maskRateBucket,
    required this.evidenceCountBucket,
    required this.nearestEvidenceDistanceBucket,
    required this.strongestEvidenceIntensityBucket,
  });
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

Map<String, Object?> _bucketJson(Map<String, _BucketStats> buckets) => {
  for (final entry in buckets.entries) entry.key: entry.value.toJson(),
};

String _eventLatitudeBucket(double latitude) {
  if (latitude >= 41) return 'hokkaido';
  if (latitude >= 37.5) return 'tohoku';
  if (latitude >= 34.5) return 'kanto_chubu';
  return 'west_south';
}

String _distanceBucket(double distanceKm) {
  if (distanceKm < 30) return '000_030km';
  if (distanceKm < 60) return '030_060km';
  if (distanceKm < 100) return '060_100km';
  if (distanceKm < 200) return '100_200km';
  return 'gt_200km';
}

String _maskRateBucket(double value) =>
    '${(value * 100).round().toString()}pct';

String _evidenceCountBucket(int count) {
  if (count <= 0) return '0';
  if (count == 1) return '1';
  if (count <= 3) return '2_3';
  if (count <= 7) return '4_7';
  return 'gte_8';
}

String _nearestEvidenceDistanceBucket(double distanceKm) {
  if (!distanceKm.isFinite) return 'no_evidence';
  if (distanceKm < 10) return '000_010km';
  if (distanceKm < 20) return '010_020km';
  return '020_030km';
}

String _strongestEvidenceIntensityBucket(double? intensity) {
  if (intensity == null || !intensity.isFinite) return 'no_evidence';
  if (intensity < 1.5) return 'lt_1_5';
  if (intensity < 2.5) return '1_5_2_5';
  if (intensity < 3.5) return '2_5_3_5';
  return 'gte_3_5';
}

String _predictionMarginBucket(double margin) {
  if (margin < 0) return 'negative';
  if (margin < 0.25) return '000_025';
  if (margin < 0.50) return '025_050';
  if (margin < 1.00) return '050_100';
  return 'gte_100';
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String dataDirectory,
  required String modelPath,
}) => {
  'schemaVersion': 'plum_specificity_frozen_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': {
    'method': 'PLUM r30/d0.50 frozen specificity diagnostic',
    'rawPredictedIntensityMutated': false,
    'frozenTestEvaluated': true,
    'productionReady': false,
    'productionUiConnected': false,
    'diagnosticOnly': true,
    'parametersTuned': false,
    'plumRadiusKm': _plumRadiusKm,
    'plumDampingPer10Km': _plumDampingPer10Km,
  },
  'inputs': {
    'dataDirectory': dataDirectory,
    'modelPath': modelPath,
    'splits': ['validation', 'test'],
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

String _signedPct(Object? value) {
  final number = _number(value) * 100;
  final sign = number >= 0 ? '+' : '';
  return '$sign${number.toStringAsFixed(1)}pp';
}
