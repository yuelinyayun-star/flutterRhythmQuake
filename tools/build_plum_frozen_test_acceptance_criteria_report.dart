import 'dart:convert';
import 'dart:io';

const _defaultOperatingPointReportPath =
    '.dart_tool/plum_operating_point_acceptance/report.json';
const _defaultOutputPath =
    '.dart_tool/plum_frozen_test_acceptance_criteria/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_frozen_test_acceptance_criteria.generated.md';

const _selectedCandidateId = 'plum_like_r30_d0_50';
const _selectedMaxMethodId = 'max_jma_style_plum_like_r30_d0_50';
const _selectedReplayKey = 'r30_d0.50';

void main(List<String> args) {
  final operatingPointReportPath =
      _argument(args, '--operating-point-report') ??
      _defaultOperatingPointReportPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumFrozenTestAcceptanceCriteriaReportJson(
    operatingPointReportPath: operatingPointReportPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumFrozenTestAcceptanceCriteriaMarkdown(report));

  stdout.writeln('wrote PLUM frozen-test acceptance criteria report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumFrozenTestAcceptanceCriteriaReportJson({
  String operatingPointReportPath = _defaultOperatingPointReportPath,
}) {
  final errors = <String>[];
  final warnings = <String>[];
  final sourceFile = File(operatingPointReportPath);
  if (!sourceFile.existsSync()) {
    errors.add('operating_point_report_missing:$operatingPointReportPath');
    return _emptyReport(
      errors: errors,
      warnings: warnings,
      operatingPointReportPath: operatingPointReportPath,
    );
  }

  final operatingPointReport =
      jsonDecode(sourceFile.readAsStringSync()) as Map<String, Object?>;
  if (operatingPointReport['schemaVersion'] !=
      'plum_operating_point_acceptance_v1') {
    errors.add(
      'invalid_operating_point_schema:'
      '${operatingPointReport['schemaVersion']}',
    );
  }
  if (operatingPointReport['status'] != 'pass') {
    errors.add('operating_point_report_not_pass');
  }
  final policy = _map(operatingPointReport['policy']);
  if (policy['frozenTestEvaluated'] != false) {
    errors.add('operating_point_report_evaluated_frozen_test');
  }
  if (policy['productionReady'] != false ||
      policy['productionUiConnected'] != false ||
      policy['selectedForProduction'] != false) {
    errors.add('operating_point_report_touched_production_boundary');
  }
  final recommended = operatingPointReport['recommendedDiagnosticCandidate']
      ?.toString();
  if (recommended != _selectedCandidateId) {
    errors.add('unexpected_recommended_candidate:$recommended');
  }

  final candidate = _candidate(operatingPointReport, _selectedCandidateId);
  if (candidate.isEmpty) {
    errors.add('selected_candidate_missing:$_selectedCandidateId');
  } else {
    if (candidate['acceptanceStatus'] != 'pass') {
      errors.add(
        'selected_candidate_not_pass:${candidate['acceptanceStatus']}',
      );
    }
    if (candidate['maxMethodId'] != _selectedMaxMethodId) {
      errors.add('selected_candidate_max_method_mismatch');
    }
    if (candidate['replayKey'] != _selectedReplayKey) {
      errors.add('selected_candidate_replay_key_mismatch');
    }
  }

  final replayShindo5ActualSparse =
      _number(_map(candidate['replayShindo5Minus'])['recall']) != null;
  if (replayShindo5ActualSparse) {
    warnings.add('replay_shindo5_minus_sparse_keep_as_watch_metric');
  }

  return {
    'schemaVersion': 'plum_frozen_test_acceptance_criteria_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': const {
      'scope': 'criteria_only_before_frozen_test',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'productionUiConnected': false,
      'selectedForProduction': false,
      'rawIntensityFieldMutated': false,
      'sourceEstimationCoordinateSwitchAllowed': false,
    },
    'inputs': {'operatingPointReportPath': operatingPointReportPath},
    'selectedOperatingPoint': const {
      'candidateId': _selectedCandidateId,
      'maxMethodId': _selectedMaxMethodId,
      'replayKey': _selectedReplayKey,
      'radiusKm': 30.0,
      'dampingPer10Km': 0.50,
      'minimumEvidenceCount': 1,
      'surfaceInputOnly': true,
      'sourceIndependentPlumBranch': true,
    },
    'preconditions': const {
      'operatingPointAcceptanceReportStatus': 'pass',
      'recommendedDiagnosticCandidate': _selectedCandidateId,
      'candidateAcceptanceStatus': 'pass',
      'realReplayInputLayer': 'jma_s',
      'freezeCandidateParametersBeforeEvaluation': true,
      'doNotTuneAfterFrozenResult': true,
    },
    'syntheticRevealFrozenCriteria': const {
      'methodId': _selectedMaxMethodId,
      'maxClassMaeMax': 0.50,
      'maxClassUnderestimateRateMax': 0.25,
      'maxClassWithinOneAccuracyMin': 0.94,
      'shindo4PrecisionMin': 0.52,
      'shindo4RecallMin': 0.68,
      'shindo4F1Min': 0.60,
      'shindo5MinusPrecisionMin': 0.52,
      'shindo5MinusRecallMin': 0.40,
      'shindo5MinusF1Min': 0.48,
    },
    'realReplayFrozenCriteria': const {
      'replayKey': _selectedReplayKey,
      'minimumCaseCount': 7,
      'minimumDecodedFrameCount': 1000,
      'minimumShindo4ActualStations': 20,
      'shindo4RecallMin': 0.55,
      'shindo4FalseAlarmReductionMin': 0.25,
      'shindo4FalseAlarmRatioMax': 0.50,
      'shindo5Minus': 'watch_metric_until_actual_station_count_reaches_10',
      'minimumMedianLeadSeconds': 0.0,
    },
    'decision': const {
      'readyToRunFrozenEvaluation': true,
      'advanceToProduction': false,
      'nextAction': 'run_plum_frozen_test_evaluation_once',
    },
    'warnings': warnings,
    'errors': errors,
  };
}

