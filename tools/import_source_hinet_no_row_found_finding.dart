import 'dart:convert';
import 'dart:io';

const _defaultFindingsPath =
    'docs/data/source_hinet_no_row_found_findings.json';

void main(List<String> args) {
  final findingsPath = _argument(args, '--findings') ?? _defaultFindingsPath;
  final inputPath = _argument(args, '--input');
  final dryRun = args.contains('--dry-run');

  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/import_source_hinet_no_row_found_finding.dart '
      '--input finding.json '
      '[--findings docs/data/source_hinet_no_row_found_findings.json] '
      '[--dry-run]',
    );
    exitCode = 64;
    return;
  }

  final findingsFile = File(findingsPath);
  final inputFile = File(inputPath);
  if (!findingsFile.existsSync()) {
    stderr.writeln('Findings file not found: ${findingsFile.path}');
    exitCode = 66;
    return;
  }
  if (!inputFile.existsSync()) {
    stderr.writeln('Input finding file not found: ${inputFile.path}');
    exitCode = 66;
    return;
  }

  final findingsJson =
      jsonDecode(findingsFile.readAsStringSync()) as Map<String, Object?>;
  final inputJson =
      jsonDecode(inputFile.readAsStringSync()) as Map<String, Object?>;

  final errors = validateSourceHinetNoRowFoundFindingInput(
    findingsJson: findingsJson,
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
  final requiredFields = _stringList(
    findingsJson['submittedFindingRequiredFields'],
  );
  final sanitizedFinding = <String, Object?>{
    for (final field in requiredFields) field: inputJson[field],
  };

  final findings = _list(
    findingsJson['findings'],
  ).map((entry) => _map(entry)).toList(growable: true);
  final index = findings.indexWhere((entry) => entry['caseId'] == caseId);
  if (index < 0) {
    stderr.writeln('No pending no-row finding slot found for caseId: $caseId');
    exitCode = 65;
    return;
  }

  findings[index] = <String, Object?>{
    'caseId': caseId,
    'status': 'submitted_no_row_found',
    'submittedFinding': sanitizedFinding,
    'rejectionReason': null,
    'decisionImpact': 'none_review_required',
  };
  findingsJson['findings'] = findings;

  if (dryRun) {
    stdout.writeln('dry-run: no-row-found finding is valid for $caseId');
    return;
  }

  findingsFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(findingsJson)}\n',
  );
  stdout.writeln('imported no-row-found finding for $caseId');
  stdout.writeln('findings: ${findingsFile.path}');
}

List<String> validateSourceHinetNoRowFoundFindingInput({
  required Map<String, Object?> findingsJson,
  required Map<String, Object?> inputJson,
}) {
  final errors = <String>[];
  if (findingsJson['schemaVersion'] !=
      'source_hinet_no_row_found_findings_v1') {
    errors.add('unexpected_findings_schema');
  }
  if (_containsSensitiveKey(inputJson)) {
    errors.add('input_contains_sensitive_auth_material');
  }

  final requiredFields = _stringList(
    findingsJson['submittedFindingRequiredFields'],
  );
  final acceptedSourceTypes = _stringList(
    findingsJson['acceptedSourceTypes'],
  ).toSet();
  for (final field in requiredFields) {
    final value = inputJson[field];
    if (value == null || (value is String && value.trim().isEmpty)) {
      errors.add('missing_required_field:$field');
    } else if (value is String && _isUnresolvedPlaceholder(value)) {
      errors.add('unresolved_placeholder:$field');
    }
  }

  final caseId = inputJson['caseId']?.toString() ?? '';
  if (caseId.isEmpty) {
    errors.add('missing_case_id');
  } else {
    final findings = _list(
      findingsJson['findings'],
    ).map((entry) => _map(entry));
    final matchingFindings = findings.where(
      (entry) => entry['caseId'] == caseId,
    );
    if (matchingFindings.isEmpty) {
      errors.add('case_not_in_no_row_findings:$caseId');
    } else if (matchingFindings.first['status'] != 'pending_finding') {
      errors.add('case_no_row_finding_is_not_pending:$caseId');
    }
  }

  final sourceType = inputJson['sourceType']?.toString();
  if (sourceType != null && !acceptedSourceTypes.contains(sourceType)) {
    errors.add('unsupported_source_type:$sourceType');
  }
  if (inputJson['sourceUrl']?.toString().startsWith('https://') != true) {
    errors.add('source_url_must_be_https');
  }
  if (DateTime.tryParse(inputJson['checkedAtUtc']?.toString() ?? '') == null) {
    errors.add('checked_at_not_parseable');
  }
  final searchResult = inputJson['searchResult']?.toString();
  if (searchResult != 'no_event_row_found') {
    errors.add('search_result_must_be_no_event_row_found');
  }
  if (!_looksLikeRange(inputJson['queryWindowJst']?.toString() ?? '')) {
    errors.add('query_window_must_be_range');
  }
  for (final field in const [
    'searchedLatitude',
    'searchedLongitude',
    'searchedMagnitude',
  ]) {
    if (inputJson[field] is! num) {
      errors.add('numeric_field_required:$field');
    }
  }
  errors.addAll(_validateQueryTarget(inputJson));
  return errors;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
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

bool _isUnresolvedPlaceholder(String value) {
  final trimmed = value.trim();
  return trimmed.startsWith('<') && trimmed.endsWith('>');
}

bool _looksLikeRange(String value) {
  final parts = value.split('..');
  if (parts.length != 2) return false;
  return DateTime.tryParse(parts[0]) != null &&
      DateTime.tryParse(parts[1]) != null;
}

List<String> _validateQueryTarget(Map<String, Object?> inputJson) {
  final target = _map(inputJson['_queryTarget']);
  if (target.isEmpty) return const [];

  final errors = <String>[];
  final caseId = inputJson['caseId']?.toString() ?? '';
  final targetCaseId = target['caseId']?.toString() ?? '';
  if (targetCaseId.isNotEmpty && targetCaseId != caseId) {
    errors.add('query_target_case_mismatch:$targetCaseId');
  }

  final queryWindow = inputJson['queryWindowJst']?.toString() ?? '';
  final targetWindow = target['queryWindowJst']?.toString() ?? '';
  if (targetWindow.isNotEmpty && targetWindow != queryWindow) {
    errors.add('query_window_does_not_match_target');
  }

  final searchedLatitude = _numValue(inputJson['searchedLatitude']);
  final searchedLongitude = _numValue(inputJson['searchedLongitude']);
  final targetLatitude = _numValue(target['targetLatitude']);
  final targetLongitude = _numValue(target['targetLongitude']);
  if (searchedLatitude != null &&
      searchedLongitude != null &&
      targetLatitude != null &&
      targetLongitude != null) {
    final latDelta = (searchedLatitude - targetLatitude).abs();
    final lonDelta = (searchedLongitude - targetLongitude).abs();
    if (latDelta > 1.0 || lonDelta > 1.0) {
      errors.add('searched_location_outside_target_tolerance');
    }
  }

  final searchedMagnitude = _numValue(inputJson['searchedMagnitude']);
  final targetMagnitude = _numValue(target['targetMagnitude']);
  if (searchedMagnitude != null &&
      targetMagnitude != null &&
      (searchedMagnitude - targetMagnitude).abs() > 1.0) {
    errors.add('searched_magnitude_outside_target_tolerance');
  }

  return errors;
}

double? _numValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((item) => item.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
