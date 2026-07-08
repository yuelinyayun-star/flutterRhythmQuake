import 'dart:convert';
import 'dart:io';

const _defaultDecisionPath =
    'docs/data/hinet_capture_provenance_review_decisions.json';

void main(List<String> args) {
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final inputPath = _argument(args, '--input');
  final dryRun = args.contains('--dry-run');

  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/import_hinet_capture_exclusion_decision.dart '
      '--input exclusion.json '
      '[--decisions docs/data/hinet_capture_provenance_review_decisions.json] '
      '[--dry-run]',
    );
    exitCode = 64;
    return;
  }

  final decisionFile = File(decisionPath);
  final inputFile = File(inputPath);
  if (!decisionFile.existsSync()) {
    stderr.writeln('Decision file not found: ${decisionFile.path}');
    exitCode = 66;
    return;
  }
  if (!inputFile.existsSync()) {
    stderr.writeln('Input exclusion file not found: ${inputFile.path}');
    exitCode = 66;
    return;
  }

  final decisionsJson =
      jsonDecode(decisionFile.readAsStringSync()) as Map<String, Object?>;
  final inputJson =
      jsonDecode(inputFile.readAsStringSync()) as Map<String, Object?>;

  final errors = validateHinetCaptureExclusionDecisionInput(
    decisionsJson: decisionsJson,
    inputJson: inputJson,
  );
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln(error);
    }
    exitCode = 65;
    return;
  }

  final caseId = inputJson['caseId'].toString();
  final cases = _list(
    decisionsJson['cases'],
  ).map((entry) => _map(entry)).toList(growable: true);
  final index = cases.indexWhere((entry) => entry['caseId'] == caseId);
  if (index < 0) {
    stderr.writeln('No capture decision slot found for caseId: $caseId');
    exitCode = 65;
    return;
  }

  final existingCase = cases[index];
  cases[index] = <String, Object?>{
    'caseId': caseId,
    'decisionStatus': 'capture_frame_exclusion_approved',
    'reviewedAtUtc': inputJson['reviewedAtUtc'],
    'reviewer': inputJson['reviewer'],
    'exclusionApproved': true,
    'excludedFiles': _stringList(inputJson['excludedFiles']),
    'exclusionReason': inputJson['exclusionReason'],
    'requiredActions': existingCase['requiredActions'],
    'notes': existingCase['notes'],
  };
  decisionsJson['cases'] = cases;

  if (dryRun) {
    stdout.writeln('dry-run: capture exclusion decision is valid for $caseId');
    return;
  }

  decisionFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(decisionsJson)}\n',
  );
  stdout.writeln('imported capture exclusion decision for $caseId');
  stdout.writeln('decisions: ${decisionFile.path}');
}

List<String> validateHinetCaptureExclusionDecisionInput({
  required Map<String, Object?> decisionsJson,
  required Map<String, Object?> inputJson,
}) {
  final errors = <String>[];
  if (decisionsJson['schemaVersion'] !=
      'hinet_capture_provenance_review_decisions_v1') {
    errors.add('unexpected_capture_decisions_schema');
  }
  if (_containsSensitiveKey(inputJson)) {
    errors.add('input_contains_sensitive_auth_material');
  }

  for (final field in const [
    'caseId',
    'decisionStatus',
    'reviewedAtUtc',
    'reviewer',
    'excludedFiles',
    'exclusionReason',
  ]) {
    final value = inputJson[field];
    if (value == null ||
        (value is String && value.trim().isEmpty) ||
        (value is List && value.isEmpty)) {
      errors.add('missing_required_field:$field');
    } else if (_containsUnresolvedPlaceholder(value)) {
      errors.add('unresolved_placeholder:$field');
    }
  }

  final caseId = inputJson['caseId']?.toString() ?? '';
  final matchingCases = _list(
    decisionsJson['cases'],
  ).map((entry) => _map(entry)).where((entry) => entry['caseId'] == caseId);
  if (caseId.isEmpty) {
    errors.add('missing_case_id');
  } else if (matchingCases.isEmpty) {
    errors.add('case_not_in_capture_decisions:$caseId');
  } else if (matchingCases.first['decisionStatus'] !=
      'pending_capture_repair_or_exclusion') {
    errors.add('case_decision_is_not_pending:$caseId');
  }

  if (inputJson['decisionStatus'] != 'capture_frame_exclusion_approved') {
    errors.add('unsupported_decision_status:${inputJson['decisionStatus']}');
  }
  if (inputJson['exclusionApproved'] != true) {
    errors.add('exclusion_approved_must_be_true');
  }
  if (DateTime.tryParse(inputJson['reviewedAtUtc']?.toString() ?? '') == null) {
    errors.add('reviewed_at_not_parseable');
  }

  final excludedFiles = _stringList(inputJson['excludedFiles']);
  if (excludedFiles.toSet().length != excludedFiles.length) {
    errors.add('duplicate_excluded_files');
  }
  if (excludedFiles.any((file) => file.trim().isEmpty)) {
    errors.add('empty_excluded_file');
  }

  final captureIssue = _map(inputJson['_captureIssue']);
  final failedCount = _asInt(captureIssue['captureFailedGifCount']);
  final missingCount = _asInt(captureIssue['captureMissingFrameCount']);
  if (failedCount != null || missingCount != null) {
    final requiredExcludedCount = (failedCount ?? 0) + (missingCount ?? 0);
    if (requiredExcludedCount > 0 &&
        excludedFiles.length < requiredExcludedCount) {
      errors.add('excluded_files_do_not_cover_capture_issue');
    }
  }

  return errors;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool _containsSensitiveKey(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key.contains('password') ||
          key.contains('cookie') ||
          key.contains('authorization') ||
          key.contains('session') ||
          key.contains('token') ||
          key == 'username' ||
          key == 'user') {
        return true;
      }
      if (_containsSensitiveKey(entry.value)) return true;
    }
  } else if (value is List) {
    return value.any(_containsSensitiveKey);
  }
  return false;
}

bool _containsUnresolvedPlaceholder(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.startsWith('<') && trimmed.endsWith('>');
  }
  if (value is List) return value.any(_containsUnresolvedPlaceholder);
  if (value is Map) return value.values.any(_containsUnresolvedPlaceholder);
  return false;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((item) => item.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
