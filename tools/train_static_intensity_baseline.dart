import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/source_estimation/static_intensity_attenuation.dart';

void main(List<String> args) {
  final trainPath = _argument(args, '--train');
  final validationPath = _argument(args, '--validation');
  final outputDirectory = _argument(args, '--output');
  if (trainPath == null || validationPath == null || outputDirectory == null) {
    stderr.writeln(
      'Usage: dart run tools/train_static_intensity_baseline.dart '
      '--train <synthetic_reveal_train.json> '
      '--validation <synthetic_reveal_validation.json> --output <directory>',
    );
    exitCode = 64;
    return;
  }
  final train = _readEvents(File(trainPath), expectedSplit: 'train');
  final validation = _readEvents(
    File(validationPath),
    expectedSplit: 'validation',
  );
  final unregularizedModel = const StaticAttenuationTrainer(
    logDistanceCandidates: [0.5, 1, 1.5, 2, 2.5, 3, 4, 5],
  ).train(train);
  final candidates =
      <
        ({StaticAttenuationModel model, StaticIntensityEvaluation evaluation})
      >[];
  for (final penalty in const [0.0, 0.0025, 0.005, 0.01, 0.02, 0.05]) {
    final model = unregularizedModel.copyWith(centroidPenaltyPerKm: penalty);
    final evaluation = StaticIntensityEvaluator(
      StaticIntensityLocator(model: model),
    ).evaluate(validation);
    candidates.add((model: model, evaluation: evaluation));
  }
  candidates.sort((left, right) {
    final leftObjective =
        left.evaluation.medianErrorKm + left.evaluation.p90ErrorKm * 0.25;
    final rightObjective =
        right.evaluation.medianErrorKm + right.evaluation.p90ErrorKm * 0.25;
    return leftObjective.compareTo(rightObjective);
  });
  final model = candidates.first.model;
  final evaluation = candidates.first.evaluation;
  final output = Directory(outputDirectory)..createSync(recursive: true);
  _writeJson(
    File('${output.path}/static_attenuation_model.json'),
    model.toJson(),
  );
  final report = {
    'schemaVersion': 1,
    'modelId': model.modelId,
    'trainedAt': DateTime.now().toUtc().toIso8601String(),
    'training': {
      'split': 'train',
      'eventCount': train.length,
      'testEventsRead': 0,
    },
    'evaluation': {'split': 'validation', ...evaluation.toJson()},
    'modelSelection': [
      for (final candidate in candidates)
        {
          'centroidPenaltyPerKm': candidate.model.centroidPenaltyPerKm,
          'medianErrorKm': candidate.evaluation.medianErrorKm,
          'p90ErrorKm': candidate.evaluation.p90ErrorKm,
          'objective':
              candidate.evaluation.medianErrorKm +
              candidate.evaluation.p90ErrorKm * 0.25,
        },
    ],
    'testPolicy': {
      'status': 'frozen',
      'evaluated': false,
      'reason': 'validation_only_model_selection',
    },
  };
  _writeJson(File('${output.path}/static_attenuation_validation.json'), report);
  File(
    '${output.path}/static_attenuation_validation.md',
  ).writeAsStringSync(_markdown(model, evaluation));
  stdout.writeln(jsonEncode(evaluation.toJson()));
}

List<StaticIntensityEvent> _readEvents(
  File file, {
  required String expectedSplit,
}) {
  if (!file.existsSync()) throw StateError('Missing input: ${file.path}');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  if (json['split'] != expectedSplit) {
    throw FormatException(
      'Expected $expectedSplit input, got ${json['split']}.',
    );
  }
  return [
    for (final raw in json['events']! as List<Object?>)
      StaticIntensityEvent.fromJson(raw! as Map<String, Object?>),
  ];
}

String _markdown(
  StaticAttenuationModel model,
  StaticIntensityEvaluation evaluation,
) {
  final buffer = StringBuffer()
    ..writeln('# P3 Static Intensity Attenuation Baseline')
    ..writeln()
    ..writeln('Model: `${model.modelId}`')
    ..writeln()
    ..writeln('Test split: frozen, not evaluated')
    ..writeln()
    ..writeln('## Parameters')
    ..writeln()
    ..writeln('| Parameter | Value |')
    ..writeln('| --- | ---: |')
    ..writeln('| log-distance coefficient | ${model.logDistanceCoefficient} |')
    ..writeln(
      '| linear-distance coefficient | ${model.linearDistanceCoefficient} |',
    )
    ..writeln('| near-distance km | ${model.nearDistanceKm} |')
    ..writeln('| Huber delta | ${model.huberDelta} |')
    ..writeln('| robust residual scale | ${model.residualScale} |')
    ..writeln('| centroid penalty / km | ${model.centroidPenaltyPerKm} |')
    ..writeln()
    ..writeln('## Validation')
    ..writeln()
    ..writeln('| Metric | P3 | Weighted centroid |')
    ..writeln('| --- | ---: | ---: |')
    ..writeln(
      '| Median error | ${evaluation.medianErrorKm.toStringAsFixed(2)} km | '
      '${evaluation.weightedCentroidMedianErrorKm.toStringAsFixed(2)} km |',
    )
    ..writeln(
      '| P90 error | ${evaluation.p90ErrorKm.toStringAsFixed(2)} km | '
      '${evaluation.weightedCentroidP90ErrorKm.toStringAsFixed(2)} km |',
    )
    ..writeln()
    ..writeln(
      'P50 coverage: ${(evaluation.p50Coverage * 100).toStringAsFixed(1)}%',
    )
    ..writeln()
    ..writeln(
      'P90 coverage: ${(evaluation.p90Coverage * 100).toStringAsFixed(1)}%',
    )
    ..writeln()
    ..writeln('## Mask Rates')
    ..writeln()
    ..writeln('| Mask | Cases | P3 median | P3 P90 | Centroid median |')
    ..writeln('| ---: | ---: | ---: | ---: | ---: |');
  for (final entry in evaluation.byMaskRate.entries) {
    final values = entry.value;
    buffer.writeln(
      '| ${entry.key} | ${values['caseCount']} | '
      '${(values['medianErrorKm']! as double).toStringAsFixed(2)} km | '
      '${(values['p90ErrorKm']! as double).toStringAsFixed(2)} km | '
      '${(values['weightedCentroidMedianErrorKm']! as double).toStringAsFixed(2)} km |',
    );
  }
  return buffer.toString();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

void _writeJson(File file, Map<String, Object?> value) {
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}
