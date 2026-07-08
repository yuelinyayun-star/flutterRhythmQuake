import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

const _defaultValidationDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultTestDatasetPath =
    '.dart_tool/plum_frozen_test_evaluation/synthetic_reveal_test.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_frozen_regression_diagnostic/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_frozen_regression_diagnostic.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;

void main(List<String> args) {
  final validationDatasetPath =
      _argument(args, '--validation') ?? _defaultValidationDatasetPath;
  final testDatasetPath = _argument(args, '--test') ?? _defaultTestDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumFrozenRegressionDiagnosticReportJson(
    validationDatasetPath: validationDatasetPath,
    testDatasetPath: testDatasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumFrozenRegressionDiagnosticMarkdown(report));

  stdout.writeln('wrote PLUM frozen regression diagnostic report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumFrozenRegressionDiagnosticReportJson({
  String validationDatasetPath = _defaultValidationDatasetPath,
  String testDatasetPath = _defaultTestDatasetPath,
  String modelPath = _defaultModelPath,
}) {
  final errors = <String>[];
  final validationFile = File(validationDatasetPath);
  final testFile = File(testDatasetPath);
  final modelFile = File(modelPath);
  if (!validationFile.existsSync()) {
    errors.add('validation_dataset_missing:$validationDatasetPath');
  }
  if (!testFile.existsSync()) {
    errors.add('test_dataset_missing:$testDatasetPath');
  }
  if (!modelFile.existsSync()) {
    errors.add('model_missing:$modelPath');
  }
  if (errors.isNotEmpty) {
    return _emptyReport(
      errors: errors,
      validationDatasetPath: validationDatasetPath,
      testDatasetPath: testDatasetPath,
      modelPath: modelPath,
    );
  }

  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final validation = _evaluateDataset(
    split: 'validation',
    dataset:
        jsonDecode(validationFile.readAsStringSync()) as Map<String, Object?>,
    model: model,
  );
  final test = _evaluateDataset(
    split: 'test',
    dataset: jsonDecode(testFile.readAsStringSync()) as Map<String, Object?>,
    model: model,
  );

  final comparisons = {
    for (final group in _groupOrder)
      group: _compareGroups(
        _map(validation['groups'])[group],
        _map(test['groups'])[group],
      ),
  };
  final worstShindo4 = _worstDrops(comparisons, threshold: 'shindo4');
  final worstShindo5 = _worstDrops(comparisons, threshold: 'shindo5-');

  return {
    'schemaVersion': 'plum_frozen_regression_diagnostic_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': 'pass',
    'policy': const {
      'splitComparison': 'validation_vs_test',
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'selectedForProduction': false,
      'diagnosticOnly': true,
    },
    'inputs': {
      'validationDatasetPath': validationDatasetPath,
      'testDatasetPath': testDatasetPath,
      'modelPath': modelPath,
      'method': 'max_jma_style_plum_like_r30_d0_50',
      'plumRadiusKm': _plumRadiusKm,
      'plumDampingPer10Km': _plumDampingPer10Km,
    },
    'validation': validation,
    'test': test,
    'comparisons': comparisons,
    'worstDrops': {'shindo4': worstShindo4, 'shindo5-': worstShindo5},
    'decision': const {
      'advanceToProduction': false,
      'nextAction': 'inspect_worst_buckets_before_model_revision',
    },
    'errors': errors,
  };
}

