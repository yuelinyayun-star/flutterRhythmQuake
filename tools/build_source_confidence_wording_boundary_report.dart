import 'dart:convert';
import 'dart:io';

const _defaultMatrixPath =
    '.dart_tool/source_residual_decision_matrix/report.json';
const _defaultOutputPath =
    '.dart_tool/source_confidence_wording_boundary/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_confidence_wording_boundary.generated.md';

void main(List<String> args) {
  final matrixPath = _argument(args, '--matrix') ?? _defaultMatrixPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceConfidenceWordingBoundaryReportJson(
    matrixPath: matrixPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source confidence wording boundary report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceConfidenceWordingBoundaryReportJson({
  String matrixPath = _defaultMatrixPath,
}) {
  final errors = <String>[];
  final matrix = _readJsonFile(matrixPath, errors);
  final matrixRows = {
    for (final raw in _list(matrix['rows']))
      _map(raw)['signature']?.toString() ?? '': _map(raw),
  }..remove('');

  final boundaries = [
    _boundary(
      signal: 'production_estimate_quality',
      evidenceSignatures: matrixRows.keys.toList(growable: false)..sort(),
      status: _allRowsPass(matrixRows) ? 'pass' : 'fail',
      sourceCard: 'show_quality_line',
      diagnosticReports: 'show_full_metrics',
      officialAlertWording: 'hide',
      coordinateSwitch: 'forbid',
      allowedCopy: const [
        'quality grade and confidence percentage',
        'RMS residual, azimuthal gap and P90 uncertainty',
        'estimated shindo badge colored by estimated shindo',
        'trigger and support station counts',
      ],
      forbiddenCopy: const [
        'final hypocenter wording',
        'JMA or EEW replacement wording',
        'coordinate correction wording',
      ],
    ),
    _boundary(
      signal: 'candidate_region_pending',
      evidenceSignatures: const ['delayed_same_region_recovery'],
      status: _rowPass(matrixRows, 'delayed_same_region_recovery')
          ? 'pass'
          : 'fail',
      sourceCard: 'show_as_uncertainty_only',
      diagnosticReports: 'show_full_metrics',
      officialAlertWording: 'hide',
      coordinateSwitch: 'forbid',
      allowedCopy: const [
        'candidate region pending',
        'awaiting same-region residual or local member support',
      ],
      forbiddenCopy: const [
        'confirmed epicenter',
        'replace production hypocenter',
        'voice or push alert wording',
      ],
    ),
    _boundary(
      signal: 'candidate_region_residual_confirmed',
      evidenceSignatures: const [
        'immediate_accept',
        'delayed_same_region_recovery',
      ],
      status:
          _rowPass(matrixRows, 'immediate_accept') &&
              _rowPass(matrixRows, 'delayed_same_region_recovery')
          ? 'pass'
          : 'fail',
      sourceCard: 'show_as_diagnostic_confirmation',
      diagnosticReports: 'show_full_metrics',
      officialAlertWording: 'hide',
      coordinateSwitch: 'forbid',
      allowedCopy: const [
        'candidate region confirmed',
        'candidate region delayed-confirmed',
        'same-region residual support',
      ],
      forbiddenCopy: const [
        'official source update',
        'production coordinate switch',
        'final report language',
      ],
    ),
    _boundary(
      signal: 'candidate_region_local_support_confirmed',
      evidenceSignatures: const ['local_support_delayed_confirmation'],
      status: _rowPass(matrixRows, 'local_support_delayed_confirmation')
          ? 'pass'
          : 'fail',
      sourceCard: 'show_as_diagnostic_confirmation',
      diagnosticReports: 'show_full_metrics',
      officialAlertWording: 'hide',
      coordinateSwitch: 'forbid',
      allowedCopy: const [
        'candidate region delayed-confirmed',
        'local member support station count and growth',
        'estimate-member centroid distance and convergence',
      ],
      forbiddenCopy: const [
        'local-support truth claim',
        'replace production hypocenter',
        'official alert wording',
      ],
    ),
    _boundary(
      signal: 'candidate_region_rejected_or_expired',
      evidenceSignatures: const [
        'false_recovery_reject',
        'no_candidate_region_control',
      ],
      status:
          _rowPass(matrixRows, 'false_recovery_reject') &&
              _rowPass(matrixRows, 'no_candidate_region_control')
          ? 'pass'
          : 'fail',
      sourceCard: 'hide_or_show_debug_only',
      diagnosticReports: 'show_full_metrics',
      officialAlertWording: 'hide',
      coordinateSwitch: 'forbid',
      allowedCopy: const [
        'rejected in debug/report surfaces',
        'expired in debug/report surfaces',
        'dual residual regression reason',
      ],
      forbiddenCopy: const [
        'uncertain epicenter warning in alert copy',
        'candidate region map recenter',
        'coordinate correction wording',
      ],
    ),
    _boundary(
      signal: 'event_level_metrics_and_split',
      evidenceSignatures: const [],
      status: 'pass',
      sourceCard: 'not_ready',
      diagnosticReports: 'show_blocker_state',
      officialAlertWording: 'hide',
      coordinateSwitch: 'forbid',
      allowedCopy: const [
        'diagnostic-ready only',
        'split or metric gate not complete',
      ],
      forbiddenCopy: const [
        'validated production accuracy wording',
        'calibrated probability wording',
        'test-set performance wording',
      ],
    ),
  ];

  final summary = _summary(boundaries);
  final validation = _validation(
    matrix: matrix,
    boundaries: boundaries,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_confidence_wording_boundary_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {'residualDecisionMatrix': matrixPath},
    'policy': const {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'officialAlertWordingAllowed': false,
      'notes':
          'Candidate-region confidence wording may appear only on source-estimation diagnostic surfaces until event-level split and metric gates are ready.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'boundaries': boundaries,
  };
}

Map<String, Object?> _boundary({
  required String signal,
  required List<String> evidenceSignatures,
  required String status,
  required String sourceCard,
  required String diagnosticReports,
  required String officialAlertWording,
  required String coordinateSwitch,
  required List<String> allowedCopy,
  required List<String> forbiddenCopy,
}) {
  return {
    'signal': signal,
    'status': status,
    'evidenceSignatures': evidenceSignatures,
    'surfaces': {
      'sourceEstimationUnifiedCard': sourceCard,
      'debugAndGeneratedReports': diagnosticReports,
      'officialAlertWording': officialAlertWording,
      'productionCoordinateSwitch': coordinateSwitch,
    },
    'allowedCopy': allowedCopy,
    'forbiddenCopy': forbiddenCopy,
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> boundaries) {
  final officialAllowed = boundaries
      .where(
        (entry) => _map(entry['surfaces'])['officialAlertWording'] != 'hide',
      )
      .length;
  final coordinateSwitchAllowed = boundaries
      .where(
        (entry) =>
            _map(entry['surfaces'])['productionCoordinateSwitch'] != 'forbid',
      )
      .length;
  final sourceCardVisible = boundaries.where((entry) {
    final value = _map(entry['surfaces'])['sourceEstimationUnifiedCard'];
    return value == 'show_quality_line' ||
        value == 'show_as_uncertainty_only' ||
        value == 'show_as_diagnostic_confirmation';
  }).length;
  return {
    'boundaryCount': boundaries.length,
    'passedBoundaryCount': boundaries
        .where((entry) => entry['status'] == 'pass')
        .length,
    'officialAlertWordingAllowedCount': officialAllowed,
    'productionCoordinateSwitchAllowedCount': coordinateSwitchAllowed,
    'sourceCardVisibleBoundaryCount': sourceCardVisible,
    'diagnosticReportBoundaryCount': boundaries
        .where(
          (entry) =>
              _map(entry['surfaces'])['debugAndGeneratedReports'] ==
              'show_full_metrics',
        )
        .length,
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> matrix,
  required List<Map<String, Object?>> boundaries,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (matrix['status'] != 'pass') {
    violations.add('residual_decision_matrix_not_pass');
  }
  if (_intValue(summary['boundaryCount']) != 6) {
    violations.add('unexpected_boundary_count');
  }
  if (_intValue(summary['passedBoundaryCount']) != 6) {
    violations.add('boundary_status_not_pass');
  }
  if (_intValue(summary['officialAlertWordingAllowedCount']) != 0) {
    violations.add('official_alert_wording_allowed');
  }
  if (_intValue(summary['productionCoordinateSwitchAllowedCount']) != 0) {
    violations.add('production_coordinate_switch_allowed');
  }
  for (final boundary in boundaries) {
    final signal = boundary['signal'];
    final surfaces = _map(boundary['surfaces']);
    if (surfaces['officialAlertWording'] != 'hide') {
      violations.add('$signal:official_alert_wording_not_hidden');
    }
    if (surfaces['productionCoordinateSwitch'] != 'forbid') {
      violations.add('$signal:coordinate_switch_not_forbidden');
    }
    if (_list(boundary['forbiddenCopy']).isEmpty) {
      violations.add('$signal:missing_forbidden_copy');
    }
  }
  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'violations': violations,
  };
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final validation = _map(report['validation']);
  final buffer = StringBuffer()
    ..writeln('# Source Confidence Wording Boundary')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Diagnostic only: `true`')
    ..writeln(
      '- Boundaries: `${summary['boundaryCount']}` '
      '(${summary['passedBoundaryCount']} pass)',
    )
    ..writeln(
      '- Source-card visible boundaries: '
      '`${summary['sourceCardVisibleBoundaryCount']}`',
    )
    ..writeln(
      '- Official alert wording allowed: '
      '`${summary['officialAlertWordingAllowedCount']}`',
    )
    ..writeln(
      '- Production coordinate switches allowed: '
      '`${summary['productionCoordinateSwitchAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Boundary Matrix')
    ..writeln()
    ..writeln(
      '| Signal | Status | Source card | Reports/debug | Official alert wording | Coordinate switch | Evidence |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
  for (final rawBoundary in _list(report['boundaries'])) {
    final boundary = _map(rawBoundary);
    final surfaces = _map(boundary['surfaces']);
    buffer.writeln(
      '| `${boundary['signal']}` | `${boundary['status']}` | '
      '`${surfaces['sourceEstimationUnifiedCard']}` | '
      '`${surfaces['debugAndGeneratedReports']}` | '
      '`${surfaces['officialAlertWording']}` | '
      '`${surfaces['productionCoordinateSwitch']}` | '
      '${_codeList(_list(boundary['evidenceSignatures']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Allowed Copy')
    ..writeln();
  for (final rawBoundary in _list(report['boundaries'])) {
    final boundary = _map(rawBoundary);
    buffer
      ..writeln('### ${boundary['signal']}')
      ..writeln()
      ..writeln('- Allowed: ${_plainList(_list(boundary['allowedCopy']))}.')
      ..writeln('- Forbidden: ${_plainList(_list(boundary['forbiddenCopy']))}.')
      ..writeln();
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Source-estimation card may show production estimate quality and explicitly diagnostic candidate-region state.',
    )
    ..writeln(
      '- Generated reports and debug surfaces may show full candidate-region residual/local-support details.',
    )
    ..writeln(
      '- Official alert wording, voice/push wording and production coordinate replacement remain disallowed.',
    )
    ..writeln(
      '- Event-level split and metric gates must be completed before any calibrated production accuracy wording is introduced.',
    )
    ..writeln()
    ..writeln('## Validation')
    ..writeln()
    ..writeln('- Status: `${validation['status']}`.');
  final violations = _list(validation['violations']);
  if (violations.isEmpty) {
    buffer.writeln('- Violations: none.');
  } else {
    buffer.writeln('- Violations: ${_codeList(violations)}.');
  }
  buffer.writeln();
  return buffer.toString();
}

bool _allRowsPass(Map<String, Map<String, Object?>> rows) =>
    rows.isNotEmpty && rows.values.every((entry) => entry['status'] == 'pass');

bool _rowPass(Map<String, Map<String, Object?>> rows, String signature) =>
    rows[signature]?['status'] == 'pass';

Map<String, Object?> _readJsonFile(String path, List<String> errors) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('json_file_missing:$path');
    return const {};
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map) return decoded.cast<String, Object?>();
    errors.add('json_file_not_object:$path');
  } on FormatException catch (error) {
    errors.add('json_file_invalid:$path:${error.message}');
  }
  return const {};
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _codeList(List<Object?> items) {
  if (items.isEmpty) return '--';
  return items.map((item) => '`${item.toString()}`').join(', ');
}

String _plainList(List<Object?> items) {
  if (items.isEmpty) return '--';
  return items.map((item) => item.toString()).join('; ');
}
