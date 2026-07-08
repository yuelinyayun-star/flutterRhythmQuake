import 'dart:convert';
import 'dart:io';

const _defaultResidualPath =
    '.dart_tool/source_residual_delayed_recovery_report/report.json';
const _defaultLocalSupportPath =
    '.dart_tool/source_local_support_control_report/report.json';
const _defaultOutputPath =
    '.dart_tool/source_residual_decision_matrix/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_residual_decision_matrix.generated.md';

void main(List<String> args) {
  final residualPath = _argument(args, '--residual') ?? _defaultResidualPath;
  final localSupportPath =
      _argument(args, '--local-support') ?? _defaultLocalSupportPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceResidualDecisionMatrixReportJson(
    residualPath: residualPath,
    localSupportPath: localSupportPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source residual decision matrix');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceResidualDecisionMatrixReportJson({
  String residualPath = _defaultResidualPath,
  String localSupportPath = _defaultLocalSupportPath,
}) {
  final errors = <String>[];
  final residual = _readJsonFile(residualPath, errors);
  final localSupport = _readJsonFile(localSupportPath, errors);
  final residualCases = {
    for (final raw in _list(residual['cases']))
      _map(raw)['caseId']?.toString() ?? '': _map(raw),
  }..remove('');
  final localCases = {
    for (final raw in _list(localSupport['cases']))
      _map(raw)['caseId']?.toString() ?? '': _map(raw),
  }..remove('');

  final rows = [
    _immediateAcceptRow(residualCases),
    _delayedSameRegionRecoveryRow(residualCases),
    _falseRecoveryRejectRow(residualCases),
    _localSupportDelayedRow(localCases),
    _noCandidateRegionControlRow(localCases),
  ];

  final summary = _summary(rows, residual, localSupport);
  final validation = _validation(
    rows: rows,
    residualCases: residualCases,
    localCases: localCases,
    residual: residual,
    localSupport: localSupport,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_residual_decision_matrix_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'residualDelayedRecoveryReport': residualPath,
      'localSupportControlReport': localSupportPath,
    },
    'policy': const {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'notes':
          'This matrix codifies diagnostic candidate-region signatures. It must not authorize production coordinate switching.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'rows': rows,
  };
}

Map<String, Object?> _immediateAcceptRow(
  Map<String, Map<String, Object?>> residualCases,
) {
  const caseId = '20260622_tomakomai_south_offshore_m35_hinet';
  final entry = residualCases[caseId];
  final accepted = _intValue(entry?['acceptedPositiveFrameCount']);
  final immediate = _intValue(entry?['confirmedImmediateCount']);
  final rejected = _intValue(entry?['rejectedPositiveFrameCount']);
  final coordinateSwitches = _intValue(entry?['coordinateSwitchAllowedCount']);
  final dualRejected = _intValue(
    entry?['dualRegressionRejectedPositiveFrameCount'],
  );
  final passed =
      entry != null &&
      accepted == 3 &&
      immediate == 3 &&
      rejected == 0 &&
      dualRejected == 0 &&
      coordinateSwitches == 0;
  return {
    'signature': 'immediate_accept',
    'caseIds': const [caseId],
    'status': passed ? 'pass' : 'fail',
    'diagnosis': entry?['caseDiagnosis'],
    'decision':
        'candidate-region can be confirmed immediately when rank and attenuation both support the candidate and there is no dual residual regression',
    'evidence': {
      'acceptedPositiveFrameCount': accepted,
      'confirmedImmediateCount': immediate,
      'rejectedPositiveFrameCount': rejected,
      'dualRegressionRejectedPositiveFrameCount': dualRejected,
      'coordinateSwitchAllowedCount': coordinateSwitches,
    },
  };
}

Map<String, Object?> _delayedSameRegionRecoveryRow(
  Map<String, Map<String, Object?>> residualCases,
) {
  const caseId = '20260622_kushiro_offshore_m30_jma';
  final entry = residualCases[caseId];
  final recovered = _intValue(entry?['delayedRecoveredPositiveFrameCount']);
  final residualDelayed = _intValue(entry?['residualConfirmedDelayedCount']);
  final dualRejected = _intValue(
    entry?['dualRegressionRejectedPositiveFrameCount'],
  );
  final noSupportRejected = _intValue(
    entry?['noSupportRejectedPositiveFrameCount'],
  );
  final coordinateSwitches = _intValue(entry?['coordinateSwitchAllowedCount']);
  final passed =
      entry != null &&
      recovered == 3 &&
      residualDelayed == 1 &&
      dualRejected == 0 &&
      noSupportRejected == 3 &&
      coordinateSwitches == 0;
  return {
    'signature': 'delayed_same_region_recovery',
    'caseIds': const [caseId],
    'status': passed ? 'pass' : 'fail',
    'diagnosis': entry?['caseDiagnosis'],
    'decision':
        'early no-support candidate frames may be recovered by a later same-region residual-supported frame',
    'evidence': {
      'delayedRecoveredPositiveFrameCount': recovered,
      'residualConfirmedDelayedCount': residualDelayed,
      'dualRegressionRejectedPositiveFrameCount': dualRejected,
      'noSupportRejectedPositiveFrameCount': noSupportRejected,
      'coordinateSwitchAllowedCount': coordinateSwitches,
    },
  };
}