Map<String, Object?> _evaluateDataset({
  required String split,
  required Map<String, Object?> dataset,
  required StaticAttenuationModel model,
}) {
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumPredictor = const PlumLikeIntensityPredictor(
    radiusKm: _plumRadiusKm,
    dampingPer10Km: _plumDampingPer10Km,
    minimumEvidenceCount: 1,
  );
  final groups = {
    for (final group in _groupOrder) group: <String, _BucketAccumulator>{},
  };
  var caseCount = 0;
  var stationForecastCount = 0;
  var skippedNoEstimate = 0;
  for (final rawEvent in _list(dataset['events'])) {
    final event = _Event.fromJson(_map(rawEvent));
    final actualMax = event.stations.fold<double>(
      -3.0,
      (max, station) => station.intensity > max ? station.intensity : max,
    );
    final actualMaxBucket = _actualMaxBucket(actualMax);
    final eventLatBucket = _eventLatitudeBucket(event.latitude);
    final stationsById = {
      for (final station in event.stations) station.stationId: station,
    };
    for (final variant in event.variants) {
      final retained = [
        for (final id in variant.retainedStationIds)
          if (stationsById[id] != null) stationsById[id]!,
      ];
      final estimate = locator.locate([
        for (final station in retained) station.toStaticStation(),
      ]);
      if (estimate == null) {
        skippedNoEstimate++;
        continue;
      }
      caseCount++;
      for (final station in event.stations) {
        final jmaPredicted = jmaPredictor
            .predict(
              magnitude: event.magnitude,
              sourceLatitude: estimate.latitude,
              sourceLongitude: estimate.longitude,
              depthKm: estimate.depthKm,
              stationLatitude: station.latitude,
              stationLongitude: station.longitude,
            )
            .intensity;
        final plumPredicted = plumPredictor
            .predict(
              targetStation: station.toStaticStation(),
              observedStations: [
                for (final retainedStation in retained)
                  retainedStation.toStaticStation(),
              ],
            )
            .intensity;
        final predicted = math.max(jmaPredicted, plumPredicted);
        stationForecastCount++;
        _add(groups['overall']!, 'all', station.intensity, predicted);
        _add(
          groups['maskRate']!,
          _maskRateBucket(variant.maskRate),
          station.intensity,
          predicted,
        );
        _add(
          groups['actualMaxClass']!,
          actualMaxBucket,
          station.intensity,
          predicted,
        );
        _add(
          groups['stationDistance']!,
          _distanceBucket(station.surfaceDistanceKm),
          station.intensity,
          predicted,
        );
        _add(
          groups['eventLatitudeBand']!,
          eventLatBucket,
          station.intensity,
          predicted,
        );
      }
    }
  }
  return {
    'split': split,
    'caseCount': caseCount,
    'stationForecastCount': stationForecastCount,
    'skippedNoEstimateVariants': skippedNoEstimate,
    'groups': {
      for (final entry in groups.entries)
        entry.key: {
          for (final bucket in entry.value.entries)
            bucket.key: bucket.value.toJson(),
        },
    },
  };
}

void _add(
  Map<String, _BucketAccumulator> buckets,
  String bucket,
  double actual,
  double predicted,
) {
  buckets
      .putIfAbsent(bucket, _BucketAccumulator.new)
      .add(actual: actual, predicted: predicted);
}

Map<String, Object?> _compareGroups(Object? rawValidation, Object? rawTest) {
  final validation = _map(rawValidation);
  final test = _map(rawTest);
  final bucketNames = {...validation.keys, ...test.keys}.toList()..sort();
  return {
    for (final bucket in bucketNames)
      bucket: _compareBucket(_map(validation[bucket]), _map(test[bucket])),
  };
}

Map<String, Object?> _compareBucket(
  Map<String, Object?> validation,
  Map<String, Object?> test,
) {
  return {
    for (final threshold in _thresholds)
      threshold.label: {
        'validation': _map(validation[threshold.label]),
        'test': _map(test[threshold.label]),
        'delta': _delta(
          _map(validation[threshold.label]),
          _map(test[threshold.label]),
        ),
      },
  };
}

Map<String, Object?> _delta(
  Map<String, Object?> validation,
  Map<String, Object?> test,
) {
  return {
    'precision': _number(test['precision']) - _number(validation['precision']),
    'recall': _number(test['recall']) - _number(validation['recall']),
    'f1': _number(test['f1']) - _number(validation['f1']),
    'falsePositive':
        _intValue(test['falsePositive']) -
        _intValue(validation['falsePositive']),
    'falseNegative':
        _intValue(test['falseNegative']) -
        _intValue(validation['falseNegative']),
  };
}

List<Map<String, Object?>> _worstDrops(
  Map<String, Object?> comparisons, {
  required String threshold,
}) {
  final rows = <Map<String, Object?>>[];
  for (final groupEntry in comparisons.entries) {
    final buckets = _map(groupEntry.value);
    for (final bucketEntry in buckets.entries) {
      final row = _map(_map(bucketEntry.value)[threshold]);
      final delta = _map(row['delta']);
      final test = _map(row['test']);
      if (_intValue(test['actualPositive']) < 10) continue;
      rows.add({
        'group': groupEntry.key,
        'bucket': bucketEntry.key,
        'testActualPositive': _intValue(test['actualPositive']),
        'validationF1': _number(_map(row['validation'])['f1']),
        'testF1': _number(test['f1']),
        'deltaF1': _number(delta['f1']),
        'deltaPrecision': _number(delta['precision']),
        'deltaRecall': _number(delta['recall']),
      });
    }
  }
  rows.sort((left, right) {
    final order = (_number(
      left['deltaF1'],
    )).compareTo(_number(right['deltaF1']));
    if (order != 0) return order;
    return (_number(left['testF1'])).compareTo(_number(right['testF1']));
  });
  return rows.take(8).toList(growable: false);
}

