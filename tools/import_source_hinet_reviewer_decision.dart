import 'dart:convert';
import 'dart:io';

const _defaultDecisionPath =
    'docs/data/hinet_truth_quality_review_decisions.json';
const _defaultStagingPath =
    '.dart_tool/source_hinet_reviewer_decision_staging/report.json';

const _allowedDecisionStatuses = {
  'accepted_constrained_reference',
  'rejected_constrained_reference',
};

void main(List<String> args) {
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final stagingPath = _argument(args, '--staging') ?? _defaultStagingPath;
  final inputPath = _argument(args, '--input');
  final dryRun = args.contains('--dry-run');

  if (inputPath == null) {
    stderr.writeln(
      'Usage: dart run tools/import_source_hinet_reviewer_decision.dart '
      '--input decision.json '
      '[--decisions docs/data/hinet_truth_quality_review_decisions.json] '
      '[--staging .dart_tool/source_hinet_reviewer_decision_staging/report.json] '
      '[--dry-run]',
    );
    exitCode = 64;
    return;
  }

  final decisionFile = File(decisionPath);
  final stagingFile = File(stagingPath);
  final inputFile = File(inputPath);
  if (!decisionFile.existsSync()) {
    stderr.writeln('Decision file not found: ${decisionFile.path}');
    exitCode = 66;
    return;
  }
  if (!stagingFile.existsSync()) {
    stderr.writeln('Staging report not found: ${stagingFile.path}');
    exitCode = 66;
    return;
  }
  if (!inputFile.existsSync()) {
    stderr.writeln('Input decision file not found: ${inputFile.path}');
    exitCode = 66;
    return;
  }

  final decisionsJson =
      jsonDecode(decisionFile.readAsStringSync()) as Map<String, Object?>;
  final stagingJson =
      jsonDecode(stagingFile.readAsStringSync()) as Map<String, Object?>;
  final inputJson =
      jsonDecode(inputFile.readAsStringSync()) as Map<String, Object?>;

  final errors = validateSourceHinetReviewerDecisionInput(
    decisionsJson: decisionsJson,
    stagingJson: stagingJson,
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
    stderr.writeln('No Hi-net truth-quality decision slot found: $caseId');
    exitCode = 65;
    return;
  }

  final accepted =
      inputJson['decisionStatus'] == 'accepted_constrained_reference';
  final existingCase = cases[index];
  cases[index] = <String, Object?>{
    'caseId': caseId,
    'decisionStatus': inputJson['decisionStatus'],
    'acceptedForConstrainedReferenceSplit': accepted,
    'reviewedAtUtc': inputJson['reviewedAtUtc'],
    'reviewer': inputJson['reviewer'],
    'evidence': _stringList(inputJson['evidence']),
    'requiredActions': existingCase['requiredActions'],
    'notes': inputJson['notes'],
    'decisionImport': {
      'source': 'source_hinet_reviewer_decision_import',
      'evidenceType': inputJson['evidenceType'],
      'splitAssignmentAllowed': false,
      'metricPromotionAllowed': false,
    },
  };
  decisionsJson['cases'] = cases;

  if (dryRun) {
    stdout.writeln('dry-run: reviewer decision is valid for $caseId');
    return;
  }

  decisionFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(decisionsJson)}\n',
  );
  stdout.writeln('imported source Hi-net reviewer decision for $caseId');
  stdout.writeln('decisions: ${decisionFile.path}');
}

List<String> validateSourceHinetReviewerDecisionInput({
  required Map<String, Object?> decisionsJson,
  required Map<String, Object?> stagingJson,
  required Map<String, Object?> inputJson,
}) {
  final errors = <String>[];
  if (decisionsJson['schemaVersion'] !=
      'hinet_truth_quality_review_decisions_v1') {
    errors.add('unexpected_hinet_truth_quality_decisions_schema');
  }
  if (stagingJson['schemaVersion'] !=
      'source_hinet_reviewer_decision_staging_v1') {
    errors.add('unexpected_reviewer_decision_staging_schema');
  }
  if (stagingJson['status'] != 'pass') {
    errors.add('reviewer_decision_staging_not_pass');
  }
  if (_containsSensitiveKey(inputJson)) {
    errors.add('input_contains_sensitive_auth_material');
  }

  for (final field in const [
    'caseId',
    'decisionStatus',
    'reviewedAtUtc',
    'reviewer',
    'evidenceType',
    'evidence',
    'notes',
    'splitAssignmentAllowed',
    'metricPromotionAllowed',
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
  final decisionStatus = inputJson['decisionStatus']?.toString() ?? '';
  final accepted = decisionStatus == 'accepted_constrained_reference';
  final rejected = decisionStatus == 'rejected_constrained_reference';
  if (caseId.isEmpty) {
    errors.add('missing_case_id');
  }
  if (!_allowedDecisionStatuses.contains(decisionStatus)) {
    errors.add('unsupported_decision_status:$decisionStatus');
  }
  if (DateTime.tryParse(inputJson['reviewedAtUtc']?.toString() ?? '') == null) {
    errors.add('reviewed_at_not_parseable');
  }

  final decisionCases = _list(
    decisionsJson['cases'],
  ).map((entry) => _map(entry)).where((entry) => entry['caseId'] == caseId);
  if (caseId.isNotEmpty && decisionCases.isEmpty) {
    errors.add('case_not_in_hinet_truth_quality_decisions:$caseId');
  } else if (decisionCases.isNotEmpty) {
    final decision = decisionCases.first;
    if (decision['decisionStatus'] != 'pending_manual_review') {
      errors.add('case_decision_is_not_pending_manual_review:$caseId');
    }
    if (decision['acceptedForConstrainedReferenceSplit'] == true) {
      errors.add('case_already_accepted:$caseId');
    }
  }

  final stagingCases = _list(
    stagingJson['cases'],
  ).map((entry) => _map(entry)).where((entry) => entry['caseId'] == caseId);
  if (caseId.isNotEmpty && stagingCases.isEmpty) {
    errors.add('case_not_in_reviewer_decision_staging:$caseId');
  } else if (stagingCases.isNotEmpty) {
    final stagingCase = stagingCases.first;
    if (stagingCase['reviewerDecisionEligible'] != true) {
      errors.add('case_not_reviewer_decision_eligible:$caseId');
    }
    final readyEvidenceTypes = _stringList(stagingCase['readyEvidenceTypes']);
    final evidenceType = inputJson['evidenceType']?.toString() ?? '';
    if (!readyEvidenceTypes.contains(evidenceType)) {
      errors.add('evidence_type_not_ready:$evidenceType');
    }
    if (_stringList(stagingCase['blockingReasons']).isNotEmpty) {
      errors.add('staging_case_has_blockers:$caseId');
    }
  }

  final evidence = _stringList(inputJson['evidence']);
  if (evidence.isEmpty) {
    errors.add('evidence_must_not_be_empty');
  }
  if (evidence.any((entry) => entry.trim().isEmpty)) {
    errors.add('evidence_contains_empty_entry');
  }
  if (accepted && inputJson['acceptedForConstrainedReferenceSplit'] != true) {
    errors.add('accepted_decision_requires_acceptance_flag');
  }
  if (rejected && inputJson['acceptedForConstrainedReferenceSplit'] != false) {
    errors.add('rejected_decision_requires_false_acceptance_flag');
  }
  if (inputJson['splitAssignmentAllowed'] != false) {
    errors.add('split_assignment_allowed_must_be_false');
  }
  if (inputJson['metricPromotionAllowed'] != false) {
    errors.add('metric_promotion_allowed_must_be_false');
  }

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
