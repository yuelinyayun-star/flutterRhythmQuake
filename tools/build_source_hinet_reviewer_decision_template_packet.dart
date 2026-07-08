import 'dart:convert';
import 'dart:io';

const _defaultStagingPath =
    '.dart_tool/source_hinet_reviewer_decision_staging/report.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_reviewer_decision_templates/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_reviewer_decision_templates.generated.md';
const _defaultTemplateDirectory =
    '.dart_tool/source_hinet_reviewer_decision_templates/files';

const _expectedCaseIds = {
  '20260622_iwate_east_offshore_m30_hinet',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260623_tokachi_southeast_offshore_m34_hinet',
};

void main(List<String> args) {
  final stagingPath = _argument(args, '--staging') ?? _defaultStagingPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;
  final templateDirectory =
      _argument(args, '--template-directory') ?? _defaultTemplateDirectory;

  final report = buildSourceHinetReviewerDecisionTemplatePacketJson(
    stagingPath: stagingPath,
    templateDirectory: templateDirectory,
    writeTemplateFiles: true,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net reviewer-decision template packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
  stdout.writeln('files: $templateDirectory');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetReviewerDecisionTemplatePacketJson({
  String stagingPath = _defaultStagingPath,
  String templateDirectory = _defaultTemplateDirectory,
  bool writeTemplateFiles = false,
}) {
  final errors = <String>[];
  final staging = _readJsonFile(
    stagingPath,
    errors,
    expectedSchema: 'source_hinet_reviewer_decision_staging_v1',
    missingError: 'source_hinet_reviewer_decision_staging_missing',
  );
  final templateDir = Directory(templateDirectory);
  if (writeTemplateFiles) templateDir.createSync(recursive: true);

  final cases =
      _list(staging['cases'])
          .map(_map)
          .map(
            (entry) => _casePacket(
              entry,
              templateDirectory: templateDirectory,
              writeTemplateFiles: writeTemplateFiles,
            ),
          )
          .toList(growable: false)
        ..sort(
          (left, right) =>
              left['caseId'].toString().compareTo(right['caseId'].toString()),
        );

  final summary = _summary(cases);
  final validation = _validation(
    staging: staging,
    cases: cases,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_reviewer_decision_templates_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {'sourceHinetReviewerDecisionStaging': stagingPath},
    'policy': const {
      'manualTemplateOnly': true,
      'writesDecisionLedger': false,
      'acceptsTruthQuality': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'requiresEligibleStagingCase': true,
      'notes':
          'Templates are emitted only for staging-eligible cases. Filling one still requires the importer.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'cases': cases,
  };
}

Map<String, Object?> _casePacket(
  Map<String, Object?> stagingCase, {
  required String templateDirectory,
  required bool writeTemplateFiles,
}) {
  final caseId = stagingCase['caseId']?.toString() ?? '';
  final eligible = stagingCase['reviewerDecisionEligible'] == true;
  final readyEvidenceTypes = _stringList(stagingCase['readyEvidenceTypes']);
  final templateFile = eligible
      ? '$templateDirectory${Platform.pathSeparator}$caseId.json'
      : null;
  final payload = eligible
      ? <String, Object?>{
          'caseId': caseId,
          'decisionStatus':
              '<accepted_constrained_reference-or-rejected_constrained_reference>',
          'reviewedAtUtc': '<fill-reviewed-at-utc>',
          'reviewer': '<fill-reviewer-id>',
          'evidenceType': readyEvidenceTypes.isEmpty
              ? '<fill-ready-evidence-type>'
              : readyEvidenceTypes.single,
          'evidence': ['<fill-reviewed-evidence-summary-or-url>'],
          'notes': '<fill-review-notes>',
          'acceptedForConstrainedReferenceSplit':
              '<true-only-for-accepted_constrained_reference>',
          'splitAssignmentAllowed': false,
          'metricPromotionAllowed': false,
        }
      : null;

  if (writeTemplateFiles && templateFile != null && payload != null) {
    File(templateFile)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
      );
  }
  final templateFields = (payload?.keys.toList() ?? <String>[])..sort();

  return {
    'caseId': caseId,
    'reviewerDecisionEligible': eligible,
    'combinedEvidenceStatus': stagingCase['combinedEvidenceStatus'],
    'readyEvidenceTypes': readyEvidenceTypes,
    'blockingReasons': _stringList(stagingCase['blockingReasons']),
    'templateFile': templateFile,
    'templateEmitted': templateFile != null,
    'templateFields': templateFields,
    'importDryRunCommand': templateFile == null
        ? null
        : 'dart run tools\\import_source_hinet_reviewer_decision.dart '
              '--input $templateFile --dry-run',
    'manualReviewRequired': true,
    'decisionLedgerWriteAllowed': false,
    'truthQualityAcceptanceAllowed': false,
    'metricPromotionAllowed': false,
    'splitAssignmentAllowed': false,
  };
}

Map<String, Object?> _summary(List<Map<String, Object?>> cases) {
  return {
    'caseCount': cases.length,
    'reviewerDecisionEligibleCount': cases
        .where((entry) => entry['reviewerDecisionEligible'] == true)
        .length,
    'templateEmittedCount': cases
        .where((entry) => entry['templateEmitted'] == true)
        .length,
    'blockedCount': cases
        .where((entry) => entry['reviewerDecisionEligible'] != true)
        .length,
    'decisionLedgerWriteAllowedCount': cases
        .where((entry) => entry['decisionLedgerWriteAllowed'] == true)
        .length,
    'truthQualityAcceptanceAllowedCount': cases
        .where((entry) => entry['truthQualityAcceptanceAllowed'] == true)
        .length,
    'metricPromotionAllowedCount': cases
        .where((entry) => entry['metricPromotionAllowed'] == true)
        .length,
    'splitAssignmentAllowedCount': cases
        .where((entry) => entry['splitAssignmentAllowed'] == true)
        .length,
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> staging,
  required List<Map<String, Object?>> cases,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (staging['status'] != 'pass') {
    violations.add('source_hinet_reviewer_decision_staging_not_pass');
  }
  final caseIds = cases
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (caseIds.length != _expectedCaseIds.length ||
      !caseIds.containsAll(_expectedCaseIds)) {
    violations.add('unexpected_reviewer_decision_template_case_set');
  }
  if (_intValue(summary['caseCount']) != 3) {
    violations.add('unexpected_case_count');
  }
  if (_intValue(summary['templateEmittedCount']) !=
      _intValue(summary['reviewerDecisionEligibleCount'])) {
    violations.add('template_count_does_not_match_eligible_count');
  }
  if (_intValue(summary['decisionLedgerWriteAllowedCount']) != 0) {
    violations.add('decision_ledger_write_allowed');
  }
  if (_intValue(summary['truthQualityAcceptanceAllowedCount']) != 0) {
    violations.add('truth_quality_acceptance_allowed');
  }
  if (_intValue(summary['metricPromotionAllowedCount']) != 0) {
    violations.add('metric_promotion_allowed');
  }
  if (_intValue(summary['splitAssignmentAllowedCount']) != 0) {
    violations.add('split_assignment_allowed');
  }
  for (final entry in cases) {
    if (entry['reviewerDecisionEligible'] == true &&
        _stringList(entry['readyEvidenceTypes']).isEmpty) {
      violations.add('${entry['caseId']}:eligible_without_ready_evidence');
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
    ..writeln('# Source Hi-net Reviewer-Decision Templates')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Cases: `${summary['caseCount']}`')
    ..writeln(
      '- Reviewer-decision eligible: '
      '`${summary['reviewerDecisionEligibleCount']}`',
    )
    ..writeln('- Templates emitted: `${summary['templateEmittedCount']}`')
    ..writeln('- Blocked: `${summary['blockedCount']}`')
    ..writeln(
      '- Decision ledger writes allowed: '
      '`${summary['decisionLedgerWriteAllowedCount']}`',
    )
    ..writeln(
      '- Truth-quality acceptance allowed: '
      '`${summary['truthQualityAcceptanceAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Cases')
    ..writeln()
    ..writeln(
      '| Case | Eligible | Ready evidence | Blockers | Template | Import dry-run |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final rawCase in _list(report['cases'])) {
    final entry = _map(rawCase);
    buffer.writeln(
      '| `${entry['caseId']}` | `${entry['reviewerDecisionEligible']}` | '
      '`${_stringList(entry['readyEvidenceTypes']).join('`, `')}` | '
      '`${_stringList(entry['blockingReasons']).join('`, `')}` | '
      '`${entry['templateFile']}` | `${entry['importDryRunCommand']}` |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Templates are emitted only after staging marks a case eligible.',
    )
    ..writeln(
      '- A filled template still must pass the reviewer-decision importer.',
    )
    ..writeln(
      '- This packet does not write the decision ledger, assign splits or change metric eligibility.',
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

Map<String, Object?> _readJsonFile(
  String path,
  List<String> errors, {
  required String expectedSchema,
  required String missingError,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('$missingError:$path');
    return <String, Object?>{};
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  if (data['schemaVersion'] != expectedSchema) {
    errors.add('unexpected_schema:$path');
  }
  return data;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _codeList(List<Object?> values) =>
    values.map((value) => '`$value`').join(', ');

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((entry) => entry.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
