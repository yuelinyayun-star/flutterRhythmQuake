import 'dart:convert';
import 'dart:io';

const _defaultCombinedPath =
    '.dart_tool/combined_intensity_prediction/report.json';
const _defaultReplayPath = '.dart_tool/plum_like_replay_leadtime/report.json';
const _defaultOutputPath =
    '.dart_tool/plum_operating_point_acceptance/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_operating_point_acceptance.generated.md';

const _minimumReplayShindo4Recall = 0.60;
const _minimumReplayShindo4FalseAlarmReduction = 0.25;
const _minimumCombinedShindo4Recall = 0.70;
const _minimumReplayCaseCount = 7;
const _minimumReplayDecodedFrameCount = 1000;

const _candidates = [
  _CandidateConfig(
    id: 'plum_like_r20_d0_50',
    maxMethodId: 'max_jma_style_plum_like_r20_d0_50',
    replayKey: 'r20_d0.50',
  ),
  _CandidateConfig(
    id: 'plum_like_r30_d0_50',
    maxMethodId: 'max_jma_style_plum_like_r30_d0_50',
    replayKey: 'r30_d0.50',
  ),
];

const _baseline = _CandidateConfig(
  id: 'plum_like',
  maxMethodId: 'max_jma_style_plum_like',
  replayKey: 'r30_d0.25_baseline',
);

void main(List<String> args) {
  final combinedPath = _argument(args, '--combined') ?? _defaultCombinedPath;
  final replayPath = _argument(args, '--replay') ?? _defaultReplayPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildPlumOperatingPointAcceptanceReportJson(
    combinedReportPath: combinedPath,
    replayReportPath: replayPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumOperatingPointAcceptanceMarkdown(report));

  stdout.writeln('wrote PLUM operating-point acceptance report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumOperatingPointAcceptanceReportJson({
  String combinedReportPath = _defaultCombinedPath,
  String replayReportPath = _defaultReplayPath,
}) {
  final errors = <String>[];
  final combinedFile = File(combinedReportPath);
  final replayFile = File(replayReportPath);
  if (!combinedFile.existsSync()) {
    errors.add('combined_report_missing:$combinedReportPath');
  }
  if (!replayFile.existsSync()) {
    errors.add('replay_report_missing:$replayReportPath');
  }
  if (errors.isNotEmpty) {
    return _emptyReport(
      errors: errors,
      combinedReportPath: combinedReportPath,
      replayReportPath: replayReportPath,
    );
  }

  final combined =
      jsonDecode(combinedFile.readAsStringSync()) as Map<String, Object?>;
  final replay =
      jsonDecode(replayFile.readAsStringSync()) as Map<String, Object?>;
  if (combined['status'] != 'pass') {
    errors.add('combined_report_not_pass:${combined['status']}');
  }
  if (replay['status'] != 'pass') {
    errors.add('replay_report_not_pass:${replay['status']}');
  }

  final baseline = _row(
    config: _baseline,
    combined: combined,
    replay: replay,
    replayCoverageOk: _replayCoverageOk(replay),
    baselineReplayShindo4FalseAlarms: null,
    baselineCombinedShindo4F1: null,
  );
  final candidateRows = [
    for (final config in _candidates)
      _row(
        config: config,
        combined: combined,
        replay: replay,
        replayCoverageOk: _replayCoverageOk(replay),
        baselineReplayShindo4FalseAlarms: _intValue(
          _map(baseline['replayShindo4'])['falseAlarmStations'],
        ),
        baselineCombinedShindo4F1: _number(
          _map(baseline['combinedShindo4'])['f1'],
        ),
      ),
  ];
  final passing =
      candidateRows
          .where((row) => row['acceptanceStatus'] == 'pass')
          .toList(growable: false)
        ..sort((left, right) {
          final f1Order = _number(
            _map(right['combinedShindo4'])['f1'],
          )!.compareTo(_number(_map(left['combinedShindo4'])['f1'])!);
          if (f1Order != 0) return f1Order;
          return _number(
            _map(right['replayShindo4'])['recall'],
          )!.compareTo(_number(_map(left['replayShindo4'])['recall'])!);
        });
  final recommended = passing.isEmpty ? null : passing.first['candidateId'];

  return {
    'schemaVersion': 'plum_operating_point_acceptance_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': const {
      'split': 'diagnostic_validation_and_replay',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'productionUiConnected': false,
      'selectedForProduction': false,
      'sourceIndependentPlumBranch': true,
    },
    'inputs': {
      'combinedReportPath': combinedReportPath,
      'replayReportPath': replayReportPath,
    },
    'criteria': const {
      'minimumReplayShindo4Recall': _minimumReplayShindo4Recall,
      'minimumReplayShindo4FalseAlarmReduction':
          _minimumReplayShindo4FalseAlarmReduction,
      'minimumCombinedShindo4Recall': _minimumCombinedShindo4Recall,
      'minimumCombinedShindo4F1': 'baseline_combined_shindo4_f1',
      'minimumReplayCaseCount': _minimumReplayCaseCount,
      'minimumReplayDecodedFrameCount': _minimumReplayDecodedFrameCount,
    },
    'baseline': baseline,
    'candidates': candidateRows,
    'recommendedDiagnosticCandidate': recommended,
    'decision': {
      'advanceToFrozenTest': false,
      'advanceToProduction': false,
      'nextAction': recommended == null
          ? 'expand_replay_or_revise_operating_point'
          : 'write_frozen_test_acceptance_criteria_for_$recommended',
    },
    'errors': errors,
  };
}

