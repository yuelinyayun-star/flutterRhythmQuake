import 'dart:convert';
import 'dart:io';

const _defaultRowsPath = 'docs/data/hinet_authenticated_export_rows.json';

void main(List<String> args) {
  final rowsPath = _argument(args, '--rows') ?? _defaultRowsPath;
  final inputPath = _argument(args, '--input');
  final dryRun = args.contains('--dry-run');

  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/import_hinet_authenticated_export_row.dart '
      '--input row.json [--rows docs/data/hinet_authenticated_export_rows.json] '
      '[--dry-run]',
    );
    exitCode = 64;
    return;
  }

  final rowsFile = File(rowsPath);
  final inputFile = File(inputPath);
  if (!rowsFile.existsSync()) {
    stderr.writeln('Rows file not found: ${rowsFile.path}');
    exitCode = 66;
    return;
  }
  if (!inputFile.existsSync()) {
    stderr.writeln('Input row file not found: ${inputFile.path}');
    exitCode = 66;
    return;
  }

  final rowsJson =
      jsonDecode(rowsFile.readAsStringSync()) as Map<String, Object?>;
  final inputJson =
      jsonDecode(inputFile.readAsStringSync()) as Map<String, Object?>;

  final errors = validateHinetAuthenticatedExportRowInput(
    rowsJson: rowsJson,
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
  final requiredFields = _stringList(rowsJson['submittedRowRequiredFields']);
  final sanitizedRow = <String, Object?>{
    for (final field in requiredFields) field: inputJson[field],
  };

  final rows = _list(
    rowsJson['rows'],
  ).map((entry) => _map(entry)).toList(growable: true);
  final index = rows.indexWhere((entry) => entry['caseId'] == caseId);
  if (index < 0) {
    stderr.writeln('No pending row slot found for caseId: $caseId');
    exitCode = 65;
    return;
  }

  rows[index] = <String, Object?>{
    'caseId': caseId,
    'status': 'submitted_for_review',
    'submittedRow': sanitizedRow,
    'rejectionReason': null,
    'decisionImpact': 'none_review_required',
  };
  rowsJson['rows'] = rows;

  if (dryRun) {
    stdout.writeln('dry-run: authenticated export row is valid for $caseId');
    return;
  }

  rowsFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(rowsJson)}\n',
  );
  stdout.writeln('imported authenticated export row for $caseId');
  stdout.writeln('rows: ${rowsFile.path}');
}

List<String> validateHinetAuthenticatedExportRowInput({
  required Map<String, Object?> rowsJson,
  required Map<String, Object?> inputJson,
}) {
  final errors = <String>[];
  if (rowsJson['schemaVersion'] != 'hinet_authenticated_export_rows_v1') {
    errors.add('unexpected_rows_schema');
  }
  if (_containsSensitiveKey(inputJson)) {
    errors.add('input_contains_sensitive_auth_material');
  }

  final requiredFields = _stringList(rowsJson['submittedRowRequiredFields']);
  final acceptedSourceTypes = _stringList(
    rowsJson['acceptedSourceTypes'],
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
    final rows = _list(rowsJson['rows']).map((entry) => _map(entry));
    final matchingRows = rows.where((entry) => entry['caseId'] == caseId);
    if (matchingRows.isEmpty) {
      errors.add('case_not_in_authenticated_export_rows:$caseId');
    } else if (matchingRows.first['status'] != 'pending_export') {
      errors.add('case_row_is_not_pending_export:$caseId');
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
  if (DateTime.tryParse(inputJson['originTimeJst']?.toString() ?? '') == null) {
    errors.add('origin_time_not_parseable');
  }
  for (final field in const ['latitude', 'longitude', 'depthKm', 'magnitude']) {
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

List<String> _validateQueryTarget(Map<String, Object?> inputJson) {
  final target = _map(inputJson['_queryTarget']);
  if (target.isEmpty) return const [];

  final errors = <String>[];
  final caseId = inputJson['caseId']?.toString() ?? '';
  final targetCaseId = target['caseId']?.toString() ?? '';
  if (targetCaseId.isNotEmpty && targetCaseId != caseId) {
    errors.add('query_target_case_mismatch:$targetCaseId');
  }

  final originTime = DateTime.tryParse(
    inputJson['originTimeJst']?.toString() ?? '',
  );
  final window = _parseQueryWindow(target['queryWindowJst']);
  if (window != null && originTime != null) {
    if (originTime.isBefore(window.start) || originTime.isAfter(window.end)) {
      errors.add('origin_time_outside_query_window');
    }
  }

  final latitude = _numValue(inputJson['latitude']);
  final longitude = _numValue(inputJson['longitude']);
  final targetLatitude = _numValue(target['targetLatitude']);
  final targetLongitude = _numValue(target['targetLongitude']);
  if (latitude != null &&
      longitude != null &&
      targetLatitude != null &&
      targetLongitude != null) {
    final latDelta = (latitude - targetLatitude).abs();
    final lonDelta = (longitude - targetLongitude).abs();
    if (latDelta > 1.0 || lonDelta > 1.0) {
      errors.add('row_location_outside_target_tolerance');
    }
  }

  final magnitude = _numValue(inputJson['magnitude']);
  final targetMagnitude = _numValue(target['targetMagnitude']);
  if (magnitude != null &&
      targetMagnitude != null &&
      (magnitude - targetMagnitude).abs() > 1.0) {
    errors.add('row_magnitude_outside_target_tolerance');
  }

  return errors;
}

({DateTime start, DateTime end})? _parseQueryWindow(Object? value) {
  if (value is Map) {
    final map = value.cast<String, Object?>();
    final start = DateTime.tryParse(map['start']?.toString() ?? '');
    final end = DateTime.tryParse(map['end']?.toString() ?? '');
    if (start != null && end != null) return (start: start, end: end);
  }
  if (value is String) {
    final parts = value.split('..');
    if (parts.length == 2) {
      final start = DateTime.tryParse(parts[0]);
      final end = DateTime.tryParse(parts[1]);
      if (start != null && end != null) return (start: start, end: end);
    }
  }
  return null;
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
