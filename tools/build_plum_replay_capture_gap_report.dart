import 'dart:convert';
import 'dart:io';

const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultOutputPath = '.dart_tool/plum_replay_capture_gap/report.json';
const _defaultMarkdownPath =
    'docs/baselines/plum_replay_capture_gap.generated.md';
const _defaultDecisionPath = 'docs/data/plum_replay_capture_gap_decisions.json';

const _defaultCaseIds = {
  '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
  '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
  '20260627_fukushima_aizu_m36_jma_equake17',
  '20260628_iwate_offshore_m41_jma',
  '20260624_fukushima_aizu_m32_jma_eq5',
  '20260625_iwate_offshore_m32_jma',
  '20260622_kushiro_offshore_m30_jma',
};

void main(List<String> args) {
  final fixtureDirectory =
      _argument(args, '--fixture-directory') ?? _defaultFixtureDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final caseIds = _caseIdsFromArgs(args) ?? _defaultCaseIds;

  final report = buildPlumReplayCaptureGapReportJson(
    fixtureDirectory: fixtureDirectory,
    decisionPath: decisionPath,
    caseIds: caseIds,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(plumReplayCaptureGapMarkdown(report));

  stdout.writeln('wrote PLUM replay capture gap report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildPlumReplayCaptureGapReportJson({
  String fixtureDirectory = _defaultFixtureDirectory,
  String decisionPath = _defaultDecisionPath,
  Set<String> caseIds = _defaultCaseIds,
  DateTime? nowJst,
}) {
  final errors = <String>[];
  final cases = <Map<String, Object?>>[];
  final excludedCases = <Map<String, Object?>>[];
  final completeCases = <Map<String, Object?>>[];
  final decisions = _readDecisions(File(decisionPath), errors);
  final effectiveNowJst = nowJst ?? _currentJstWallClock();
  final fixtureDir = Directory(fixtureDirectory);
  if (!fixtureDir.existsSync()) {
    errors.add('fixture_directory_missing:$fixtureDirectory');
  } else {
    final manifests =
        fixtureDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final manifestFile in manifests) {
      final fixture = _readJsonObject(manifestFile, errors);
      final caseId = fixture['caseId']?.toString() ?? '';
      if (!caseIds.contains(caseId)) continue;
      final originTimeJst = _originTimeJst(fixture);
      final captureDirectory = fixture['captureDirectory']?.toString() ?? '';
      final captureManifest = _captureManifest(captureDirectory, errors);
      final failedGifCount = _intValue(captureManifest['failedGifCount']);
      final expectedGifCount = _intValue(captureManifest['expectedGifCount']);
      final downloadedGifCount = _intValue(
        captureManifest['downloadedGifCount'],
      );
      final failedRecords = _failedRecords(captureManifest);
      final repairWindowStatus = _repairWindowStatus(
        failedGifCount: failedGifCount,
        originTimeJst: originTimeJst,
        nowJst: effectiveNowJst,
      );
      final decision = decisions[caseId];
      final exclusion = _approvedExclusion(
        caseId: caseId,
        decision: decision,
        failedRecords: failedRecords,
        repairWindowStatus: repairWindowStatus,
        errors: errors,
      );
      final entry = {
        'caseId': caseId,
        'originTimeJst': originTimeJst,
        'captureDirectory': captureDirectory,
        'captureManifestPath': captureDirectory.isEmpty
            ? null
            : '$captureDirectory/capture_manifest.json',
        'expectedGifCount': expectedGifCount,
        'downloadedGifCount': downloadedGifCount,
        'failedGifCount': failedGifCount,
        'failedRecords': failedRecords,
        'repairWindowStatus': repairWindowStatus,
        'exclusionDecision': exclusion,
        'recommendedAction': _recommendedAction(
          failedGifCount: failedGifCount,
          repairWindowStatus: repairWindowStatus,
          exclusionApproved: exclusion['exclusionApproved'] == true,
        ),
      };
      if (failedGifCount > 0) {
        if (exclusion['exclusionApproved'] == true) {
          excludedCases.add(entry);
        } else {
          cases.add(entry);
        }
      } else {
        completeCases.add(entry);
      }
    }
  }

  final foundCaseIds = {
    for (final entry in cases) entry['caseId'].toString(),
    for (final entry in excludedCases) entry['caseId'].toString(),
    for (final entry in completeCases) entry['caseId'].toString(),
  };
  final missingCaseIds = caseIds.difference(foundCaseIds);
  if (missingCaseIds.isNotEmpty) {
    errors.add('case_ids_not_found:${missingCaseIds.join(',')}');
  }

  return {
    'schemaVersion': 'plum_replay_capture_gap_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'policy': const {
      'diagnosticOnly': true,
      'repairsCaptures': false,
      'excludesCaptures': false,
      'recordsExclusionDecisions': true,
      'changesReplayMetrics': false,
      'completeReplayRequirement': 'capture_manifest_failed_gifs_eq_0',
      'historicalGifRepairWindow': 'origin_time_jst_plus_3h',
    },
    'inputs': {
      'fixtureDirectory': fixtureDirectory,
      'decisionPath': decisionPath,
      'caseIds': caseIds.toList()..sort(),
    },
    'summary': {
      'caseCount': foundCaseIds.length,
      'completeCaseCount': completeCases.length,
      'totalGapCaseCount': cases.length + excludedCases.length,
      'gapCaseCount': cases.length,
      'excludedGapCaseCount': excludedCases.length,
      'failedGifCount': cases.fold<int>(
        0,
        (total, entry) => total + _intValue(entry['failedGifCount']),
      ),
      'excludedFailedGifCount': excludedCases.fold<int>(
        0,
        (total, entry) => total + _intValue(entry['failedGifCount']),
      ),
      'totalFailedGifCount': [...cases, ...excludedCases].fold<int>(
        0,
        (total, entry) => total + _intValue(entry['failedGifCount']),
      ),
    },
    'gapCases': cases,
    'excludedGapCases': excludedCases,
    'completeCases': completeCases,
    'errors': errors,
    'warnings': const [],
  };
}

String plumReplayCaptureGapMarkdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final buffer = StringBuffer()
    ..writeln('# PLUM Replay Capture Gap Report')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases scanned: `${summary['caseCount']}`')
    ..writeln('- Complete cases: `${summary['completeCaseCount']}`')
    ..writeln('- Total gap cases: `${summary['totalGapCaseCount']}`')
    ..writeln('- Unresolved gap cases: `${summary['gapCaseCount']}`')
    ..writeln('- Excluded gap cases: `${summary['excludedGapCaseCount']}`')
    ..writeln('- Unresolved failed GIFs: `${summary['failedGifCount']}`')
    ..writeln('- Excluded failed GIFs: `${summary['excludedFailedGifCount']}`')
    ..writeln('- Total failed GIFs: `${summary['totalFailedGifCount']}`')
    ..writeln()
    ..writeln('## Unresolved Gap Cases')
    ..writeln()
    ..writeln(
      '| Case | Origin JST | Repair window | Expected | Downloaded | Failed | Action |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | --- |');
  for (final rawCase in _list(report['gapCases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['originTimeJst']}` | '
      '`${entry['repairWindowStatus']}` | ${entry['expectedGifCount']} | '
      '${entry['downloadedGifCount']} | ${entry['failedGifCount']} | '
      '`${entry['recommendedAction']}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Excluded Gap Cases')
    ..writeln()
    ..writeln(
      '| Case | Origin JST | Repair window | Expected | Downloaded | Failed | Decision |',
    )
    ..writeln('| --- | --- | --- | ---: | ---: | ---: | --- |');
  for (final rawCase in _list(report['excludedGapCases'])) {
    final entry = _map(rawCase);
    final decision = _map(entry['exclusionDecision']);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['originTimeJst']}` | '
      '`${entry['repairWindowStatus']}` | ${entry['expectedGifCount']} | '
      '${entry['downloadedGifCount']} | ${entry['failedGifCount']} | '
      '`${decision['decisionStatus']}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- This report does not repair or exclude captures automatically.',
    )
    ..writeln(
      '- Historical NIED GIF capture repair is only considered within 3 hours '
      'after the event JST origin time.',
    )
    ..writeln(
      '- Gap cases with `expired_over_3h` must stay out of complete replay '
      'lead-time metrics until an explicit exclusion decision is recorded or '
      'the case is replaced by another complete capture with no missing GIFs.',
    )
    ..writeln(
      '- Excluded gap cases remain excluded from complete replay metrics; they '
      'do not count as complete captures and do not require historical '
      're-download.',
    );
  return buffer.toString();
}

Map<String, Map<String, Object?>> _readDecisions(
  File file,
  List<String> errors,
) {
  if (!file.existsSync()) return const {};
  final decoded = _readJsonObject(file, errors);
  final schema = decoded['schemaVersion']?.toString();
  if (schema != 'plum_replay_capture_gap_decisions_v1') {
    errors.add('unexpected_decision_schema:${file.path}');
    return const {};
  }
  final decisions = <String, Map<String, Object?>>{};
  for (final raw in _list(decoded['decisions'])) {
    final decision = _map(raw);
    final caseId = decision['caseId']?.toString() ?? '';
    if (caseId.isEmpty) {
      errors.add('decision_missing_case_id:${file.path}');
      continue;
    }
    if (decisions.containsKey(caseId)) {
      errors.add('duplicate_decision:$caseId');
      continue;
    }
    decisions[caseId] = decision;
  }
  return decisions;
}