Map<String, Object?> _row({
  required _CandidateConfig config,
  required Map<String, Object?> combined,
  required Map<String, Object?> replay,
  required bool replayCoverageOk,
  required int? baselineReplayShindo4FalseAlarms,
  required double? baselineCombinedShindo4F1,
}) {
  final replayShindo4 = _replayThreshold(replay, config.replayKey, 'shindo4');
  final replayShindo5 = _replayThreshold(replay, config.replayKey, 'shindo5-');
  final combinedShindo4 = _combinedThreshold(
    combined,
    config.maxMethodId,
    'shindo4',
  );
  final combinedShindo5 = _combinedThreshold(
    combined,
    config.maxMethodId,
    'shindo5-',
  );
  final currentFalseAlarms = _intValue(replayShindo4['falseAlarmStations']);
  final falseAlarmReduction =
      baselineReplayShindo4FalseAlarms == null ||
          baselineReplayShindo4FalseAlarms == 0
      ? 0.0
      : (baselineReplayShindo4FalseAlarms - currentFalseAlarms) /
            baselineReplayShindo4FalseAlarms;
  final isBaseline = baselineReplayShindo4FalseAlarms == null;
  final checks = {
    'replayShindo4Recall': isBaseline
        ? 'baseline'
        : _number(replayShindo4['recall'])! >= _minimumReplayShindo4Recall,
    'replayShindo4FalseAlarmReduction': isBaseline
        ? 'baseline'
        : falseAlarmReduction >= _minimumReplayShindo4FalseAlarmReduction,
    'combinedShindo4Recall': isBaseline
        ? 'baseline'
        : _number(combinedShindo4['recall'])! >= _minimumCombinedShindo4Recall,
    'combinedShindo4F1': isBaseline
        ? 'baseline'
        : _number(combinedShindo4['f1'])! >= baselineCombinedShindo4F1!,
    'replayCoverage': isBaseline ? 'baseline' : replayCoverageOk,
  };
  final passed = checks.values.every(
    (value) => value == true || value == 'baseline',
  );
  return {
    'candidateId': config.id,
    'maxMethodId': config.maxMethodId,
    'replayKey': config.replayKey,
    'acceptanceStatus': isBaseline ? 'baseline' : (passed ? 'pass' : 'warn'),
    'replayShindo4FalseAlarmReduction': falseAlarmReduction,
    'checks': checks,
    'replayShindo4': replayShindo4,
    'replayShindo5Minus': replayShindo5,
    'combinedShindo4': combinedShindo4,
    'combinedShindo5Minus': combinedShindo5,
  };
}

bool _replayCoverageOk(Map<String, Object?> replay) {
  final summary = _map(replay['summary']);
  return _intValue(summary['caseCount']) >= _minimumReplayCaseCount &&
      _intValue(summary['decodedFrameCount']) >=
          _minimumReplayDecodedFrameCount;
}

Map<String, Object?> _replayThreshold(
  Map<String, Object?> report,
  String key,
  String threshold,
) {
  final row = _map(_map(_map(report['tuningGridComparison'])[key])[threshold]);
  return {
    'recall': _number(row['stationRecall']) ?? 0.0,
    'falseAlarmStations': _intValue(row['falseAlarmStationCount']),
    'falseAlarmRatio': _number(row['stationFalseAlarmRatio']) ?? 0.0,
  };
}

