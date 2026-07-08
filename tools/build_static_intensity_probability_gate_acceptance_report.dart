import 'dart:convert';
import 'dart:io';

const _defaultGateReportPath =
    '.dart_tool/static_intensity_probability_gate/report.json';
const _defaultOutputPath =
    '.dart_tool/static_intensity_probability_gate_acceptance/report.json';
const _defaultMarkdownPath =
    'docs/baselines/static_intensity_probability_gate_acceptance.generated.md';

void main(List<String> args) {
  final gateReportPath =
      _argument(args, '--gate-report') ?? _defaultGateReportPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildStaticIntensityProbabilityGateAcceptanceJson(
    gateReportPath: gateReportPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    staticIntensityProbabilityGateAcceptanceMarkdown(report),
  );

  stdout.writeln('wrote static intensity probability gate acceptance report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildStaticIntensityProbabilityGateAcceptanceJson({
  String gateReportPath = _defaultGateReportPath,
}) {
  final errors = <String>[];
  final gateFile = File(gateReportPath);
  if (!gateFile.existsSync()) {
    errors.add('probability_gate_report_missing:$gateReportPath');
    return _emptyReport(errors: errors, gateReportPath: gateReportPath);
  }

  final gateReport =
      jsonDecode(gateFile.readAsStringSync()) as Map<String, Object?>;
  if (gateReport['schemaVersion'] != 'static_intensity_probability_gate_v1') {
    errors.add('invalid_gate_schema:${gateReport['schemaVersion']}');
  }
  final policy = _map(gateReport['policy']);
  if (policy['rawIntensityFieldMutated'] != false) {
    errors.add('raw_intensity_field_was_mutated');
  }
  if (policy['frozenTestEvaluated'] != false) {
    errors.add('frozen_test_was_evaluated');
  }

  final decisions = [
    for (final raw in _list(gateReport['thresholds']))
      _AcceptanceDecision.fromThreshold(_map(raw)),
  ];
  final relevant = decisions
      .where(
        (decision) =>
            decision.label == 'shindo4' || decision.label == 'shindo5-',
      )
      .toList(growable: false);
  final failed = relevant
      .where((decision) => decision.status == 'fail')
      .toList();
  final warnings = relevant
      .where((decision) => decision.status == 'warn')
      .toList();
  final status = errors.isNotEmpty || failed.isNotEmpty ? 'fail' : 'pass';

  return {
    'schemaVersion': 'static_intensity_probability_gate_acceptance_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': status,
    'gateReportPath': gateReportPath,
    'policy': const {
      'split': 'validation',
      'frozenTestEvaluated': false,
      'productionReady': false,
      'rawIntensityFieldMutated': false,
      'acceptanceScope': 'validation_acceptance_criteria_only',
    },
    'criteria': _criteriaJson,
    'summary': {
      'relevantThresholds': [for (final item in relevant) item.label],
      'failedRelevantThresholds': [for (final item in failed) item.label],
      'warningRelevantThresholds': [for (final item in warnings) item.label],
      'readyForFrozenTest': status == 'pass' && warnings.isEmpty,
      'requiresManualDecision': warnings.isNotEmpty,
    },
    'thresholds': [for (final decision in decisions) decision.toJson()],
    'errors': errors,
  };
}

