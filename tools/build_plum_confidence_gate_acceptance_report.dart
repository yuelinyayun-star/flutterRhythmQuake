import 'dart:convert';
import 'dart:io';

const _defaultConfidenceReportPath =
    '.dart_tool/plum_confidence_gate/report.json';
const _defaultReplayReportPath =
    '.dart_tool/plum_like_replay_leadtime/report.json';
const _defaultOutputPath =
    '.dart_tool/plum_confidence_gate_acceptance/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_confidence_gate_acceptance.generated.md';
const _minimumReplayCaseCount = 7;
const _minimumReplayDecodedFrameCount = 1000;

void main(List<String> args) {
  final confidencePath =
      _argument(args, '--confidence-report') ?? _defaultConfidenceReportPath;
  final replayPath = _argument(args, '--replay') ?? _defaultReplayReportPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumConfidenceGateAcceptanceReportJson(
    confidenceReportPath: confidencePath,
    replayReportPath: replayPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumConfidenceGateAcceptanceMarkdown(report));

  stdout.writeln('wrote PLUM confidence gate acceptance report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumConfidenceGateAcceptanceReportJson({
  String confidenceReportPath = _defaultConfidenceReportPath,
  String replayReportPath = _defaultReplayReportPath,
}) {
  final errors = <String>[];
  final confidenceFile = File(confidenceReportPath);
  final replayFile = File(replayReportPath);
  if (!confidenceFile.existsSync()) {
    errors.add('confidence_report_missing:$confidenceReportPath');
  }
  if (!replayFile.existsSync()) {
    errors.add('replay_report_missing:$replayReportPath');
  }
  if (errors.isNotEmpty) {
    return _emptyReport(
      errors: errors,
      confidenceReportPath: confidenceReportPath,
      replayReportPath: replayReportPath,
    );
  }

  final confidence =
      jsonDecode(confidenceFile.readAsStringSync()) as Map<String, Object?>;
  final replay =
      jsonDecode(replayFile.readAsStringSync()) as Map<String, Object?>;
  if (confidence['schemaVersion'] != 'plum_confidence_gate_report_v1') {
    errors.add('invalid_confidence_schema:${confidence['schemaVersion']}');
  }
  if (replay['schemaVersion'] != 'plum_like_replay_leadtime_report_v1') {
    errors.add('invalid_replay_schema:${replay['schemaVersion']}');
  }
  final confidencePolicy = _map(confidence['policy']);
  final replayPolicy = _map(replay['policy']);
  if (confidencePolicy['rawIntensityFieldMutated'] != false) {
    errors.add('confidence_gate_mutated_raw_intensity');
  }
  if (confidencePolicy['frozenTestEvaluated'] != false ||
      replayPolicy['frozenTestEvaluated'] != false) {
    errors.add('frozen_test_was_evaluated');
  }

  final recommended = confidence['recommendedForReplayValidation']?.toString();
  final replayLabel = _replayLabelForGate(recommended);
  final validationBaseline = _evaluation(confidence, 'baseline_raw_threshold');
  final validationGate = _evaluation(confidence, recommended);
  final replayGrid = _map(replay['tuningGridComparison']);
  final replayBaseline = _map(_map(replayGrid['r30_d0.50'])['shindo4']);
  final replayGate = _map(_map(replayGrid[replayLabel])['shindo4']);
  final decision = _Decision.evaluate(
    validationBaseline: validationBaseline,
    validationGate: validationGate,
    replayBaseline: replayBaseline,
    replayGate: replayGate,
    replayReport: replay,
    errors: errors,
  );

  return {
    'schemaVersion': 'plum_confidence_gate_acceptance_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'confidenceReportPath': confidenceReportPath,
    'replayReportPath': replayReportPath,
    'policy': const {
      'split': 'validation_plus_diagnostic_replay',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'productionUiConnected': false,
      'rawIntensityFieldMutated': false,
      'acceptanceScope': 'manual_triage_before_any_frozen_criteria',
    },
    'criteria': _criteriaJson,
    'recommendedGate': recommended,
    'replayGridLabel': replayLabel,
    'decision': decision.toJson(),
    'errors': errors,
  };
}