Map<String, Object?> _combinedThreshold(
  Map<String, Object?> report,
  String method,
  String threshold,
) {
  final row = _map(
    _map(_map(_map(report['methods'])[method])['thresholds'])[threshold],
  );
  return {
    'precision': _number(row['precision']) ?? 0.0,
    'recall': _number(row['recall']) ?? 0.0,
    'f1': _number(row['f1']) ?? 0.0,
  };
}

String plumOperatingPointAcceptanceMarkdown(Map<String, Object?> report) {
  final baseline = _map(report['baseline']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Operating-Point Acceptance Diagnostic')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Production UI connected: `false`')
    ..writeln(
      '- Recommended diagnostic candidate: '
      '`${report['recommendedDiagnosticCandidate'] ?? 'none'}`',
    )
    ..writeln()
    ..writeln('## Criteria')
    ..writeln()
    ..writeln(
      '- Replay `shindo4` recall must be >= '
      '`${_pct(_minimumReplayShindo4Recall)}`.',
    )
    ..writeln(
      '- Replay `shindo4` false-alarm stations must drop by >= '
      '`${_pct(_minimumReplayShindo4FalseAlarmReduction)}` versus baseline.',
    )
    ..writeln(
      '- Combined synthetic-reveal `shindo4` recall must be >= '
      '`${_pct(_minimumCombinedShindo4Recall)}`.',
    )
    ..writeln(
      '- Combined synthetic-reveal `shindo4` F1 must not fall below the '
      'baseline combined branch.',
    )
    ..writeln(
      '- Replay coverage must include at least `$_minimumReplayCaseCount` '
      'complete cases and `$_minimumReplayDecodedFrameCount` decoded frames.',
    )
    ..writeln()
    ..writeln('## Baseline')
    ..writeln()
    ..writeln(_candidateLine(baseline))
    ..writeln()
    ..writeln('## Candidates')
    ..writeln()
    ..writeln(
      '| Candidate | Status | Replay shindo4 recall | Replay shindo4 false alarms | Replay false-alarm reduction | Combined shindo4 P/R/F1 | Combined shindo5- P/R/F1 |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | ---: |');
  for (final raw in _list(report['candidates'])) {
    final row = _map(raw);
    final replay = _map(row['replayShindo4']);
    final shindo4 = _map(row['combinedShindo4']);
    final shindo5 = _map(row['combinedShindo5Minus']);
    buffer.writeln(
      '| `${row['candidateId']}` | `${row['acceptanceStatus']}` | '
      '${_pct(replay['recall'])} | ${replay['falseAlarmStations']} | '
      '${_pct(row['replayShindo4FalseAlarmReduction'])} | '
      '${_triplet(shindo4)} | ${_triplet(shindo5)} |',
    );
  }
  final decision = _map(report['decision']);
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Advance to frozen test: `${decision['advanceToFrozenTest']}`')
    ..writeln('- Advance to production: `${decision['advanceToProduction']}`')
    ..writeln('- Next action: `${decision['nextAction']}`')
    ..writeln()
    ..writeln(
      'This report is diagnostic-only and must not drive production UI, '
      'notifications or warning wording.',
    )
    ..writeln();
  return buffer.toString();
}

String _candidateLine(Map<String, Object?> row) {
  final replay = _map(row['replayShindo4']);
  final combined = _map(row['combinedShindo4']);
  return '- `${row['candidateId']}` replay shindo4 recall '
      '`${_pct(replay['recall'])}`, false alarms '
      '`${replay['falseAlarmStations']}`, combined shindo4 P/R/F1 '
      '`${_triplet(combined)}`.';
}

String _triplet(Map<String, Object?> row) =>
    '${_pct(row['precision'])} / ${_pct(row['recall'])} / ${_pct(row['f1'])}';

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String combinedReportPath,
  required String replayReportPath,
}) => {
  'schemaVersion': 'plum_operating_point_acceptance_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'inputs': {
    'combinedReportPath': combinedReportPath,
    'replayReportPath': replayReportPath,
  },
  'baseline': const {},
  'candidates': const [],
  'recommendedDiagnosticCandidate': null,
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

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _pct(Object? value) {
  final number = _number(value);
  return number == null ? '-' : '${(number * 100).toStringAsFixed(1)}%';
}

class _CandidateConfig {
  final String id;
  final String maxMethodId;
  final String replayKey;

  const _CandidateConfig({
    required this.id,
    required this.maxMethodId,
    required this.replayKey,
  });
}