String plumFrozenRegressionDiagnosticMarkdown(Map<String, Object?> report) {
  final validationOverall = _map(
    _map(_map(_map(report['validation'])['groups'])['overall'])['all'],
  );
  final testOverall = _map(
    _map(_map(_map(report['test'])['groups'])['overall'])['all'],
  );
  final buffer = StringBuffer()
    ..writeln('# PLUM Frozen Regression Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Frozen test evaluated: `true`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Method: `max_jma_style_plum_like_r30_d0_50`')
    ..writeln()
    ..writeln('## Overall Thresholds')
    ..writeln()
    ..writeln('| Threshold | Validation P/R/F1 | Test P/R/F1 | Delta P/R/F1 |')
    ..writeln('| --- | ---: | ---: | ---: |');
  for (final threshold in _thresholds) {
    final validation = _map(validationOverall[threshold.label]);
    final test = _map(testOverall[threshold.label]);
    final delta = _delta(validation, test);
    buffer.writeln(
      '| `${threshold.label}` | ${_triplet(validation)} | ${_triplet(test)} | '
      '${_triplet(delta, signed: true)} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Worst Shindo4 F1 Drops')
    ..writeln()
    ..writeln(
      '| Group | Bucket | Test positives | Validation F1 | Test F1 | Delta F1 |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: |');
  for (final row in _list(_map(report['worstDrops'])['shindo4'])) {
    final item = _map(row);
    buffer.writeln(
      '| `${item['group']}` | `${item['bucket']}` | '
      '${item['testActualPositive']} | ${_pct(item['validationF1'])} | '
      '${_pct(item['testF1'])} | ${_signedPct(item['deltaF1'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Bucket Comparisons')
    ..writeln()
    ..writeln('### Shindo4 F1 by Mask Rate')
    ..writeln()
    ..writeln('| Bucket | Validation | Test | Delta |')
    ..writeln('| --- | ---: | ---: | ---: |');
  _writeBucketRows(buffer, report, group: 'maskRate', threshold: 'shindo4');
  buffer
    ..writeln()
    ..writeln('### Shindo4 F1 by Station Distance')
    ..writeln()
    ..writeln('| Bucket | Validation | Test | Delta |')
    ..writeln('| --- | ---: | ---: | ---: |');
  _writeBucketRows(
    buffer,
    report,
    group: 'stationDistance',
    threshold: 'shindo4',
  );
  buffer
    ..writeln()
    ..writeln('### Shindo4 F1 by Actual Max Class')
    ..writeln()
    ..writeln('| Bucket | Validation | Test | Delta |')
    ..writeln('| --- | ---: | ---: | ---: |');
  _writeBucketRows(
    buffer,
    report,
    group: 'actualMaxClass',
    threshold: 'shindo4',
  );
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Do not tune from this frozen report.')
    ..writeln(
      '- Use the bucket failures to decide whether the model family or validation gates were insufficient.',
    )
    ..writeln('- Production remains blocked.')
    ..writeln();
  return buffer.toString();
}

void _writeBucketRows(
  StringBuffer buffer,
  Map<String, Object?> report, {
  required String group,
  required String threshold,
}) {
  final buckets = _map(_map(report['comparisons'])[group]);
  for (final bucket in buckets.keys.toList()..sort()) {
    final row = _map(_map(buckets[bucket])[threshold]);
    final validation = _map(row['validation']);
    final test = _map(row['test']);
    final delta = _map(row['delta']);
    buffer.writeln(
      '| `$bucket` | ${_pct(validation['f1'])} | ${_pct(test['f1'])} | '
      '${_signedPct(delta['f1'])} |',
    );
  }
}

class _Event {
  final String eventId;
  final double latitude;
  final double longitude;
  final double depthKm;
  final double magnitude;
  final List<_Station> stations;
  final List<_Variant> variants;

  const _Event({
    required this.eventId,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
    required this.stations,
    required this.variants,
  });

  factory _Event.fromJson(Map<String, Object?> json) {
    final truth = _map(json['truth']);
    return _Event(
      eventId: json['eventId']!.toString(),
      latitude: _number(truth['latitude']),
      longitude: _number(truth['longitude']),
      depthKm: _number(truth['depthKm']),
      magnitude: _number(truth['magnitude']),
      stations: [
        for (final raw in _list(json['stations'])) _Station.fromJson(_map(raw)),
      ],
      variants: [
        for (final raw in _list(json['variants'])) _Variant.fromJson(_map(raw)),
      ],
    );
  }
}

class _Station {
  final String stationId;
  final double latitude;
  final double longitude;
  final double intensity;
  final double surfaceDistanceKm;

  const _Station({
    required this.stationId,
    required this.latitude,
    required this.longitude,
    required this.intensity,
    required this.surfaceDistanceKm,
  });

  factory _Station.fromJson(Map<String, Object?> json) => _Station(
    stationId: json['stationId']!.toString(),
    latitude: _number(json['latitude']),
    longitude: _number(json['longitude']),
    intensity: _number(json['instrumentalIntensity']),
    surfaceDistanceKm: _number(json['surfaceDistanceKm']),
  );

  StaticIntensityStation toStaticStation() => StaticIntensityStation(
    stationId: stationId,
    latitude: latitude,
    longitude: longitude,
    intensity: intensity,
  );
}

class _Variant {
  final double maskRate;
  final List<String> retainedStationIds;

  const _Variant({required this.maskRate, required this.retainedStationIds});

  factory _Variant.fromJson(Map<String, Object?> json) => _Variant(
    maskRate: _number(json['requestedMaskRate']),
    retainedStationIds: [
      for (final raw in _list(json['retainedStationIds'])) raw.toString(),
    ],
  );
}

class _BucketAccumulator {
  final counts = {
    for (final threshold in _thresholds) threshold.label: _ThresholdCounts(),
  };

  void add({required double actual, required double predicted}) {
    for (final threshold in _thresholds) {
      counts[threshold.label]!.add(
        actual: actual >= threshold.value,
        predicted: predicted >= threshold.value,
      );
    }
  }

  Map<String, Object?> toJson() => {
    for (final entry in counts.entries) entry.key: entry.value.toJson(),
  };
}

class _ThresholdCounts {
  var truePositive = 0;
  var falsePositive = 0;
  var falseNegative = 0;
  var trueNegative = 0;

  void add({required bool actual, required bool predicted}) {
    if (actual && predicted) {
      truePositive++;
    } else if (!actual && predicted) {
      falsePositive++;
    } else if (actual && !predicted) {
      falseNegative++;
    } else {
      trueNegative++;
    }
  }

  double get precision => truePositive + falsePositive == 0
      ? 0
      : truePositive / (truePositive + falsePositive);
  double get recall => truePositive + falseNegative == 0
      ? 0
      : truePositive / (truePositive + falseNegative);
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);

  Map<String, Object?> toJson() => {
    'truePositive': truePositive,
    'falsePositive': falsePositive,
    'falseNegative': falseNegative,
    'trueNegative': trueNegative,
    'actualPositive': truePositive + falseNegative,
    'predictedPositive': truePositive + falsePositive,
    'precision': precision,
    'recall': recall,
    'f1': f1,
  };
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

const _thresholds = [_Threshold('shindo4', 3.5), _Threshold('shindo5-', 4.5)];

const _groupOrder = [
  'overall',
  'maskRate',
  'actualMaxClass',
  'stationDistance',
  'eventLatitudeBand',
];

String _maskRateBucket(double value) => '${(value * 100).round()}pct';

String _actualMaxBucket(double shindo) {
  final index = JpShindoScale.jmaIndexFromShindo(shindo);
  if (index <= 2) return 'max_le_2';
  if (index == 3) return 'max_3';
  if (index == 4) return 'max_4';
  return 'max_5plus';
}

String _distanceBucket(double distanceKm) {
  if (distanceKm < 30) return '000_030km';
  if (distanceKm < 60) return '030_060km';
  if (distanceKm < 100) return '060_100km';
  if (distanceKm < 200) return '100_200km';
  return 'gt_200km';
}

String _eventLatitudeBucket(double latitude) {
  if (latitude >= 41) return 'hokkaido';
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

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
  required String testDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'plum_frozen_regression_diagnostic_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'inputs': {
    'validationDatasetPath': validationDatasetPath,
    'testDatasetPath': testDatasetPath,
    'modelPath': modelPath,
  },
  'errors': errors,
};

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

List<Object?> _list(Object? value) => value is List ? value : const [];

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.parse(value?.toString() ?? '0');
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _triplet(Map<String, Object?> row, {bool signed = false}) {
  final formatter = signed ? _signedPct : _pct;
  return '${formatter(row['precision'])} / ${formatter(row['recall'])} / '
      '${formatter(row['f1'])}';
}

String _pct(Object? value) {
  final number = _number(value);
  return '${(number * 100).toStringAsFixed(1)}%';
}

String _signedPct(Object? value) {
  final number = _number(value);
  final sign = number > 0 ? '+' : '';
  return '$sign${(number * 100).toStringAsFixed(1)}%';
}
