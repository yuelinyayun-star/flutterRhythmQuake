import 'dart:convert';
import 'dart:io';

const _defaultBoundaryPath =
    '.dart_tool/source_confidence_wording_boundary/report.json';
const _defaultOutputPath =
    '.dart_tool/source_wording_surface_audit/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_wording_surface_audit.generated.md';

void main(List<String> args) {
  final boundaryPath = _argument(args, '--boundary') ?? _defaultBoundaryPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceWordingSurfaceAuditReportJson(
    boundaryPath: boundaryPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source wording surface audit report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceWordingSurfaceAuditReportJson({
  String boundaryPath = _defaultBoundaryPath,
}) {
  final errors = <String>[];
  final boundary = _readJsonFile(boundaryPath, errors);
  final sources = _readSources(errors);

  final checks = [
    _sourceCardCandidateCopyCheck(sources),
    _expiredHiddenFromSourceCardCheck(sources),
    _sourceTriggerLineCheck(sources),
    _sourceEventIsolationCheck(sources),
    _voicePathCheck(sources),
    _officialAdapterCheck(sources),
    _debugSurfaceCheck(sources),
  ];
  final summary = _summary(checks);
  final validation = _validation(
    boundary: boundary,
    checks: checks,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_wording_surface_audit_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'confidenceWordingBoundary': boundaryPath,
      'sourceFiles': sources.keys.toList(growable: false)..sort(),
    },
    'policy': const {
      'diagnosticOnly': true,
      'productionCoordinateSwitchAllowed': false,
      'officialAlertWordingAllowed': false,
      'notes':
          'This audit verifies current UI, voice and official alert code paths against the source confidence wording boundary.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'checks': checks,
  };
}

Map<String, String> _readSources(List<String> errors) {
  const paths = [
    'lib/widgets/ui/alert_module.dart',
    'lib/widgets/ui/unified_alert_card.dart',
    'lib/widgets/ui/debug_page.dart',
    'lib/core/utils/alert_voice_helper.dart',
    'lib/providers/quake_provider.dart',
    'lib/services/quake_event_adapter.dart',
    'lib/services/tts_service.dart',
  ];
  final result = <String, String>{};
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      errors.add('source_file_missing:$path');
      result[path] = '';
      continue;
    }
    result[path] = file.readAsStringSync();
  }
  return result;
}

Map<String, Object?> _sourceCardCandidateCopyCheck(
  Map<String, String> sources,
) {
  final alert = sources['lib/widgets/ui/alert_module.dart'] ?? '';
  final passed =
      alert.contains('_sourceCandidateRegionText') &&
      alert.contains("metadata['candidate_region']") &&
      alert.contains('candidateRegionText == null') &&
      alert.contains('apiTypeLabel: apiTypeLabel') &&
      alert.contains('_buildCompactInfoColumn') &&
      alert.contains('event.apiTypeLabel');
  return _check(
    id: 'source_card_candidate_copy',
    surface: 'source_estimation_unified_card',
    status: passed,
    expectation:
        'source card may show production quality plus explicit diagnostic candidate-region text',
    evidence: [
      'AlertModule reads sourceEvent.metadata candidate_region',
      'candidate text is appended only to apiTypeLabel',
      'compact source-estimation card renders apiTypeLabel',
    ],
  );
}

Map<String, Object?> _expiredHiddenFromSourceCardCheck(
  Map<String, String> sources,
) {
  final alert = sources['lib/widgets/ui/alert_module.dart'] ?? '';
  final passed =
      alert.contains("'expired' => null") &&
      !alert.contains('候选区域 已过期') &&
      !alert.contains(r'\u5019\u9009\u533a\u57df \u5df2\u8fc7\u671f');
  return _check(
    id: 'candidate_region_expired_hidden',
    surface: 'source_estimation_unified_card',
    status: passed,
    expectation:
        'expired candidate-region state must not be shown as alert uncertainty',
    evidence: [
      'AlertModule maps expired candidate_region status to null',
      'expired wording is retained for reports/debug only',
    ],
  );
}

Map<String, Object?> _sourceTriggerLineCheck(Map<String, String> sources) {
  final alert = sources['lib/widgets/ui/alert_module.dart'] ?? '';
  final passed =
      alert.contains('warnArea: triggerText') &&
      alert.contains('P: \${phases.count(EstimatedStationPhase.p)}') &&
      alert.contains('S: \${phases.count(EstimatedStationPhase.s)}') &&
      !RegExp(
        r'warnArea:\s*(candidateRegionText|apiTypeLabel)',
      ).hasMatch(alert);
  return _check(
    id: 'source_trigger_line_no_candidate_region',
    surface: 'source_estimation_unified_card',
    status: passed,
    expectation:
        'source-estimation warnArea line remains trigger P/S/O text, not candidate-region wording',
    evidence: [
      'source UnifiedQuakeData warnArea is triggerText',
      'triggerText is built from classified station phases',
    ],
  );
}

Map<String, Object?> _sourceEventIsolationCheck(Map<String, String> sources) {
  final alert = sources['lib/widgets/ui/alert_module.dart'] ?? '';
  final provider = sources['lib/providers/quake_provider.dart'] ?? '';
  final passed =
      alert.contains('StationEventTracker.instance.currentNiedEvent') &&
      alert.contains('final sourceUnified = _sourceEstimationUnifiedEventV2') &&
      alert.contains('provider.unifiedEvents.length +') &&
      !provider.contains('StationEventTracker') &&
      !provider.contains('nied_source_estimation') &&
      !provider.contains('candidate_region');
  return _check(
    id: 'source_event_not_inserted_into_official_unified_queue',
    surface: 'provider_unified_queue',
    status: passed,
    expectation:
        'source-estimation event is composed locally for UI and is not inserted into provider unified event queue',
    evidence: [
      'AlertModule listens to StationEventTracker currentNiedEvent directly',
      'QuakeProvider has no StationEventTracker or candidate_region dependency',
    ],
  );
}