Map<String, Object?> _approvedExclusion({
  required String caseId,
  required Map<String, Object?>? decision,
  required List<Map<String, Object?>> failedRecords,
  required String repairWindowStatus,
  required List<String> errors,
}) {
  if (decision == null) {
    return const {
      'exclusionApproved': false,
      'decisionStatus': 'pending_exclusion_decision',
    };
  }
  if (decision['decisionStatus'] != 'capture_gap_exclusion_approved') {
    return {
      'exclusionApproved': false,
      'decisionStatus': decision['decisionStatus']?.toString(),
    };
  }
  if (decision['exclusionApproved'] != true) {
    errors.add('exclusion_approved_must_be_true:$caseId');
  }
  if (repairWindowStatus != 'expired_over_3h') {
    errors.add('exclusion_requires_expired_repair_window:$caseId');
  }
  if (DateTime.tryParse(decision['reviewedAtUtc']?.toString() ?? '') == null) {
    errors.add('exclusion_reviewed_at_not_parseable:$caseId');
  }
  if ((decision['reviewer']?.toString().trim() ?? '').isEmpty) {
    errors.add('exclusion_missing_reviewer:$caseId');
  }
  if ((decision['exclusionReason']?.toString().trim() ?? '').isEmpty) {
    errors.add('exclusion_missing_reason:$caseId');
  }
  final excludedFiles = _stringList(decision['excludedFiles']);
  final failedFiles = failedRecords
      .map((record) => record['file']?.toString() ?? '')
      .where((file) => file.isNotEmpty)
      .toSet();
  final missingExcludedFiles = failedFiles.difference(excludedFiles.toSet());
  if (missingExcludedFiles.isNotEmpty) {
    errors.add(
      'exclusion_missing_failed_files:$caseId:${missingExcludedFiles.join(',')}',
    );
  }
  return {
    'exclusionApproved': decision['exclusionApproved'] == true,
    'decisionStatus': decision['decisionStatus']?.toString(),
    'reviewedAtUtc': decision['reviewedAtUtc']?.toString(),
    'reviewer': decision['reviewer']?.toString(),
    'excludedFiles': excludedFiles,
    'exclusionReason': decision['exclusionReason']?.toString(),
  };
}

String? _originTimeJst(Map<String, Object?> fixture) {
  final truth = _map(fixture['truth']);
  return truth['originTimeJst']?.toString();
}

String _repairWindowStatus({
  required int failedGifCount,
  required String? originTimeJst,
  required DateTime nowJst,
}) {
  if (failedGifCount <= 0) return 'not_applicable_complete_capture';
  final origin = _parseJstWallClock(originTimeJst);
  if (origin == null) return 'unknown_origin_time';
  return nowJst.difference(origin) > const Duration(hours: 3)
      ? 'expired_over_3h'
      : 'within_3h';
}

String _recommendedAction({
  required int failedGifCount,
  required String repairWindowStatus,
  required bool exclusionApproved,
}) {
  if (failedGifCount <= 0) return 'keep_as_complete_replay_candidate';
  if (exclusionApproved) return 'excluded_from_complete_replay_metrics';
  if (repairWindowStatus == 'within_3h') {
    return 'repair_or_exclude_from_complete_replay_metrics';
  }
  if (repairWindowStatus == 'expired_over_3h') {
    return 'exclude_or_replace_from_complete_replay_metrics';
  }
  return 'exclude_until_repairability_is_known';
}

DateTime _currentJstWallClock() {
  final jst = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(
    jst.year,
    jst.month,
    jst.day,
    jst.hour,
    jst.minute,
    jst.second,
    jst.millisecond,
    jst.microsecond,
  );
}

DateTime? _parseJstWallClock(String? value) {
  if (value == null || value.length < 19) return null;
  return DateTime.tryParse(value.substring(0, 19));
}

Map<String, Object?> _captureManifest(
  String captureDirectory,
  List<String> errors,
) {
  if (captureDirectory.isEmpty) return const {};
  final manifest = File('$captureDirectory/capture_manifest.json');
  if (!manifest.existsSync()) {
    errors.add('capture_manifest_missing:${manifest.path}');
    return const {};
  }
  return _readJsonObject(manifest, errors);
}

List<Map<String, Object?>> _failedRecords(Map<String, Object?> manifest) {
  return [
    for (final raw in _list(manifest['records']))
      if (_map(raw)['ok'] == false)
        {
          'timeJst': _map(raw)['timeJst'],
          'layer': _map(raw)['layer'],
          'file': _map(raw)['file'],
          'qualityFlags': _list(_map(raw)['qualityFlags']),
        },
  ];
}

Map<String, Object?> _readJsonObject(File file, List<String> errors) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) return decoded;
    errors.add('json_not_object:${file.path}');
  } on FormatException catch (error) {
    errors.add('json_invalid:${file.path}:${error.message}');
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

Set<String>? _caseIdsFromArgs(List<String> args) {
  final values = <String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--case-id' && i + 1 < args.length) values.add(args[i + 1]);
    if (arg.startsWith('--case-id=')) {
      values.add(arg.substring('--case-id='.length));
    }
  }
  return values.isEmpty ? null : values;
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) => [
  for (final item in _list(value))
    if (item != null) item.toString(),
];

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
