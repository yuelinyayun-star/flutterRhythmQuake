import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/core/calculator.dart';
import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

const _defaultDatasetPath =
    'tmp/jma_intensity_pretraining/synthetic_reveal_validation.json';
const _defaultModelPath =
    'tmp/jma_intensity_pretraining/static_attenuation_model.json';
const _defaultOutputPath =
    '.dart_tool/static_intensity_probability_gate/report.json';
const _defaultMarkdownPath =
    'docs/baselines/static_intensity_probability_gate.generated.md';

void main(List<String> args) {
  final datasetPath = _argument(args, '--validation') ?? _defaultDatasetPath;
  final modelPath = _argument(args, '--model') ?? _defaultModelPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildStaticIntensityProbabilityGateJson(
    validationDatasetPath: datasetPath,
    modelPath: modelPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(staticIntensityProbabilityGateMarkdown(report));

  stdout.writeln('wrote static intensity probability gate report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildStaticIntensityProbabilityGateJson({
  String validationDatasetPath = _defaultDatasetPath,
  String modelPath = _defaultModelPath,
}) {
  final errors = <String>[];
  final datasetFile = File(validationDatasetPath);
  final modelFile = File(modelPath);
  if (!datasetFile.existsSync()) {
    errors.add('validation_dataset_missing:$validationDatasetPath');
  }
  if (!modelFile.existsSync()) {
    errors.add('static_attenuation_model_missing:$modelPath');
  }
  if (errors.isNotEmpty) {
    return _emptyReport(
      errors: errors,
      validationDatasetPath: validationDatasetPath,
      modelPath: modelPath,
    );
  }

  final dataset =
      jsonDecode(datasetFile.readAsStringSync()) as Map<String, Object?>;
  final modelJson =
      jsonDecode(modelFile.readAsStringSync()) as Map<String, Object?>;
  final model = _modelFromJson(modelJson);
  final stations = _buildStationPredictions(dataset, model);
  if (stations.isEmpty) errors.add('no_station_predictions_produced');

  final residuals = _distanceResiduals(stations);
  final farCorrection = -(residuals['gt_200km']?.meanResidual ?? 0);
  final thresholds = [
    for (final threshold in _thresholds)
      _ThresholdReport.build(
        threshold: threshold,
        stations: stations,
        farCorrection: farCorrection,
      ),
  ];

  return {
    'schemaVersion': 'static_intensity_probability_gate_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'modelPath': modelPath,
    'validationDatasetPath': validationDatasetPath,
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'calibrationType': 'threshold_probability_gate_validation',
      'rawIntensityFieldMutated': false,
      'temporalSemantics':
          'synthetic reveal of final peak station intensity, not realtime observed intensity',
    },
    'farDistanceCorrection': farCorrection,
    'distanceResiduals': [
      for (final key in _distanceBucketOrder)
        if (residuals[key] != null)
          {'bucket': key, ...residuals[key]!.toJson()},
    ],
    'thresholds': [for (final threshold in thresholds) threshold.toJson()],
    'errors': errors,
  };
}