String plumFrozenTestAcceptanceCriteriaMarkdown(Map<String, Object?> report) {
  final selected = _map(report['selectedOperatingPoint']);
  final synthetic = _map(report['syntheticRevealFrozenCriteria']);
  final replay = _map(report['realReplayFrozenCriteria']);
  final decision = _map(report['decision']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Frozen-Test Acceptance Criteria')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Scope: `criteria_only_before_frozen_test`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Production UI connected: `false`')
    ..writeln()
    ..writeln('## Selected Operating Point')
    ..writeln()
    ..writeln('| Field | Value |')
    ..writeln('| --- | ---: |')
    ..writeln('| Candidate | `${selected['candidateId']}` |')
    ..writeln('| Combined method | `${selected['maxMethodId']}` |')
    ..writeln('| Replay key | `${selected['replayKey']}` |')
    ..writeln('| Radius | `${selected['radiusKm']} km` |')
    ..writeln('| Damping | `${selected['dampingPer10Km']} shindo / 10 km` |')
    ..writeln('| Minimum evidence | `${selected['minimumEvidenceCount']}` |')
    ..writeln()
    ..writeln('## Synthetic-Reveal Frozen Criteria')
    ..writeln()
    ..writeln('| Metric | Required |')
    ..writeln('| --- | ---: |')
    ..writeln('| Max-class MAE | <= `${synthetic['maxClassMaeMax']}` |')
    ..writeln(
      '| Max-class underestimation | <= `${_pct(synthetic['maxClassUnderestimateRateMax'])}` |',
    )
    ..writeln(
      '| Max-class within one | >= `${_pct(synthetic['maxClassWithinOneAccuracyMin'])}` |',
    )
    ..writeln(
      '| Shindo4 precision | >= `${_pct(synthetic['shindo4PrecisionMin'])}` |',
    )
    ..writeln(
      '| Shindo4 recall | >= `${_pct(synthetic['shindo4RecallMin'])}` |',
    )
    ..writeln('| Shindo4 F1 | >= `${_pct(synthetic['shindo4F1Min'])}` |')
    ..writeln(
      '| Shindo5- precision | >= `${_pct(synthetic['shindo5MinusPrecisionMin'])}` |',
    )
    ..writeln(
      '| Shindo5- recall | >= `${_pct(synthetic['shindo5MinusRecallMin'])}` |',
    )
    ..writeln('| Shindo5- F1 | >= `${_pct(synthetic['shindo5MinusF1Min'])}` |')
    ..writeln()
    ..writeln('## Real-Replay Frozen Criteria')
    ..writeln()
    ..writeln('| Metric | Required |')
    ..writeln('| --- | ---: |')
    ..writeln('| Minimum cases | `${replay['minimumCaseCount']}` |')
    ..writeln(
      '| Minimum decoded frames | `${replay['minimumDecodedFrameCount']}` |',
    )
    ..writeln(
      '| Minimum shindo4 actual stations | `${replay['minimumShindo4ActualStations']}` |',
    )
    ..writeln('| Shindo4 recall | >= `${_pct(replay['shindo4RecallMin'])}` |')
    ..writeln(
      '| Shindo4 false-alarm reduction | >= `${_pct(replay['shindo4FalseAlarmReductionMin'])}` |',
    )
    ..writeln(
      '| Shindo4 false-alarm ratio | <= `${_pct(replay['shindo4FalseAlarmRatioMax'])}` |',
    )
    ..writeln('| Median lead | >= `${replay['minimumMedianLeadSeconds']} s` |')
    ..writeln('| Shindo5- | `${replay['shindo5Minus']}` |')
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Ready to run frozen evaluation: `${decision['readyToRunFrozenEvaluation']}`',
    )
    ..writeln('- Advance to production: `${decision['advanceToProduction']}`')
    ..writeln('- Next action: `${decision['nextAction']}`')
    ..writeln()
    ..writeln(
      'These criteria freeze the diagnostic operating point before frozen-test '
      'evaluation. They do not authorize production UI, notifications or '
      'warning wording.',
    )
    ..writeln();
  return buffer.toString();
}

Map<String, Object?> _candidate(Map<String, Object?> report, String id) {
  for (final raw in _list(report['candidates'])) {
    final row = _map(raw);
    if (row['candidateId'] == id) return row;
  }
  return const {};
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required List<String> warnings,
  required String operatingPointReportPath,
}) => {
  'schemaVersion': 'plum_frozen_test_acceptance_criteria_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'policy': const {
    'scope': 'criteria_only_before_frozen_test',
    'frozenTestEvaluated': false,
    'productionReady': false,
    'productionUiConnected': false,
  },
  'inputs': {'operatingPointReportPath': operatingPointReportPath},
  'selectedOperatingPoint': const {},
  'preconditions': const {},
  'syntheticRevealFrozenCriteria': const {},
  'realReplayFrozenCriteria': const {},
  'decision': const {
    'readyToRunFrozenEvaluation': false,
    'advanceToProduction': false,
  },
  'warnings': warnings,
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

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _pct(Object? value) {
  final number = _number(value);
  return number == null ? '-' : '${(number * 100).toStringAsFixed(1)}%';
}