Map<String, Object?> _falseRecoveryRejectRow(
  Map<String, Map<String, Object?>> residualCases,
) {
  const caseId = '20260621_fukushima_offshore_m32_eq6';
  final entry = residualCases[caseId];
  final delayed = _intValue(entry?['delayedRecoveredPositiveFrameCount']);
  final rejected = _intValue(entry?['rejectedPositiveFrameCount']);
  final dualRejected = _intValue(
    entry?['dualRegressionRejectedPositiveFrameCount'],
  );
  final coordinateSwitches = _intValue(entry?['coordinateSwitchAllowedCount']);
  final passed =
      entry != null &&
      delayed == 0 &&
      rejected >= 1 &&
      dualRejected == rejected &&
      coordinateSwitches == 0;
  return {
    'signature': 'false_recovery_reject',
    'caseIds': const [caseId],
    'status': passed ? 'pass' : 'fail',
    'diagnosis': entry?['caseDiagnosis'],
    'decision':
        'candidate frames that improve truth offline but regress rank and attenuation together remain rejected',
    'evidence': {
      'rejectedPositiveFrameCount': rejected,
      'delayedRecoveredPositiveFrameCount': delayed,
      'dualRegressionRejectedPositiveFrameCount': dualRejected,
      'coordinateSwitchAllowedCount': coordinateSwitches,
    },
  };
}

Map<String, Object?> _localSupportDelayedRow(
  Map<String, Map<String, Object?>> localCases,
) {
  const caseId = '20260625_iwate_offshore_m32_jma';
  final entry = localCases[caseId];
  final localConfirmed = _intValue(entry?['localSupportConfirmedCount']);
  final delayed = _intValue(entry?['confirmedDelayedCount']);
  final residualDelayed = _intValue(
    _map(entry?['expectedCounts'])['residualConfirmedDelayedCount'],
  );
  final switches = _intValue(entry?['coordinateSwitchAllowedCount']);
  final unexpectedLocal = _intValue(
    entry?['unexpectedLocalSupportConfirmationCount'],
  );
  final passed =
      entry != null &&
      localConfirmed == 1 &&
      delayed == 1 &&
      residualDelayed == 0 &&
      switches == 0 &&
      unexpectedLocal == 0;
  return {
    'signature': 'local_support_delayed_confirmation',
    'caseIds': const [caseId],
    'status': passed ? 'pass' : 'fail',
    'diagnosis': entry?['diagnosis'],
    'decision':
        'local member growth may confirm a pending candidate-region as diagnostic metadata only',
    'evidence': {
      'localSupportConfirmedCount': localConfirmed,
      'confirmedDelayedCount': delayed,
      'expectedResidualConfirmedDelayedCount': residualDelayed,
      'unexpectedLocalSupportConfirmationCount': unexpectedLocal,
      'coordinateSwitchAllowedCount': switches,
    },
  };
}

Map<String, Object?> _noCandidateRegionControlRow(
  Map<String, Map<String, Object?>> localCases,
) {
  const caseIds = [
    '20260623_tokachi_southeast_offshore_m34_hinet',
    '20260624_fukushima_aizu_m32_jma_eq5',
  ];
  final evidence = <Map<String, Object?>>[];
  var passed = true;
  var switches = 0;
  for (final caseId in caseIds) {
    final entry = localCases[caseId];
    final frameCount = _intValue(entry?['frameCount']);
    final coordinateSwitches = _intValue(
      entry?['coordinateSwitchAllowedCount'],
    );
    switches += coordinateSwitches;
    final casePassed =
        entry != null && frameCount == 0 && coordinateSwitches == 0;
    passed = passed && casePassed;
    evidence.add({
      'caseId': caseId,
      'diagnosis': entry?['diagnosis'],
      'frameCount': frameCount,
      'coordinateSwitchAllowedCount': coordinateSwitches,
    });
  }
  return {
    'signature': 'no_candidate_region_control',
    'caseIds': caseIds,
    'status': passed ? 'pass' : 'fail',
    'diagnosis': 'no_candidate_region_controls_clear',
    'decision':
        'manifest controls without candidate-region evidence must stay empty and must not create delayed confirmations',
    'evidence': {
      'controlCaseCount': caseIds.length,
      'productionCoordinateSwitchAllowedCount': switches,
      'cases': evidence,
    },
  };
}