String plumConfidenceGateAcceptanceMarkdown(Map<String, Object?> report) {
  final decision = _map(report['decision']);
  final validation = _map(decision['validation']);
  final replay = _map(decision['replay']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Confidence Gate Acceptance Triage')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Raw intensity field mutated: `false`')
    ..writeln('- Recommended gate: `${report['recommendedGate'] ?? 'none'}`')
    ..writeln('- Replay grid label: `${report['replayGridLabel'] ?? 'none'}`')
    ..writeln('- Decision status: `${decision['status']}`')
    ..writeln(
      '- Ready for frozen criteria: `${decision['readyForFrozenCriteria']}`',
    )
    ..writeln(
      '- Requires manual decision: `${decision['requiresManualDecision']}`',
    )
    ..writeln()
    ..writeln('## Validation')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('| --- | ---: |')
    ..writeln(
      '| Shindo4 precision gain | ${_pct(validation['precisionGain'])} |',
    )
    ..writeln('| Shindo4 recall loss | ${_pct(validation['recallLoss'])} |')
    ..writeln('| Shindo4 F1 gain | ${_pct(validation['f1Gain'])} |')
    ..writeln()
    ..writeln('## Replay')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('| --- | ---: |')
    ..writeln('| Baseline shindo4 recall | ${_pct(replay['baselineRecall'])} |')
    ..writeln('| Gate shindo4 recall | ${_pct(replay['gateRecall'])} |')
    ..writeln('| Baseline false alarms | ${replay['baselineFalseAlarms']} |')
    ..writeln('| Gate false alarms | ${replay['gateFalseAlarms']} |')
    ..writeln(
      '| False-alarm reduction | ${_pct(replay['falseAlarmReduction'])} |',
    )
    ..writeln()
    ..writeln('## Notes')
    ..writeln()
    ..writeln('| Note |')
    ..writeln('| --- |');
  for (final note in _list(decision['notes'])) {
    buffer.writeln('| `$note` |');
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This gate can only affect confidence/wording experiments; raw predicted '
      'intensity remains unchanged.',
    )
    ..writeln(
      '- Do not open frozen test or production wiring from this triage report.',
    )
    ..writeln();
  return buffer.toString();
}

class _Decision {
  final String status;
  final bool readyForFrozenCriteria;
  final bool requiresManualDecision;
  final Map<String, Object?> validation;
  final Map<String, Object?> replay;
  final List<String> notes;

  const _Decision({
    required this.status,
    required this.readyForFrozenCriteria,
    required this.requiresManualDecision,
    required this.validation,
    required this.replay,
    required this.notes,
  });

  factory _Decision.evaluate({
    required Map<String, Object?> validationBaseline,
    required Map<String, Object?> validationGate,
    required Map<String, Object?> replayBaseline,
    required Map<String, Object?> replayGate,
    required Map<String, Object?> replayReport,
    required List<String> errors,
  }) {
    final base4 = _map(_map(validationBaseline['thresholds'])['shindo4']);
    final gate4 = _map(_map(validationGate['thresholds'])['shindo4']);
    final precisionGain =
        _number(gate4['precision']) - _number(base4['precision']);
    final recallLoss = _number(base4['recall']) - _number(gate4['recall']);
    final f1Gain = _number(gate4['f1']) - _number(base4['f1']);
    final baselineFalseAlarms = _number(
      replayBaseline['falseAlarmStationCount'],
    );
    final gateFalseAlarms = _number(replayGate['falseAlarmStationCount']);
    final falseAlarmReduction = baselineFalseAlarms == 0
        ? 0.0
        : (baselineFalseAlarms - gateFalseAlarms) / baselineFalseAlarms;
    final replayRecall = _number(replayGate['stationRecall']);
    final notes = <String>[];
    if (precisionGain < _criteria.minimumValidationPrecisionGain) {
      notes.add('validation_precision_gain_below_minimum');
    }
    if (f1Gain < _criteria.minimumValidationF1Gain) {
      notes.add('validation_f1_gain_below_minimum');
    }
    if (recallLoss > _criteria.maximumValidationRecallLoss) {
      notes.add('validation_recall_loss_above_limit');
    }
    if (falseAlarmReduction < _criteria.minimumReplayFalseAlarmReduction) {
      notes.add('replay_false_alarm_reduction_below_minimum');
    }
    if (replayRecall < _criteria.minimumReplayRecall) {
      notes.add('replay_recall_below_minimum');
    } else if (replayRecall < _criteria.preferredReplayRecall) {
      notes.add('replay_recall_below_preferred_manual_decision_required');
    }
    if (!_replayCoverageOk(replayReport)) {
      notes.add('replay_coverage_below_minimum');
    }
    final failed = notes.any(
      (note) =>
          note.endsWith('below_minimum') ||
          note == 'validation_recall_loss_above_limit',
    );
    final manual = notes.any((note) => note.contains('manual_decision'));
    return _Decision(
      status: errors.isNotEmpty || failed
          ? 'fail'
          : manual
          ? 'warn'
          : 'pass',
      readyForFrozenCriteria: false,
      requiresManualDecision: manual,
      validation: {
        'precisionGain': precisionGain,
        'recallLoss': recallLoss,
        'f1Gain': f1Gain,
      },
      replay: {
        'baselineRecall': _number(replayBaseline['stationRecall']),
        'gateRecall': replayRecall,
        'baselineFalseAlarms': baselineFalseAlarms.toInt(),
        'gateFalseAlarms': gateFalseAlarms.toInt(),
        'falseAlarmReduction': falseAlarmReduction,
      },
      notes: notes,
    );
  }

