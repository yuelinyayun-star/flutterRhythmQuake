import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';
import 'package:flutterrhythmquake/services/sources/jp_shindo_scale.dart';

const _defaultTestDatasetPath =
    '.dart_tool/plum_frozen_test_evaluation/synthetic_reveal_test.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/plum_frozen_regression_drilldown/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_frozen_regression_drilldown.generated.md';

const _plumRadiusKm = 30.0;
const _plumDampingPer10Km = 0.50;
const _threshold = 3.5;
const _exampleLimit = 12;

void main(List<String> args) {
  final testDatasetPath = _argument(args, '--test') ?? _defaultTestDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumFrozenRegressionDrilldownReportJson(
    testDatasetPath: testDatasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumFrozenRegressionDrilldownMarkdown(report));

  stdout.writeln('wrote PLUM frozen regression drilldown report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumFrozenRegressionDrilldownReportJson({
  String testDatasetPath = _defaultTestDatasetPath,
  String modelPath = _defaultModelPath,
}) {
  final errors = <String>[];
  final testFile = File(testDatasetPath);
  final modelFile = File(modelPath);
  if (!testFile.existsSync()) {
    errors.add('test_dataset_missing:$testDatasetPath');
  }
  if (!modelFile.existsSync()) errors.add('model_missing:$modelPath');
  if (errors.isNotEmpty) {
    return {
      'schemaVersion': 'plum_frozen_regression_drilldown_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': 'fail',
      'errors': errors,
    };
  }

  final model = _modelFromJson(
    jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>,
  );
  final dataset =
      jsonDecode(testFile.readAsStringSync()) as Map<String, Object?>;
  final examples = {
    for (final bucket in _targetBuckets) bucket.id: _ExampleCollector(),
  };
  final locator = StaticIntensityLocator(model: model);
  final jmaPredictor = const JmaStyleIntensityPredictor();
  final plumPredictor = const PlumLikeIntensityPredictor(
    radiusKm: _plumRadiusKm,
    dampingPer10Km: _plumDampingPer10Km,
    minimumEvidenceCount: 1,
  );
  var stationForecastCount = 0;
  var skippedNoEstimate = 0;
  for (final rawEvent in _list(dataset['events'])) {
    final event = _Event.fromJson(_map(rawEvent));
    final actualMax = event.stations.fold<double>(
      -3,
      (max, station) => station.intensity > max ? station.intensity : max,
    );
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
      final retainedStatic = [
        for (final station in retained) station.toStaticStation(),
      ];
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
              observedStations: retainedStatic,
            )
            .intensity;
        final predicted = math.max(jmaPredicted, plumPredicted);
        stationForecastCount++;
        final actualPositive = station.intensity >= _threshold;
        final predictedPositive = predicted >= _threshold;
        if (actualPositive == predictedPositive) continue;
        final row = {
          'eventId': event.eventId,
          'variantId': variant.variantId,
          'maskRate': variant.maskRate,
          'stationId': station.stationId,
          'actualIntensity': station.intensity,
          'predictedIntensity': predicted,
          'error': predicted - station.intensity,
          'jmaPredicted': jmaPredicted,
          'plumPredicted': plumPredicted,
          'surfaceDistanceKm': station.surfaceDistanceKm,
          'actualMaxIntensity': actualMax,
          'actualMaxBucket': _actualMaxBucket(actualMax),
          'eventLatitudeBand': _eventLatitudeBucket(event.latitude),
          'stationDistanceBucket': _distanceBucket(station.surfaceDistanceKm),
          'maskRateBucket': _maskRateBucket(variant.maskRate),
        };
        for (final bucket in _targetBuckets) {
          if (!bucket.matches(row)) continue;
          examples[bucket.id]!.add(row, falsePositive: predictedPositive);
        }
      }
    }
  }

  return {
    'schemaVersion': 'plum_frozen_regression_drilldown_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': 'pass',
    'policy': const {
      'split': 'test',
      'frozenTestEvaluated': true,
      'productionReady': false,
      'productionUiConnected': false,
      'diagnosticOnly': true,
    },
    'inputs': {
      'testDatasetPath': testDatasetPath,
      'modelPath': modelPath,
      'method': 'max_jma_style_plum_like_r30_d0_50',
      'threshold': 'shindo4',
    },
    'coverage': {
      'stationForecastCount': stationForecastCount,
      'skippedNoEstimateVariants': skippedNoEstimate,
    },
    'buckets': {
      for (final entry in examples.entries) entry.key: entry.value.toJson(),
    },
    'decision': const {
      'advanceToProduction': false,
      'nextAction':
          'inspect_examples_then_design_validation_gate_or_model_revision',
    },
    'errors': errors,
  };
}