String staticIntensityProbabilityGateAcceptanceMarkdown(
  Map<String, Object?> report,
) {
  final summary = _map(report['summary']);
  final buffer = StringBuffer()
    ..writeln('# Static Intensity Probability Gate Acceptance')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Split: `validation`')
    ..writeln('- Frozen test evaluated: `false`')
    ..writeln('- Production ready: `false`')
    ..writeln('- Ready for frozen test: `${summary['readyForFrozenTest']}`')
    ..writeln(
      '- Requires manual decision: `${summary['requiresManualDecision']}`',
    )
    ..writeln()
    ..writeln('## Criteria')
    ..writeln()
    ..writeln('| Criterion | Value |')
    ..writeln('| --- | ---: |')
    ..writeln(
      '| Minimum precision gain | ${_pct(_criteria.minimumPrecisionGain)} |',
    )
    ..writeln('| Minimum F1 gain | ${_pct(_criteria.minimumF1Gain)} |')
    ..writeln('| Maximum recall loss | ${_pct(_criteria.maximumRecallLoss)} |')
    ..writeln(
      '| Maximum false-negative ratio | ${_fmt(_criteria.maximumFalseNegativeRatio)}x |',
    )
    ..writeln()
    ..writeln('## Threshold Decisions')
    ..writeln()
    ..writeln(
      '| Threshold | Status | Precision gain | Recall loss | F1 gain | FN ratio | Notes |',
    )
    ..writeln('| --- | --- | ---: | ---: | ---: | ---: | --- |');
  for (final raw in _list(report['thresholds'])) {
    final row = _map(raw);
    buffer.writeln(
      '| `${row['label']}` | `${row['status']}` | '
      '${_pct(row['precisionGain'])} | ${_pct(row['recallLoss'])} | '
      '${_pct(row['f1Gain'])} | ${_fmt(row['falseNegativeRatio'])}x | '
      '${(row['notes'] as List? ?? const []).join('; ')} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- `shindo4` and `shindo5-` are the production-relevant high-shindo gates.',
    )
    ..writeln(
      '- A `warn` means the gate improves precision/F1 but the recall loss '
      'needs explicit product decision before frozen test.',
    )
    ..writeln(
      '- A `fail` blocks frozen-test evaluation until the validation gate is '
      'changed or acceptance criteria are deliberately revised.',
    )
    ..writeln();
  return buffer.toString();
}

class _AcceptanceDecision {
  final String label;
  final String status;
  final double precisionGain;
  final double recallLoss;
  final double f1Gain;
  final double falseNegativeRatio;
  final List<String> notes;

  const _AcceptanceDecision({
    required this.label,
    required this.status,
    required this.precisionGain,
    required this.recallLoss,
    required this.f1Gain,
    required this.falseNegativeRatio,
    required this.notes,
  });

  factory _AcceptanceDecision.fromThreshold(Map<String, Object?> threshold) {
    final label = threshold['label']?.toString() ?? 'unknown';
    final raw = _map(threshold['rawThreshold']);
    final gate = _map(threshold['probabilityGate']);
    final precisionGain =
        _number(gate['precision']) - _number(raw['precision']);
    final recallLoss = _number(raw['recall']) - _number(gate['recall']);
    final f1Gain = _number(gate['f1']) - _number(raw['f1']);
    final rawFalseNegative = _number(raw['falseNegative']);
    final gateFalseNegative = _number(gate['falseNegative']);
    final falseNegativeRatio = rawFalseNegative == 0
        ? 0.0
        : gateFalseNegative / rawFalseNegative;
    final notes = <String>[];
    if (precisionGain < _criteria.minimumPrecisionGain) {
      notes.add('precision_gain_below_minimum');
    }
    if (f1Gain < _criteria.minimumF1Gain) {
      notes.add('f1_gain_below_minimum');
    }
    if (recallLoss > _criteria.maximumRecallLoss) {
      notes.add('recall_loss_above_limit');
    }
    if (falseNegativeRatio > _criteria.maximumFalseNegativeRatio) {
      notes.add('false_negative_ratio_above_limit');
    }
    final isHighShindo = label == 'shindo4' || label == 'shindo5-';
    String status;
    if (!isHighShindo) {
      status = 'info';
    } else if (precisionGain < _criteria.minimumPrecisionGain ||
        f1Gain < _criteria.minimumF1Gain) {
      status = 'fail';
    } else if (recallLoss > _criteria.maximumRecallLoss ||
        falseNegativeRatio > _criteria.maximumFalseNegativeRatio) {
      status = 'warn';
    } else {
      status = 'pass';
    }
    return _AcceptanceDecision(
      label: label,
      status: status,
      precisionGain: precisionGain,
      recallLoss: recallLoss,
      f1Gain: f1Gain,
      falseNegativeRatio: falseNegativeRatio,
      notes: notes,
    );
  }

  Map<String, Object?> toJson() => {
    'label': label,
    'status': status,
    'precisionGain': precisionGain,
    'recallLoss': recallLoss,
    'f1Gain': f1Gain,
    'falseNegativeRatio': falseNegativeRatio,
    'notes': notes,
  };
}

const _criteria = _AcceptanceCriteria(
  minimumPrecisionGain: 0.10,
  minimumF1Gain: 0.10,
  maximumRecallLoss: 0.18,
  maximumFalseNegativeRatio: 3.0,
);

Map<String, Object?> get _criteriaJson => {
  'minimumPrecisionGain': _criteria.minimumPrecisionGain,
  'minimumF1Gain': _criteria.minimumF1Gain,
  'maximumRecallLoss': _criteria.maximumRecallLoss,
  'maximumFalseNegativeRatio': _criteria.maximumFalseNegativeRatio,
};

class _AcceptanceCriteria {
  final double minimumPrecisionGain;
  final double minimumF1Gain;
  final double maximumRecallLoss;
  final double maximumFalseNegativeRatio;

  const _AcceptanceCriteria({
    required this.minimumPrecisionGain,
    required this.minimumF1Gain,
    required this.maximumRecallLoss,
    required this.maximumFalseNegativeRatio,
  });
}

Map<String, Object?> _emptyReport({
  required List<String> errors,
  required String gateReportPath,
}) => {
  'schemaVersion': 'static_intensity_probability_gate_acceptance_v1',
  'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
  'status': 'fail',
  'gateReportPath': gateReportPath,
  'policy': const {
    'split': 'validation',
    'frozenTestEvaluated': false,
    'productionReady': false,
  },
  'criteria': _criteriaJson,
  'summary': const {},
  'thresholds': const [],
  'errors': errors,
};

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

double _number(Object? value) => value is num ? value.toDouble() : 0.0;

String _fmt(Object? value) => _number(value).toStringAsFixed(2);

String _pct(Object? value) => '${(_number(value) * 100).toStringAsFixed(1)}%';
