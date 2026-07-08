import 'dart:convert';
import 'dart:io';

const _defaultPriorityTemplatePath =
    '.dart_tool/source_hinet_priority_evidence_template_packet/report.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_no_row_found_review_packet/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_no_row_found_review_packet.generated.md';
const _defaultTemplateDirectory =
    '.dart_tool/source_hinet_no_row_found_review/files';

const _priorityCaseIds = {
  '20260622_iwate_east_offshore_m30_hinet',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260623_tokachi_southeast_offshore_m34_hinet',
};

const _requiredNoRowFields = {
  'caseId',
  'sourceType',
  'sourceUrl',
  'checkedAtUtc',
  'reviewer',
  'queryWindowJst',
  'searchResult',
  'searchedOriginTimeJst',
  'searchedLatitude',
  'searchedLongitude',
  'searchedMagnitude',
  'notes',
};

void main(List<String> args) {
  final priorityTemplatePath =
      _argument(args, '--priority-template-packet') ??
      _defaultPriorityTemplatePath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;
  final templateDirectoryPath =
      _argument(args, '--template-directory') ?? _defaultTemplateDirectory;

  final report = buildSourceHinetNoRowFoundReviewPacketJson(
    priorityTemplatePath: priorityTemplatePath,
    templateDirectoryPath: templateDirectoryPath,
    writeTemplates: true,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net no-row-found review packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
  stdout.writeln('files: $templateDirectoryPath');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetNoRowFoundReviewPacketJson({
  String priorityTemplatePath = _defaultPriorityTemplatePath,
  String templateDirectoryPath = _defaultTemplateDirectory,
  bool writeTemplates = false,
}) {
  final errors = <String>[];
  final priorityTemplatePacket = _readJsonFile(
    priorityTemplatePath,
    errors,
    expectedSchema: 'source_hinet_priority_evidence_template_packet_v1',
    missingError: 'source_hinet_priority_evidence_template_packet_missing',
  );

  final templateDirectory = Directory(templateDirectoryPath);
  if (writeTemplates) templateDirectory.createSync(recursive: true);

  final packets =
      _list(priorityTemplatePacket['packets'])
          .map(_map)
          .where((entry) => entry['rowStatus'] == 'pending_export')
          .map(
            (entry) =>
                _packet(entry, templateDirectoryPath.replaceAll('\\', '/')),
          )
          .toList(growable: false)
        ..sort(
          (left, right) =>
              left['caseId'].toString().compareTo(right['caseId'].toString()),
        );

  if (writeTemplates) {
    for (final packet in packets) {
      final file = File(packet['noRowFindingTemplateFile']!.toString());
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(packet['templatePayload'])}\n',
      );
    }
  }

  final summary = _summary(packets);
  final validation = _validation(
    priorityTemplatePacket: priorityTemplatePacket,
    packets: packets,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_no_row_found_review_packet_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {'sourceHinetPriorityEvidenceTemplates': priorityTemplatePath},
    'policy': const {
      'manualFindingTemplateOnly': true,
      'writesDecisionLedger': false,
      'submitsRows': false,
      'acceptsTruthQuality': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'credentialFieldsAllowed': false,
      'notes':
          'A no-row-found finding is only a manual review artifact. It keeps the case pending unless a separate accepted decision is recorded.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'packets': packets
        .map(
          (packet) => {
            for (final entry in packet.entries)
              if (entry.key != 'templatePayload') entry.key: entry.value,
          },
        )
        .toList(growable: false),
  };
}

Map<String, Object?> _packet(
  Map<String, Object?> priorityPacket,
  String templateDirectoryPath,
) {
  final caseId = priorityPacket['caseId']?.toString() ?? '';
  final templateFile = '$templateDirectoryPath/$caseId.no_row_found.json';
  final queryWindow = priorityPacket['queryWindowJst']?.toString() ?? '';
  final authTemplate = _readTemplate(
    priorityPacket['templateFile']?.toString(),
  );
  final authTarget = _map(authTemplate?['_queryTarget']);
  final templatePayload = {
    '_instructions': [
      'Fill this only after checking the authenticated event-level Hi-net/JMA page for the query window.',
      'Do not add username, password, cookie, token or session data.',
      'This finding does not accept truth quality or clear split blockers.',
    ],
    '_queryTarget': {
      'caseId': caseId,
      'plannedUse': priorityPacket['plannedUse'],
      'queryWindowJst': queryWindow,
      'preferredSourceType': priorityPacket['preferredSourceType'],
      'authenticatedRowTemplateFile': priorityPacket['templateFile'],
      'targetLatitude': authTarget['targetLatitude'],
      'targetLongitude': authTarget['targetLongitude'],
      'targetMagnitude': authTarget['targetMagnitude'],
    },
    'caseId': caseId,
    'sourceType': priorityPacket['preferredSourceType'],
    'sourceUrl': 'https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en',
    'checkedAtUtc': '<fill-checked-at-utc>',
    'reviewer': '<fill-reviewer-id>',
    'queryWindowJst': queryWindow,
    'searchResult': 'no_event_row_found',
    'searchedOriginTimeJst': '<fill-searched-origin-time-or-window>',
    'searchedLatitude': null,
    'searchedLongitude': null,
    'searchedMagnitude': null,
    'notes': '<fill-search-notes>',
  };

  return {
    'caseId': caseId,
    'plannedUse': priorityPacket['plannedUse'],
    'rowStatus': priorityPacket['rowStatus'],
    'decisionStatus': priorityPacket['decisionStatus'],
    'decisionEvidenceReady': priorityPacket['decisionEvidenceReady'] == true,
    'preferredSourceType': priorityPacket['preferredSourceType'],
    'queryWindowJst': queryWindow,
    'authenticatedRowTemplateFile': priorityPacket['templateFile'],
    'noRowFindingTemplateFile': templateFile,
    'templateFields':
        templatePayload.keys
            .where((key) => !key.startsWith('_'))
            .toList(growable: false)
          ..sort(),
    'missingTemplateFields':
        _requiredNoRowFields
            .difference(
              templatePayload.keys.where((key) => !key.startsWith('_')).toSet(),
            )
            .toList()
          ..sort(),
    'credentialFieldPresent': _containsSensitiveKey(templatePayload),
    'manualReviewRequired': true,
    'noRowFindingSubmitted': false,
    'decisionLedgerWriteAllowed': false,
    'truthQualityAcceptanceAllowed': false,
    'metricPromotionAllowed': false,
    'splitAssignmentAllowed': false,
    'decision': 'record_no_row_found_only_after_manual_authenticated_search',
    'templatePayload': templatePayload,
  };
}

Map<String, Object?>? _readTemplate(String? path) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } on Object {
    return null;
  }
}