String plumFrozenRegressionDrilldownMarkdown(Map<String, Object?> report) {
  final coverage = _map(report['coverage']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Frozen Regression Drilldown')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Frozen test evaluated: `true`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Threshold: `shindo4`')
    ..writeln(
      '- Station forecasts: `${coverage['stationForecastCount'] ?? 'n/a'}`',
    )
    ..writeln(
      '- Skipped no-estimate variants: '
      '`${coverage['skippedNoEstimateVariants'] ?? 'n/a'}`',
    )
    ..writeln()
    ..writeln('## Buckets');
  final buckets = _map(report['buckets']);
  for (final bucketId in buckets.keys.toList()..sort()) {
    final bucket = _map(buckets[bucketId]);
    buffer
      ..writeln()
      ..writeln('### `$bucketId`')
      ..writeln()
      ..writeln(
        '- False positives: `${bucket['falsePositiveCount']}`, false negatives: `${bucket['falseNegativeCount']}`',
      )
      ..writeln()
      ..writeln(
        '| Type | Event | Variant | Station | Actual | Pred | Error | Distance | Max |',
      )
      ..writeln('| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |');
    for (final raw in [
      ..._list(bucket['falsePositives']),
      ..._list(bucket['falseNegatives']),
    ]) {
      final row = _map(raw);
      buffer.writeln(
        '| `${row['type']}` | `${row['eventId']}` | `${row['variantId']}` | '
        '`${row['stationId']}` | ${_fmt(row['actualIntensity'])} | '
        '${_fmt(row['predictedIntensity'])} | ${_fmt(row['error'])} | '
        '${_fmt(row['surfaceDistanceKm'])} km | '
        '${_fmt(row['actualMaxIntensity'])} |',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln('## Interpretation')
    ..writeln()
    ..writeln(
      '- The frozen failure is not a single far-distance issue: the inspected '
      'buckets include both 30-60 km regressions and near/medium distance '
      'Kanto-Chubu examples.',
    )
    ..writeln(
      '- False positives show strong local observed shaking being propagated '
      'into weak stations.',
    )
    ..writeln(
      '- False negatives show high-mask variants and strong local stations '
      'that are not recovered by the current PLUM/JMA max branch.',
    )
    ..writeln(
      '- Next model changes must be designed on validation diagnostics only; '
      'this opened frozen split must not become a tuning set.',
    )
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Production remains blocked.')
    ..writeln(
      '- Use these examples to decide whether a new validation gate or model-family revision is required.',
    )
    ..writeln();
  return buffer.toString();
}

class _TargetBucket {
  final String id;
  final bool Function(Map<String, Object?> row) matches;

  const _TargetBucket(this.id, this.matches);
}

final _targetBuckets = [
  _TargetBucket(
    'eventLatitudeBand_kanto_chubu',
    (row) => row['eventLatitudeBand'] == 'kanto_chubu',
  ),
  _TargetBucket(
    'stationDistance_030_060km',
    (row) => row['stationDistanceBucket'] == '030_060km',
  ),
  _TargetBucket('maskRate_80pct', (row) => row['maskRateBucket'] == '80pct'),
  _TargetBucket(
    'actualMaxClass_max_5plus',
    (row) => row['actualMaxBucket'] == 'max_5plus',
  ),
];

class _ExampleCollector {
  final falsePositives = <Map<String, Object?>>[];
  final falseNegatives = <Map<String, Object?>>[];

  void add(Map<String, Object?> row, {required bool falsePositive}) {
    final target = falsePositive ? falsePositives : falseNegatives;
    target.add({...row, 'type': falsePositive ? 'FP' : 'FN'});
  }

  Map<String, Object?> toJson() {
    int byMagnitude(Map<String, Object?> left, Map<String, Object?> right) =>
        _number(right['error']).abs().compareTo(_number(left['error']).abs());
    falsePositives.sort(byMagnitude);
    falseNegatives.sort(byMagnitude);
    return {
      'falsePositiveCount': falsePositives.length,
      'falseNegativeCount': falseNegatives.length,
      'falsePositives': falsePositives.take(_exampleLimit).toList(),
      'falseNegatives': falseNegatives.take(_exampleLimit).toList(),
    };
  }
}

class _Event {
  final String eventId;
  final double latitude;
  final double magnitude;
  final List<_Station> stations;
  final List<_Variant> variants;

  const _Event({
    required this.eventId,
    required this.latitude,
    required this.magnitude,
    required this.stations,
    required this.variants,
  });

  factory _Event.fromJson(Map<String, Object?> json) {
    final truth = _map(json['truth']);
    return _Event(
      eventId: json['eventId']!.toString(),
      latitude: _number(truth['latitude']),
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
  final String variantId;
  final double maskRate;
  final List<String> retainedStationIds;

  const _Variant({
    required this.variantId,
    required this.maskRate,
    required this.retainedStationIds,
  });

  factory _Variant.fromJson(Map<String, Object?> json) => _Variant(
    variantId: json['variantId']!.toString(),
    maskRate: _number(json['requestedMaskRate']),
    retainedStationIds: [
      for (final raw in _list(json['retainedStationIds'])) raw.toString(),
    ],
  );
}

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

String _fmt(Object? value) => _number(value).toStringAsFixed(2);
