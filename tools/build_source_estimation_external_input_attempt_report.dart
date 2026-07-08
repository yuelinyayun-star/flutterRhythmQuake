import 'dart:convert';
import 'dart:io';

const _defaultQueuePath =
    '.dart_tool/source_estimation_external_input_queue/report.json';
const _defaultAttemptsPath =
    'docs/data/source_estimation_external_input_attempts.json';
const _defaultOutput =
    '.dart_tool/source_estimation_external_input_attempts/report.json';
const _defaultMarkdown =
    'docs/baselines/source_estimation_external_input_attempts.generated.md';

void main(List<String> args) {
  final queuePath = _argument(args, '--queue') ?? _defaultQueuePath;
  final attemptsPath = _argument(args, '--attempts') ?? _defaultAttemptsPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ExternalInputAttemptReport.build(
    queueFile: File(queuePath),
    attemptsFile: File(attemptsPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-estimation external input attempt report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildSourceEstimationExternalInputAttemptJson({
  String queuePath = _defaultQueuePath,
  String attemptsPath = _defaultAttemptsPath,
}) {
  return _ExternalInputAttemptReport.build(
    queueFile: File(queuePath),
    attemptsFile: File(attemptsPath),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ExternalInputAttemptReport {
  final String queuePath;
  final String attemptsPath;
  final List<_ExternalInputAttempt> attempts;
  final List<String> errors;
  final List<String> warnings;

  const _ExternalInputAttemptReport({
    required this.queuePath,
    required this.attemptsPath,
    required this.attempts,
    required this.errors,
    required this.warnings,
  });

  factory _ExternalInputAttemptReport.build({
    required File queueFile,
    required File attemptsFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final queue = _readJson(queueFile, errors);
    final attemptsManifest = _readJson(attemptsFile, errors);
    final queuedKeys = _queuedInputKeys(queue);

    if (attemptsManifest['schemaVersion'] !=
        'source_estimation_external_input_attempts_v1') {
      errors.add('unexpected_external_input_attempts_schema');
    }

    final rawAttempts = attemptsManifest['attempts'];
    final attempts = <_ExternalInputAttempt>[];
    final seenAttemptIds = <String>{};
    if (rawAttempts is List) {
      for (final rawAttempt in rawAttempts) {
        final attempt = _ExternalInputAttempt.fromAny(rawAttempt, errors);
        if (attempt == null) continue;
        if (!seenAttemptIds.add(attempt.attemptId)) {
          errors.add('duplicate_attempt_id:${attempt.attemptId}');
        }
        if (!queuedKeys.contains(attempt.queueKey)) {
          warnings.add(
            'attempt_references_nonqueued_input:${attempt.queueKey}',
          );
        }
        if (attempt.automaticClearance) {
          errors.add('attempt_allows_automatic_clearance:${attempt.attemptId}');
        }
        if (attempt.evidenceStrength != 'negative_attempt_only') {
          errors.add('attempt_has_nonnegative_evidence:${attempt.attemptId}');
        }
        attempts.add(attempt);
      }
    } else {
      errors.add('external_input_attempts_missing_attempts');
    }

    if (attempts.isEmpty && errors.isEmpty) {
      warnings.add('external_input_attempts_empty');
    }

    attempts.sort((left, right) {
      final caseId = left.caseId.compareTo(right.caseId);
      if (caseId != 0) return caseId;
      return left.attemptId.compareTo(right.attemptId);
    });

    return _ExternalInputAttemptReport(
      queuePath: queueFile.path,
      attemptsPath: attemptsFile.path,
      attempts: attempts,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final typeCounts = <String, int>{};
    var automaticClearanceCount = 0;
    var negativeAttemptOnlyCount = 0;
    for (final attempt in attempts) {
      typeCounts[attempt.inputType] = (typeCounts[attempt.inputType] ?? 0) + 1;
      if (attempt.automaticClearance) automaticClearanceCount++;
      if (attempt.evidenceStrength == 'negative_attempt_only') {
        negativeAttemptOnlyCount++;
      }
    }
    return {
      'schemaVersion': 'source_estimation_external_input_attempt_report_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'queuePath': queuePath,
      'attemptsPath': attemptsPath,
      'summary': {
        'attemptCount': attempts.length,
        'inputTypeCounts': typeCounts,
        'automaticClearanceCount': automaticClearanceCount,
        'negativeAttemptOnlyCount': negativeAttemptOnlyCount,
      },
      'errors': errors,
      'warnings': warnings,
      'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final typeCounts = (summary['inputTypeCounts'] as Map)
        .cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Source Estimation External Input Attempts')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Queue: `$queuePath`')
      ..writeln('- Attempts: `$attemptsPath`')
      ..writeln('- Attempt count: `${summary['attemptCount']}`')
      ..writeln(
        '- Automatic clearances: `${summary['automaticClearanceCount']}`',
      )
      ..writeln(
        '- Negative-attempt-only rows: '
        '`${summary['negativeAttemptOnlyCount']}`',
      )
      ..writeln()
      ..writeln('## Input Type Counts')
      ..writeln()
      ..writeln('| Input type | Count |')
      ..writeln('| --- | ---: |');
    for (final type in typeCounts.keys.toList()..sort()) {
      buffer.writeln('| `$type` | ${typeCounts[type]} |');
    }
    buffer
      ..writeln()
      ..writeln('## Validation')
      ..writeln()
      ..writeln(
        errors.isEmpty
            ? '- Errors: none'
            : '- Errors: `${errors.join('`, `')}`',
      )
      ..writeln(
        warnings.isEmpty
            ? '- Warnings: none'
            : '- Warnings: `${warnings.join('`, `')}`',
      )
      ..writeln()
      ..writeln('## Attempts')
      ..writeln()
      ..writeln('| Case | Type | Method | Target | Result | Clearance |')
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final attempt in attempts) {
      buffer.writeln(
        '| `${attempt.caseId}` | `${attempt.inputType}` | '
        '`${attempt.method}` | ${attempt.target} | `${attempt.result}` | '
        '`${attempt.automaticClearance}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- These attempts are operational notes only. They do not clear capture '
        'repair, source truth, final catalog or split blockers.',
      )
      ..writeln(
        '- A negative attempt is not proof that an input is impossible to '
        'obtain; it only prevents repeated untracked searches.',
      );
    return buffer.toString();
  }
}

class _ExternalInputAttempt {
  final String attemptId;
  final String inputType;
  final String caseId;
  final String attemptedAtUtc;
  final String method;
  final String target;
  final String result;
  final String evidenceStrength;
  final bool automaticClearance;
  final String notes;

  const _ExternalInputAttempt({
    required this.attemptId,
    required this.inputType,
    required this.caseId,
    required this.attemptedAtUtc,
    required this.method,
    required this.target,
    required this.result,
    required this.evidenceStrength,
    required this.automaticClearance,
    required this.notes,
  });

  String get queueKey => '$inputType::$caseId';

  static _ExternalInputAttempt? fromAny(Object? raw, List<String> errors) {
    if (raw is! Map) {
      errors.add('external_input_attempt_not_object');
      return null;
    }
    final data = raw.cast<String, Object?>();
    final attempt = _ExternalInputAttempt(
      attemptId: _string(data['attemptId']),
      inputType: _string(data['inputType']),
      caseId: _string(data['caseId']),
      attemptedAtUtc: _string(data['attemptedAtUtc']),
      method: _string(data['method']),
      target: _string(data['target']),
      result: _string(data['result']),
      evidenceStrength: _string(data['evidenceStrength']),
      automaticClearance: data['automaticClearance'] == true,
      notes: _string(data['notes']),
    );
    final requiredFields = {
      'attemptId': attempt.attemptId,
      'inputType': attempt.inputType,
      'caseId': attempt.caseId,
      'attemptedAtUtc': attempt.attemptedAtUtc,
      'method': attempt.method,
      'target': attempt.target,
      'result': attempt.result,
      'evidenceStrength': attempt.evidenceStrength,
      'notes': attempt.notes,
    };
    for (final entry in requiredFields.entries) {
      if (entry.value.isEmpty) {
        errors.add('external_input_attempt_missing_${entry.key}');
      }
    }
    if (DateTime.tryParse(attempt.attemptedAtUtc) == null) {
      errors.add('external_input_attempt_invalid_time:${attempt.attemptId}');
    }
    return attempt;
  }

  Map<String, Object?> toJson() {
    return {
      'attemptId': attemptId,
      'inputType': inputType,
      'caseId': caseId,
      'attemptedAtUtc': attemptedAtUtc,
      'method': method,
      'target': target,
      'result': result,
      'evidenceStrength': evidenceStrength,
      'automaticClearance': automaticClearance,
      'notes': notes,
    };
  }
}

Map<String, Object?> _readJson(File file, List<String> errors) {
  if (!file.existsSync()) {
    errors.add('json_file_missing:${file.path}');
    return const {};
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map) return decoded.cast<String, Object?>();
    errors.add('json_file_not_object:${file.path}');
  } catch (error) {
    errors.add('json_file_decode_failed:${file.path}:$error');
  }
  return const {};
}

Set<String> _queuedInputKeys(Map<String, Object?> queue) {
  final rawItems = queue['items'];
  if (rawItems is! List) return const {};
  return rawItems
      .whereType<Map>()
      .map((item) {
        final inputType = _string(item['inputType']);
        final caseId = _string(item['caseId']);
        return inputType.isEmpty || caseId.isEmpty ? '' : '$inputType::$caseId';
      })
      .where((key) => key.isNotEmpty)
      .toSet();
}

String _string(Object? value) => value?.toString().trim() ?? '';
