import 'dart:convert';
import 'dart:io';

const _defaultSourceHinetTriagePath =
    '.dart_tool/source_hinet_truth_quality_triage_packet/report.json';
const _defaultAuthenticatedReviewPath =
    '.dart_tool/hinet_authenticated_export_review/report.json';
const _defaultRowTemplatesPath =
    '.dart_tool/hinet_authenticated_export_row_templates/report.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_priority_evidence_template_packet/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_priority_evidence_templates.generated.md';

const _expectedPriorityCaseIds = <String>{};

const _requiredTemplateFields = {
  'caseId',
  'sourceType',
  'sourceUrl',
  'sourceVersionOrPageDate',
  'checkedAtUtc',
  'reviewer',
  'originTimeJst',
  'latitude',
  'longitude',
  'depthKm',
  'magnitude',
  'region',
  'rawRowText',
};

void main(List<String> args) {
  final sourceHinetTriagePath =
      _argument(args, '--source-hinet-triage') ?? _defaultSourceHinetTriagePath;
  final authenticatedReviewPath =
      _argument(args, '--authenticated-review') ??
      _defaultAuthenticatedReviewPath;
  final rowTemplatesPath =
      _argument(args, '--row-templates') ?? _defaultRowTemplatesPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceHinetPriorityEvidenceTemplatePacketJson(
    sourceHinetTriagePath: sourceHinetTriagePath,
    authenticatedReviewPath: authenticatedReviewPath,
    rowTemplatesPath: rowTemplatesPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net priority evidence template packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetPriorityEvidenceTemplatePacketJson({
  String sourceHinetTriagePath = _defaultSourceHinetTriagePath,
  String authenticatedReviewPath = _defaultAuthenticatedReviewPath,
  String rowTemplatesPath = _defaultRowTemplatesPath,
}) {
  final errors = <String>[];
  final sourceHinetTriage = _readJsonFile(
    sourceHinetTriagePath,
    errors,
    expectedSchema: 'source_hinet_truth_quality_triage_packet_v1',
    missingError: 'source_hinet_truth_quality_triage_missing',
  );
  final authenticatedReview = _readJsonFile(
    authenticatedReviewPath,
    errors,
    expectedSchema: 'hinet_authenticated_export_review_v1',
    missingError: 'hinet_authenticated_export_review_missing',
  );
  final rowTemplates = _readJsonFile(
    rowTemplatesPath,
    errors,
    expectedSchema: 'hinet_authenticated_export_row_templates_v1',
    missingError: 'hinet_authenticated_export_row_templates_missing',
  );

  final priorityCases = _list(sourceHinetTriage['packets'])
      .map(_map)
      .where(
        (entry) =>
            entry['queueNextAction'] ==
            'collect_external_hinet_or_jma_revised_evidence',
      )
      .toList(growable: false);
  final reviewByCaseId = {
    for (final entry in _list(authenticatedReview['cases']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');
  final templateByCaseId = {
    for (final entry in _list(rowTemplates['templates']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');

  final packets =
      priorityCases
          .map((priorityCase) {
            final caseId = priorityCase['caseId']?.toString() ?? '';
            return _packet(
              priorityCase,
              reviewByCaseId[caseId] ?? const <String, Object?>{},
              templateByCaseId[caseId] ?? const <String, Object?>{},
            );
          })
          .toList(growable: false)
        ..sort(
          (left, right) =>
              left['caseId'].toString().compareTo(right['caseId'].toString()),
        );

  final summary = _summary(packets);
  final validation = _validation(
    sourceHinetTriage: sourceHinetTriage,
    authenticatedReview: authenticatedReview,
    rowTemplates: rowTemplates,
    packets: packets,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_priority_evidence_template_packet_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'sourceHinetTruthQualityTriage': sourceHinetTriagePath,
      'hinetAuthenticatedExportReview': authenticatedReviewPath,
      'hinetAuthenticatedExportRowTemplates': rowTemplatesPath,
    },
    'policy': const {
      'manualTemplateOnly': true,
      'writesDecisionLedger': false,
      'submitsRows': false,
      'acceptsTruthQuality': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'credentialFieldsAllowed': false,
      'notes':
          'These templates collect event-level authenticated Hi-net/JMA evidence for Priority 1 review only.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'packets': packets,
  };
}

Map<String, Object?> _packet(
  Map<String, Object?> priorityCase,
  Map<String, Object?> reviewCase,
  Map<String, Object?> template,
) {
  final templateFile = template['outputFile']?.toString() ?? '';
  final templateExists =
      templateFile.isNotEmpty && File(templateFile).existsSync();
  final templatePayload = templateExists
      ? _readTemplatePayload(File(templateFile))
      : const <String, Object?>{};
  final templateFields = _stringList(template['templateFields']).toSet();
  final evidenceCandidate = _map(reviewCase['evidenceCandidate']);
  final decisionEvidenceReady = reviewCase['decisionEvidenceReady'] == true;
  final acceptedForConstrainedReferenceSplit =
      reviewCase['acceptedForConstrainedReferenceSplit'] == true;
  final rowStatus = reviewCase['rowStatus']?.toString() ?? '';
  final needsTemplate =
      rowStatus == 'pending_export' &&
      !decisionEvidenceReady &&
      !acceptedForConstrainedReferenceSplit;
  final preferredSourceType =
      template['preferredSourceType'] ?? evidenceCandidate['sourceType'];
  final missingTemplateFields = needsTemplate
      ? (_requiredTemplateFields.difference(templateFields).toList()..sort())
      : <String>[];

  return {
    'caseId': priorityCase['caseId'],
    'plannedUse': priorityCase['plannedUse'],
    'triageTier': priorityCase['triageTier'],
    'priority': priorityCase['priority'],
    'queueNextAction': priorityCase['queueNextAction'],
    'requiredEvidence': priorityCase['requiredEvidence'],
    'rowStatus': rowStatus,
    'decisionStatus': reviewCase['decisionStatus'],
    'decisionEvidenceReady': decisionEvidenceReady,
    'acceptedForConstrainedReferenceSplit':
        acceptedForConstrainedReferenceSplit,
    'preferredSourceType': preferredSourceType,
    'queryWindowJst': template['queryWindowJst'],
    'templateFile': templateFile,
    'templateExists': templateExists,
    'templateFields': templateFields.toList()..sort(),
    'missingTemplateFields': missingTemplateFields,
    'credentialFieldPresent': _containsSensitiveKey(templatePayload),
    'importDryRunCommand': needsTemplate
        ? 'dart run tools\\import_hinet_authenticated_export_row.dart '
              '--input $templateFile --dry-run'
        : '',
    'manualReviewRequired': true,
    'submitAllowedAfterFill': needsTemplate,
    'automaticClearance': false,
    'decisionLedgerWriteAllowed': false,
    'truthQualityAcceptanceAllowed': false,
    'metricPromotionAllowed': false,
    'splitAssignmentAllowed': false,
    'decision': acceptedForConstrainedReferenceSplit
        ? 'authenticated_row_review_accepted_waiting_split_gate'
        : decisionEvidenceReady
        ? 'authenticated_row_imported_waiting_reviewer_decision'
        : 'fill_template_from_authenticated_event_row_then_import_for_review',
  };
}

Map<String, Object?> _readTemplatePayload(File file) {
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } on Object {
    return const <String, Object?>{};
  }
}

Map<String, Object?> _summary(List<Map<String, Object?>> packets) {
  return {
    'packetCount': packets.length,
    'expectedPacketCount': _expectedPriorityCaseIds.length,
    'pendingExportCount': packets
        .where((entry) => entry['rowStatus'] == 'pending_export')
        .length,
    'submittedForReviewCount': packets
        .where((entry) => entry['rowStatus'] == 'submitted_for_review')
        .length,
    'templateFileCount': packets
        .where((entry) => entry['templateExists'] == true)
        .length,
    'missingTemplateFieldCaseCount': packets
        .where((entry) => _list(entry['missingTemplateFields']).isNotEmpty)
        .length,
    'credentialFieldPresentCount': packets
        .where((entry) => entry['credentialFieldPresent'] == true)
        .length,
    'decisionEvidenceReadyCount': packets
        .where((entry) => entry['decisionEvidenceReady'] == true)
        .length,
    'acceptedForConstrainedReferenceSplitCount': packets
        .where((entry) => entry['acceptedForConstrainedReferenceSplit'] == true)
        .length,
    'automaticClearanceCount': packets
        .where((entry) => entry['automaticClearance'] == true)
        .length,
    'decisionLedgerWriteAllowedCount': packets
        .where((entry) => entry['decisionLedgerWriteAllowed'] == true)
        .length,
    'truthQualityAcceptanceAllowedCount': packets
        .where((entry) => entry['truthQualityAcceptanceAllowed'] == true)
        .length,
    'metricPromotionAllowedCount': packets
        .where((entry) => entry['metricPromotionAllowed'] == true)
        .length,
    'splitAssignmentAllowedCount': packets
        .where((entry) => entry['splitAssignmentAllowed'] == true)
        .length,
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> sourceHinetTriage,
  required Map<String, Object?> authenticatedReview,
  required Map<String, Object?> rowTemplates,
  required List<Map<String, Object?>> packets,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (sourceHinetTriage['status'] != 'pass') {
    violations.add('source_hinet_truth_quality_triage_not_pass');
  }
  if (authenticatedReview['status'] != 'pass') {
    violations.add('hinet_authenticated_export_review_not_pass');
  }
  if (rowTemplates['status'] != 'pass') {
    violations.add('hinet_authenticated_export_row_templates_not_pass');
  }

  final caseIds = packets
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (caseIds.length != _expectedPriorityCaseIds.length ||
      !caseIds.containsAll(_expectedPriorityCaseIds)) {
    violations.add('unexpected_priority_case_set');
  }
  if (_intValue(summary['packetCount']) != 0) {
    violations.add('unexpected_packet_count');
  }
  final pendingExportCount = _intValue(summary['pendingExportCount']) ?? 0;
  final submittedForReviewCount =
      _intValue(summary['submittedForReviewCount']) ?? 0;
  if (pendingExportCount + submittedForReviewCount !=
      _expectedPriorityCaseIds.length) {
    violations.add('priority_rows_not_pending_or_submitted');
  }
  if (_intValue(summary['templateFileCount']) != pendingExportCount) {
    violations.add('pending_priority_template_file_missing');
  }
  if (_intValue(summary['missingTemplateFieldCaseCount']) != 0) {
    violations.add('priority_template_missing_required_fields');
  }
  if (_intValue(summary['credentialFieldPresentCount']) != 0) {
    violations.add('priority_template_contains_credential_field');
  }
  final acceptedCount =
      _intValue(summary['acceptedForConstrainedReferenceSplitCount']) ?? 0;
  final decisionEvidenceReadyCount =
      _intValue(summary['decisionEvidenceReadyCount']) ?? 0;
  if (decisionEvidenceReadyCount + acceptedCount != submittedForReviewCount) {
    violations.add('submitted_priority_not_ready_or_accepted');
  }
  if (_intValue(summary['automaticClearanceCount']) != 0) {
    violations.add('automatic_clearance_allowed');
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

  for (final packet in packets) {
    final caseId = packet['caseId'];
    if (packet['preferredSourceType'] != 'hinet_jma_unified_catalog') {
      violations.add('$caseId:preferred_source_not_jma_unified');
    }
    if (!_stringList(
      packet['requiredEvidence'],
    ).contains('reviewer_and_review_timestamp')) {
      violations.add('$caseId:missing_reviewer_timestamp_requirement');
    }
    if (packet['rowStatus'] == 'pending_export' &&
        !packet['importDryRunCommand'].toString().contains('--dry-run')) {
      violations.add('$caseId:import_command_not_dry_run');
    }
    if (packet['rowStatus'] == 'submitted_for_review' &&
        packet['decisionEvidenceReady'] != true &&
        packet['acceptedForConstrainedReferenceSplit'] != true) {
      violations.add('$caseId:submitted_row_not_evidence_ready');
    }
    if (packet['rowStatus'] == 'submitted_for_review' &&
        packet['submitAllowedAfterFill'] == true) {
      violations.add('$caseId:submitted_row_still_allows_template_submit');
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
    ..writeln('# Source Hi-net Priority Evidence Templates')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Packets: `${summary['packetCount']}`')
    ..writeln('- Pending exports: `${summary['pendingExportCount']}`')
    ..writeln('- Submitted for review: `${summary['submittedForReviewCount']}`')
    ..writeln('- Template files: `${summary['templateFileCount']}`')
    ..writeln(
      '- Missing-template-field cases: '
      '`${summary['missingTemplateFieldCaseCount']}`',
    )
    ..writeln(
      '- Credential fields present: '
      '`${summary['credentialFieldPresentCount']}`',
    )
    ..writeln(
      '- Decision evidence ready: '
      '`${summary['decisionEvidenceReadyCount']}`',
    )
    ..writeln(
      '- Accepted constrained references: '
      '`${summary['acceptedForConstrainedReferenceSplitCount']}`',
    )
    ..writeln(
      '- Decision ledger writes allowed: '
      '`${summary['decisionLedgerWriteAllowedCount']}`',
    )
    ..writeln(
      '- Truth-quality acceptance allowed: '
      '`${summary['truthQualityAcceptanceAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Templates')
    ..writeln()
    ..writeln(
      '| Case | Template | Source | Query window | Row status | Import dry-run |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- |');

  for (final rawPacket in _list(report['packets'])) {
    final packet = _map(rawPacket);
    buffer.writeln(
      '| `${packet['caseId']}` | `${packet['templateFile']}` | '
      '`${packet['preferredSourceType']}` | `${packet['queryWindowJst']}` | '
      '`${packet['rowStatus']}` | `${packet['importDryRunCommand']}` |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Fill these templates only from authenticated event-level Hi-net/JMA rows.',
    )
    ..writeln(
      '- A filled row may be imported for review, but this packet does not write the decision ledger or accept truth quality.',
    )
    ..writeln(
      '- Submitted rows are evidence-ready only; keep all Priority 1 cases pending in the decision ledger until an explicit accepted decision is recorded with reviewer metadata.',
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