Map<String, Object?> _summary(List<Map<String, Object?>> packets) {
  return {
    'packetCount': packets.length,
    'priorityCaseCount': _priorityCaseIds.length,
    'pendingExportCount': packets
        .where((entry) => entry['rowStatus'] == 'pending_export')
        .length,
    'templateCount': packets.length,
    'missingTemplateFieldCaseCount': packets
        .where((entry) => _list(entry['missingTemplateFields']).isNotEmpty)
        .length,
    'credentialFieldPresentCount': packets
        .where((entry) => entry['credentialFieldPresent'] == true)
        .length,
    'noRowFindingSubmittedCount': packets
        .where((entry) => entry['noRowFindingSubmitted'] == true)
        .length,
    'decisionEvidenceReadyCount': packets
        .where((entry) => entry['decisionEvidenceReady'] == true)
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
  required Map<String, Object?> priorityTemplatePacket,
  required List<Map<String, Object?>> packets,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (priorityTemplatePacket['status'] != 'pass') {
    violations.add('source_hinet_priority_evidence_templates_not_pass');
  }
  final caseIds = packets
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (!caseIds.every(_priorityCaseIds.contains)) {
    violations.add('unexpected_no_row_case_set');
  }
  if (_intValue(summary['packetCount']) !=
      _intValue(summary['pendingExportCount'])) {
    violations.add('no_row_packet_rows_not_pending');
  }
  if (_intValue(summary['missingTemplateFieldCaseCount']) != 0) {
    violations.add('no_row_template_missing_required_fields');
  }
  if (_intValue(summary['credentialFieldPresentCount']) != 0) {
    violations.add('no_row_template_contains_credential_field');
  }
  if (_intValue(summary['noRowFindingSubmittedCount']) != 0) {
    violations.add('no_row_finding_already_submitted');
  }
  if (_intValue(summary['decisionEvidenceReadyCount']) != 0) {
    violations.add('no_row_decision_evidence_ready');
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
    if (packet['decisionStatus'] != 'pending_manual_review') {
      violations.add('$caseId:decision_not_pending');
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
    ..writeln('# Source Hi-net No-Row-Found Review Packet')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Packets: `${summary['packetCount']}`')
    ..writeln('- Pending exports: `${summary['pendingExportCount']}`')
    ..writeln('- Templates: `${summary['templateCount']}`')
    ..writeln(
      '- Missing-template-field cases: '
      '`${summary['missingTemplateFieldCaseCount']}`',
    )
    ..writeln(
      '- Credential fields present: '
      '`${summary['credentialFieldPresentCount']}`',
    )
    ..writeln(
      '- No-row findings submitted: '
      '`${summary['noRowFindingSubmittedCount']}`',
    )
    ..writeln(
      '- Decision evidence ready: '
      '`${summary['decisionEvidenceReadyCount']}`',
    )
    ..writeln(
      '- Truth-quality acceptance allowed: '
      '`${summary['truthQualityAcceptanceAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Templates')
    ..writeln()
    ..writeln(
      '| Case | No-row template | Query window | Row status | Decision |',
    )
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final rawPacket in _list(report['packets'])) {
    final packet = _map(rawPacket);
    buffer.writeln(
      '| `${packet['caseId']}` | `${packet['noRowFindingTemplateFile']}` | '
      '`${packet['queryWindowJst']}` | `${packet['rowStatus']}` | '
      '`${packet['decision']}` |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- These are manual no-row-found finding templates only; they do not prove an authenticated search happened until filled by a reviewer.',
    )
    ..writeln(
      '- A no-row-found finding keeps the case pending and does not accept truth quality or assign a split.',
    )
    ..writeln(
      '- Prefer a real authenticated event-level row whenever one is available.',
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

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