Map<String, Object?> _summary(
  List<Map<String, Object?>> rows,
  Map<String, Object?> residual,
  Map<String, Object?> localSupport,
) {
  final localSummary = _map(localSupport['summary']);
  final residualSummary = _map(residual['summary']);
  return {
    'rowCount': rows.length,
    'passedRowCount': rows.where((entry) => entry['status'] == 'pass').length,
    'failedRowCount': rows.where((entry) => entry['status'] != 'pass').length,
    'residualReportStatus': residual['status'],
    'localSupportReportStatus': localSupport['status'],
    'manifestCaseCount': _intValue(localSummary['caseCount']),
    'manifestCandidateRegionCaseCount': _intValue(
      localSummary['caseWithCandidateRegionCount'],
    ),
    'unexpectedLocalSupportConfirmationCount': _intValue(
      localSummary['unexpectedLocalSupportConfirmationCount'],
    ),
    'localSupportConfirmedCaseCount': _intValue(
      localSummary['localSupportConfirmedCaseCount'],
    ),
    'delayedRecoveredPositiveFrameCount': _intValue(
      residualSummary['delayedRecoveredPositiveFrameCount'],
    ),
    'productionCoordinateSwitchAllowedCount': _intValue(
      localSummary['productionCoordinateSwitchAllowedCount'],
    ),
  };
}

Map<String, Object?> _validation({
  required List<Map<String, Object?>> rows,
  required Map<String, Map<String, Object?>> residualCases,
  required Map<String, Map<String, Object?>> localCases,
  required Map<String, Object?> residual,
  required Map<String, Object?> localSupport,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (residual['status'] != 'pass') violations.add('residual_report_not_pass');
  if (localSupport['status'] != 'pass') {
    violations.add('local_support_report_not_pass');
  }
  for (final row in rows) {
    if (row['status'] != 'pass') {
      violations.add('decision_row_failed:${row['signature']}');
    }
  }
  if (_intValue(summary['productionCoordinateSwitchAllowedCount']) != 0) {
    violations.add('production_coordinate_switch_present');
  }
  if (_intValue(summary['unexpectedLocalSupportConfirmationCount']) != 0) {
    violations.add('unexpected_local_support_confirmation');
  }
  if (_intValue(summary['manifestCaseCount']) != 6) {
    violations.add('unexpected_manifest_case_count');
  }
  if (_intValue(summary['manifestCandidateRegionCaseCount']) != 4) {
    violations.add('unexpected_candidate_region_case_count');
  }

  final fukushima = residualCases['20260621_fukushima_offshore_m32_eq6'];
  final kushiro = residualCases['20260622_kushiro_offshore_m30_jma'];
  final tomakomai =
      residualCases['20260622_tomakomai_south_offshore_m35_hinet'];
  final iwate = localCases['20260625_iwate_offshore_m32_jma'];
  if (_intValue(fukushima?['delayedRecoveredPositiveFrameCount']) != 0) {
    violations.add('fukushima_delayed_false_recovery');
  }
  if (_intValue(kushiro?['delayedRecoveredPositiveFrameCount']) != 3) {
    violations.add('kushiro_delayed_recovery_count_regressed');
  }
  if (_intValue(tomakomai?['acceptedPositiveFrameCount']) != 3) {
    violations.add('tomakomai_immediate_accept_count_regressed');
  }
  if (_intValue(iwate?['localSupportConfirmedCount']) != 1) {
    violations.add('iwate_local_support_confirmation_regressed');
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
    ..writeln('# Source Residual Decision Matrix')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Diagnostic only: `true`')
    ..writeln(
      '- Production coordinate switches: `${summary['productionCoordinateSwitchAllowedCount']}`',
    )
    ..writeln(
      '- Manifest cases: `${summary['manifestCaseCount']}` '
      '(${summary['manifestCandidateRegionCaseCount']} with candidate-region frames)',
    )
    ..writeln(
      '- Unexpected local-support confirmations: `${summary['unexpectedLocalSupportConfirmationCount']}`',
    )
    ..writeln()
    ..writeln('## Matrix')
    ..writeln()
    ..writeln('| Signature | Status | Cases | Decision | Evidence |')
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final rawRow in _list(report['rows'])) {
    final row = _map(rawRow);
    buffer.writeln(
      '| `${row['signature']}` | `${row['status']}` | '
      '${_codeList(_list(row['caseIds']))} | ${row['decision']} | '
      '${_evidenceSummary(_map(row['evidence']))} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Interpretation')
    ..writeln()
    ..writeln(
      '- `immediate_accept`: Tomakomai remains the positive guard for direct residual-supported confirmation.',
    )
    ..writeln(
      '- `delayed_same_region_recovery`: Kushiro keeps the delayed recovery path for early no-support frames.',
    )
    ..writeln(
      '- `false_recovery_reject`: Fukushima remains blocked because rank and attenuation regress together.',
    )
    ..writeln(
      '- `local_support_delayed_confirmation`: Iwate is confirmed by local member growth only as metadata.',
    )
    ..writeln(
      '- `no_candidate_region_control`: Tokachi and Fukushima Aizu stay empty controls.',
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

String _evidenceSummary(Map<String, Object?> evidence) {
  final parts = <String>[];
  for (final entry in evidence.entries) {
    if (entry.value is List) {
      parts.add('`${entry.key}=${_list(entry.value).length}`');
    } else {
      parts.add('`${entry.key}=${entry.value}`');
    }
  }
  return parts.join(', ');
}

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