Map<String, Object?> _voicePathCheck(Map<String, String> sources) {
  final helper = sources['lib/core/utils/alert_voice_helper.dart'] ?? '';
  final provider = sources['lib/providers/quake_provider.dart'] ?? '';
  final tts = sources['lib/services/tts_service.dart'] ?? '';
  final passed =
      provider.contains('AlertVoiceHelper.generateUnifiedEventText') &&
      provider.contains('TtsService().speakEvent') &&
      tts.contains('Future<void> speakEvent') &&
      !helper.contains('candidate_region') &&
      !helper.contains('apiTypeLabel') &&
      !provider.contains('nied_source_estimation') &&
      !provider.contains('candidate_region');
  return _check(
    id: 'voice_path_excludes_candidate_region',
    surface: 'voice_tts',
    status: passed,
    expectation:
        'voice/TTS path must not consume candidate-region diagnostic wording',
    evidence: [
      'QuakeProvider voice path calls AlertVoiceHelper for provider unified events',
      'AlertVoiceHelper does not read candidate_region or apiTypeLabel',
      'TtsService only speaks text passed by provider/helper',
    ],
  );
}

Map<String, Object?> _officialAdapterCheck(Map<String, String> sources) {
  final adapter = sources['lib/services/quake_event_adapter.dart'] ?? '';
  final passed =
      adapter.contains('class QuakeEventAdapter') &&
      !adapter.contains('candidate_region') &&
      !adapter.contains('nied_source_estimation');
  return _check(
    id: 'official_adapter_excludes_candidate_region',
    surface: 'official_alert_adapter',
    status: passed,
    expectation:
        'official data adapters must not consume source-estimation candidate-region metadata',
    evidence: [
      'QuakeEventAdapter converts external official/info sources only',
      'adapter source does not reference candidate_region',
    ],
  );
}

Map<String, Object?> _debugSurfaceCheck(Map<String, String> sources) {
  final debug = sources['lib/widgets/ui/debug_page.dart'] ?? '';
  final passed =
      debug.contains("metadata['candidate_region']") &&
      debug.contains("metadata['candidate_region_residual_gate']") &&
      debug.contains("metadata['candidate_region_local_support_gate']");
  return _check(
    id: 'debug_surface_keeps_full_candidate_region_metadata',
    surface: 'debug_and_reports',
    status: passed,
    expectation:
        'debug surfaces may show full candidate-region residual/local-support metadata',
    evidence: [
      'DebugPage reads candidate_region',
      'DebugPage reads residual gate and local support gate metadata',
    ],
  );
}

Map<String, Object?> _check({
  required String id,
  required String surface,
  required bool status,
  required String expectation,
  required List<String> evidence,
}) {
  return {
    'id': id,
    'surface': surface,
    'status': status ? 'pass' : 'fail',
    'expectation': expectation,
    'evidence': evidence,
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> checks) {
  return {
    'checkCount': checks.length,
    'passedCheckCount': checks
        .where((entry) => entry['status'] == 'pass')
        .length,
    'failedCheckCount': checks
        .where((entry) => entry['status'] != 'pass')
        .length,
    'sourceCardCheckCount': checks
        .where((entry) => entry['surface'] == 'source_estimation_unified_card')
        .length,
    'voicePathCheckCount': checks
        .where((entry) => entry['surface'] == 'voice_tts')
        .length,
    'officialAdapterCheckCount': checks
        .where((entry) => entry['surface'] == 'official_alert_adapter')
        .length,
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> boundary,
  required List<Map<String, Object?>> checks,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  final boundarySummary = _map(boundary['summary']);
  if (boundary['status'] != 'pass') {
    violations.add('confidence_wording_boundary_not_pass');
  }
  if (_intValue(boundarySummary['officialAlertWordingAllowedCount']) != 0) {
    violations.add('boundary_allows_official_alert_wording');
  }
  if (_intValue(boundarySummary['productionCoordinateSwitchAllowedCount']) !=
      0) {
    violations.add('boundary_allows_coordinate_switching');
  }
  if (_intValue(summary['checkCount']) != 7) {
    violations.add('unexpected_audit_check_count');
  }
  if (_intValue(summary['failedCheckCount']) != 0) {
    violations.add('surface_audit_check_failed');
  }
  for (final check in checks) {
    if (check['status'] != 'pass') {
      violations.add('check_failed:${check['id']}');
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
    ..writeln('# Source Wording Surface Audit')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Diagnostic only: `true`')
    ..writeln('- Checks: `${summary['checkCount']}`')
    ..writeln('- Passed checks: `${summary['passedCheckCount']}`')
    ..writeln('- Failed checks: `${summary['failedCheckCount']}`')
    ..writeln()
    ..writeln('## Checks')
    ..writeln()
    ..writeln('| Check | Surface | Status | Expectation |')
    ..writeln('| --- | --- | --- | --- |');
  for (final rawCheck in _list(report['checks'])) {
    final check = _map(rawCheck);
    buffer.writeln(
      '| `${check['id']}` | `${check['surface']}` | '
      '`${check['status']}` | ${check['expectation']} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Current source-estimation candidate-region wording is limited to the source-estimation unified card apiTypeLabel.',
    )
    ..writeln(
      '- Expired candidate-region state is hidden from the source card and remains debug/report-only.',
    )
    ..writeln(
      '- Voice/TTS and official adapter paths do not consume candidate-region metadata.',
    )
    ..writeln(
      '- Production coordinate switching remains forbidden by upstream matrix and boundary reports.',
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