  Map<String, Object?> toJson() => {
    'status': status,
    'readyForFrozenCriteria': readyForFrozenCriteria,
    'requiresManualDecision': requiresManualDecision,
    'validation': validation,
    'replay': replay,
    'notes': notes,
  };
}

const _criteria = _Criteria(
  minimumValidationPrecisionGain: 0.10,
  minimumValidationF1Gain: 0.00,
  maximumValidationRecallLoss: 0.15,
  minimumReplayFalseAlarmReduction: 0.15,
  minimumReplayRecall: 0.55,
  preferredReplayRecall: 0.60,
);

Map<String, Object?> get _criteriaJson => {
  'minimumValidationPrecisionGain': _criteria.minimumValidationPrecisionGain,
  'minimumValidationF1Gain': _criteria.minimumValidationF1Gain,
  'maximumValidationRecallLoss': _criteria.maximumValidationRecallLoss,
  'minimumReplayFalseAlarmReduction':
      _criteria.minimumReplayFalseAlarmReduction,
  'minimumReplayRecall': _criteria.minimumReplayRecall,
  'preferredReplayRecall': _criteria.preferredReplayRecall,
  'minimumReplayCaseCount': _minimumReplayCaseCount,
  'minimumReplayDecodedFrameCount': _minimumReplayDecodedFrameCount,
};

bool _replayCoverageOk(Map<String, Object?> replay) {
  final summary = _map(replay['summary']);
  return _intValue(summary['caseCount']) >= _minimumReplayCaseCount &&
      _intValue(summary['decodedFrameCount']) >=
          _minimumReplayDecodedFrameCount;
}

class _Criteria {
  final double minimumValidationPrecisionGain;
  final double minimumValidationF1Gain;
  final double maximumValidationRecallLoss;
  final double minimumReplayFalseAlarmReduction;
  final double minimumReplayRecall;
  final double preferredReplayRecall;

  const _Criteria({
    required this.minimumValidationPrecisionGain,
    required this.minimumValidationF1Gain,
    required this.maximumValidationRecallLoss,
    required this.minimumReplayFalseAlarmReduction,
    required this.minimumReplayRecall,
    required this.preferredReplayRecall,
  });
}

Map<String, Object?> _evaluation(Map<String, Object?> report, String? gateId) {
  if (gateId == null) return const {};
  for (final raw in _list(report['evaluations'])) {
    final entry = _map(raw);
    if (entry['gateId'] == gateId) return entry;
  }
  return const {};
}

String? _replayLabelForGate(String? gateId) {
  return switch (gateId) {
    'plum_r20_d0_50_only' => 'r20_d0.50',
    'jma_or_plum_r20_d0_50' => 'r20_d0.50',
    'jma_or_plum_r30_d0_75' => 'r30_d0.75',
    'two_of_jma_r20_d0_50_r30_d0_75' => 'r20_d0.50',
    _ => null,
  };
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String confidenceReportPath,
  required String replayReportPath,
}) => {
  'schemaVersion': 'plum_confidence_gate_acceptance_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'confidenceReportPath': confidenceReportPath,
  'replayReportPath': replayReportPath,
  'policy': const {
    'frozenTestEvaluated': false,
    'productionReady': false,
    'productionUiConnected': false,
    'rawIntensityFieldMutated': false,
  },
  'decision': const {},
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

String _pct(Object? value) => '${(_number(value) * 100).toStringAsFixed(1)}%';