String staticIntensityProbabilityGateMarkdown(Map<String, Object?> report) {
  final buffer = StringBuffer()
    ..writeln('# Static Intensity Probability Gate')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `validation`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Raw intensity field mutated: `false`')
    ..writeln(
      '- `gt_200km` correction used only as a threshold-gate feature: `${_fmt(report['farDistanceCorrection'])}`',
    )
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This is a validation-only threshold probability/confidence gate '
      'diagnostic.',
    )
    ..writeln(
      '- It does not change the raw predicted intensity field or maximum-shindo '
      'display.',
    )
    ..writeln(
      '- It uses final peak station intensity with synthetic reveal masks, so '
      'it is not realtime lead-time validation.',
    )
    ..writeln()
    ..writeln('## Threshold Comparison')
    ..writeln()
    ..writeln(
      '| Threshold | Raw P/R/F1 | Hard `gt_200km` P/R/F1 | Gate P/R/F1 | Gate score |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['thresholds'])) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['label']}` | '
      '${_thresholdSummary(_map(row['rawThreshold']))} | '
      '${_thresholdSummary(_map(row['hardFarCorrection']))} | '
      '${_thresholdSummary(_map(row['probabilityGate']))} | '
      '`${_fmt(row['selectedGateScore'])}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Distance Residuals')
    ..writeln()
    ..writeln('| Bucket | Count | Mean residual | MAE |')
    ..writeln('| --- | ---: | ---: | ---: |');
  for (final raw in _list(report['distanceResiduals'])) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['bucket']}` | ${row['count']} | '
      '${_fmt(row['meanResidual'])} | ${_fmt(row['mae'])} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Next Step')
    ..writeln()
    ..writeln(
      '- If the probability gate beats both raw and hard correction on '
      'validation with acceptable recall, freeze acceptance criteria before '
      'opening the frozen test split.',
    )
    ..writeln();
  return buffer.toString();
}

List<_StationPrediction> _buildStationPredictions(
  Map<String, Object?> dataset,
  StaticAttenuationModel model,
) {
  final locator = StaticIntensityLocator(model: model);
  final stations = <_StationPrediction>[];
  for (final rawEvent in _list(dataset['events'])) {
    final event = StaticIntensityEvent.fromJson(_map(rawEvent));
    final stationsById = {
      for (final station in event.stations) station.stationId: station,
    };
    for (final variant in event.variants) {
      final retainedStations = [
        for (final id in variant.retainedStationIds)
          if (stationsById[id] != null) stationsById[id]!,
      ];
      final estimate = locator.locate(retainedStations);
      if (estimate == null) continue;
      for (final station in event.stations) {
        final predicted = _predictStationIntensity(model, estimate, station);
        stations.add(
          _StationPrediction(
            actual: station.intensity,
            predicted: predicted,
            distanceKm: _stationDistanceKm(estimate, station),
          ),
        );
      }
    }
  }
  return stations;
}

StaticAttenuationModel _modelFromJson(Map<String, Object?> json) {
  return StaticAttenuationModel(
    modelId: json['modelId']?.toString() ?? 'static_intensity_attenuation_v1',
    logDistanceCoefficient: (json['logDistanceCoefficient']! as num).toDouble(),
    linearDistanceCoefficient: (json['linearDistanceCoefficient']! as num)
        .toDouble(),
    nearDistanceKm: (json['nearDistanceKm']! as num).toDouble(),
    huberDelta: (json['huberDelta']! as num).toDouble(),
    residualScale: (json['residualScale']! as num).toDouble(),
    centroidPenaltyPerKm:
        (json['centroidPenaltyPerKm'] as num?)?.toDouble() ?? 0,
    depthClassesKm: [
      for (final value in _list(json['depthClassesKm']))
        (value as num).toDouble(),
    ],
  );
}

double _predictStationIntensity(
  StaticAttenuationModel model,
  StaticIntensityLocationEstimate estimate,
  StaticIntensityStation station,
) {
  final surfaceDistance = QuakeCalculator.haversineDistance(
    estimate.latitude,
    estimate.longitude,
    station.latitude,
    station.longitude,
  );
  final distance = math.sqrt(
    surfaceDistance * surfaceDistance + estimate.depthKm * estimate.depthKm,
  );
  return estimate.sourceScale -
      model.logDistanceCoefficient * _log10(distance + model.nearDistanceKm) -
      model.linearDistanceCoefficient * distance;
}

double _stationDistanceKm(
  StaticIntensityLocationEstimate estimate,
  StaticIntensityStation station,
) {
  final surfaceDistance = QuakeCalculator.haversineDistance(
    estimate.latitude,
    estimate.longitude,
    station.latitude,
    station.longitude,
  );
  return math.sqrt(
    surfaceDistance * surfaceDistance + estimate.depthKm * estimate.depthKm,
  );
}

Map<String, _DistanceResidualBucket> _distanceResiduals(
  List<_StationPrediction> stations,
) {
  final buckets = <String, _DistanceResidualBucket>{};
  for (final station in stations) {
    buckets
        .putIfAbsent(
          _distanceBucket(station.distanceKm),
          _DistanceResidualBucket.new,
        )
        .add(station);
  }
  return buckets;
}

class _ThresholdReport {
  final String label;
  final double value;
  final _ThresholdMetrics rawThreshold;
  final _ThresholdMetrics hardFarCorrection;
  final _ThresholdMetrics probabilityGate;
  final double selectedGateScore;

  const _ThresholdReport({
    required this.label,
    required this.value,
    required this.rawThreshold,
    required this.hardFarCorrection,
    required this.probabilityGate,
    required this.selectedGateScore,
  });

  factory _ThresholdReport.build({
    required _Threshold threshold,
    required List<_StationPrediction> stations,
    required double farCorrection,
  }) {
    final raw = _ThresholdMetrics.fromPredictions(
      stations,
      actualForStation: (station) => station.actual >= threshold.value,
      predictedForStation: (station) => station.predicted >= threshold.value,
    );
    final hard = _ThresholdMetrics.fromPredictions(
      stations,
      actualForStation: (station) => station.actual >= threshold.value,
      predictedForStation: (station) =>
          station.predicted +
              _farCorrectionForStation(station, farCorrection) >=
          threshold.value,
    );
    final rows = [
      for (final score in _gateScores)
        (
          score: score,
          metrics: _ThresholdMetrics.fromPredictions(
            stations,
            actualForStation: (station) => station.actual >= threshold.value,
            predictedForStation: (station) =>
                _gateScore(station, threshold.value, farCorrection) >= score,
          ),
        ),
    ];
    final selected = _selectGate(rows, raw);
    return _ThresholdReport(
      label: threshold.label,
      value: threshold.value,
      rawThreshold: raw,
      hardFarCorrection: hard,
      probabilityGate: selected.metrics,
      selectedGateScore: selected.score,
    );
  }

  Map<String, Object?> toJson() => {
    'label': label,
    'value': value,
    'rawThreshold': rawThreshold.toJson(),
    'hardFarCorrection': hardFarCorrection.toJson(),
    'probabilityGate': probabilityGate.toJson(),
    'selectedGateScore': selectedGateScore,
  };
}

({double score, _ThresholdMetrics metrics}) _selectGate(
  List<({double score, _ThresholdMetrics metrics})> rows,
  _ThresholdMetrics raw,
) {
  final allowed = rows.where((row) {
    return row.metrics.precision >= raw.precision &&
        row.metrics.f1 >= raw.f1 &&
        row.metrics.recall >= math.max(0, raw.recall - 0.18) &&
        row.metrics.falseNegative <= (raw.falseNegative * 1.2).ceil();
  }).toList();
  final pool = allowed.isEmpty ? rows : allowed;
  pool.sort((left, right) {
    final f1Order = right.metrics.f1.compareTo(left.metrics.f1);
    if (f1Order != 0) return f1Order;
    return right.metrics.precision.compareTo(left.metrics.precision);
  });
  return pool.first;
}

double _gateScore(
  _StationPrediction station,
  double threshold,
  double farCorrection,
) {
  final corrected =
      station.predicted + _farCorrectionForStation(station, farCorrection);
  final rawMargin = station.predicted - threshold;
  final correctedMargin = corrected - threshold;
  final effectiveMargin = math.min(rawMargin, correctedMargin);
  // Convert margin to a monotonic confidence-like score without claiming
  // calibrated probability yet. The report scans operating points separately.
  return 1 / (1 + math.exp(-effectiveMargin / 0.35));
}

double _farCorrectionForStation(
  _StationPrediction station,
  double farCorrection,
) {
  return _distanceBucket(station.distanceKm) == 'gt_200km' ? farCorrection : 0;
}

class _StationPrediction {
  final double actual;
  final double predicted;
  final double distanceKm;

  const _StationPrediction({
    required this.actual,
    required this.predicted,
    required this.distanceKm,
  });
}

class _DistanceResidualBucket {
  final residuals = <double>[];
  final errors = <double>[];

  void add(_StationPrediction station) {
    final residual = station.predicted - station.actual;
    residuals.add(residual);
    errors.add(residual.abs());
  }

  double get meanResidual => _mean(residuals);

  Map<String, Object?> toJson() => {
    'count': residuals.length,
    'meanResidual': meanResidual,
    'mae': _mean(errors),
  };
}

class _Threshold {
  final String label;
  final double value;

  const _Threshold(this.label, this.value);
}

const _thresholds = [
  _Threshold('shindo3', 2.5),
  _Threshold('shindo4', 3.5),
  _Threshold('shindo5-', 4.5),
];

const _gateScores = [
  0.05,
  0.1,
  0.15,
  0.2,
  0.25,
  0.3,
  0.35,
  0.4,
  0.45,
  0.5,
  0.55,
  0.6,
  0.65,
  0.7,
  0.75,
  0.8,
  0.85,
  0.9,
  0.95,
];

const _distanceBucketOrder = ['0_50km', '50_100km', '100_200km', 'gt_200km'];

String _distanceBucket(double distanceKm) {
  if (distanceKm <= 50) return '0_50km';
  if (distanceKm <= 100) return '50_100km';
  if (distanceKm <= 200) return '100_200km';
  return 'gt_200km';
}

class _ThresholdMetrics {
  final int truePositive;
  final int falsePositive;
  final int falseNegative;
  final int trueNegative;

  const _ThresholdMetrics({
    required this.truePositive,
    required this.falsePositive,
    required this.falseNegative,
    required this.trueNegative,
  });

  factory _ThresholdMetrics.fromPredictions(
    List<_StationPrediction> stations, {
    required bool Function(_StationPrediction station) actualForStation,
    required bool Function(_StationPrediction station) predictedForStation,
  }) {
    var truePositive = 0;
    var falsePositive = 0;
    var falseNegative = 0;
    var trueNegative = 0;
    for (final station in stations) {
      final actual = actualForStation(station);
      final predicted = predictedForStation(station);
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
    return _ThresholdMetrics(
      truePositive: truePositive,
      falsePositive: falsePositive,
      falseNegative: falseNegative,
      trueNegative: trueNegative,
    );
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
    'precision': precision,
    'recall': recall,
    'f1': f1,
  };
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String validationDatasetPath,
  required String modelPath,
}) => {
  'schemaVersion': 'static_intensity_probability_gate_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'validationDatasetPath': validationDatasetPath,
  'modelPath': modelPath,
  'errors': errors,
  'policy': const {
    'split': 'validation',
    'frozenTestEvaluated': false,
    'productionReady': false,
  },
  'farDistanceCorrection': 0.0,
  'distanceResiduals': const [],
  'thresholds': const [],
};

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

double _log10(double value) => math.log(value) / math.ln10;

double _mean(Iterable<double> values) {
  var sum = 0.0;
  var count = 0;
  for (final value in values) {
    if (!value.isFinite) continue;
    sum += value;
    count++;
  }
  return count == 0 ? 0.0 : sum / count;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

String _fmt(Object? value) {
  final number = _number(value);
  return number == null ? '-' : number.toStringAsFixed(2);
}

String _pct(Object? value) {
  final number = _number(value);
  return number == null ? '-' : '${(number * 100).toStringAsFixed(1)}%';
}

String _thresholdSummary(Map<String, Object?> metrics) {
  return '${_pct(metrics['precision'])} / '
      '${_pct(metrics['recall'])} / '
      '${_pct(metrics['f1'])}';
}
