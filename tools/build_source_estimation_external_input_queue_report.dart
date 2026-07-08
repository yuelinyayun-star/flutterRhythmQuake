import 'dart:convert';
import 'dart:io';

const _defaultBlockerQueuePath =
    '.dart_tool/source_estimation_split_blocker_queue/report.json';
const _defaultJmaCaptureAssociationPath =
    '.dart_tool/jma_reference_capture_association/report.json';
const _defaultHinetRepairProbePath =
    '.dart_tool/hinet_capture_repair_probe/report.json';
const _defaultHinetAuthenticatedExportReviewPath =
    '.dart_tool/hinet_authenticated_export_review/report.json';
const _defaultOutput =
    '.dart_tool/source_estimation_external_input_queue/report.json';
const _defaultMarkdown =
    'docs/baselines/source_estimation_external_input_queue.generated.md';

void main(List<String> args) {
  final blockerQueuePath =
      _argument(args, '--blockers') ?? _defaultBlockerQueuePath;
  final jmaCaptureAssociationPath =
      _argument(args, '--jma-capture') ?? _defaultJmaCaptureAssociationPath;
  final hinetRepairProbePath =
      _argument(args, '--hinet-repair') ?? _defaultHinetRepairProbePath;
  final hinetAuthenticatedExportReviewPath =
      _argument(args, '--hinet-export') ??
      _defaultHinetAuthenticatedExportReviewPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ExternalInputQueueReport.build(
    blockerQueueFile: File(blockerQueuePath),
    jmaCaptureAssociationFile: File(jmaCaptureAssociationPath),
    hinetRepairProbeFile: File(hinetRepairProbePath),
    hinetAuthenticatedExportReviewFile: File(
      hinetAuthenticatedExportReviewPath,
    ),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-estimation external input queue report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildSourceEstimationExternalInputQueueJson({
  String blockerQueuePath = _defaultBlockerQueuePath,
  String jmaCaptureAssociationPath = _defaultJmaCaptureAssociationPath,
  String hinetRepairProbePath = _defaultHinetRepairProbePath,
  String hinetAuthenticatedExportReviewPath =
      _defaultHinetAuthenticatedExportReviewPath,
}) {
  return _ExternalInputQueueReport.build(
    blockerQueueFile: File(blockerQueuePath),
    jmaCaptureAssociationFile: File(jmaCaptureAssociationPath),
    hinetRepairProbeFile: File(hinetRepairProbePath),
    hinetAuthenticatedExportReviewFile: File(
      hinetAuthenticatedExportReviewPath,
    ),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ExternalInputQueueReport {
  final String blockerQueuePath;
  final String jmaCaptureAssociationPath;
  final String hinetRepairProbePath;
  final String hinetAuthenticatedExportReviewPath;
  final List<_ExternalInputItem> items;
  final List<String> errors;
  final List<String> warnings;

  const _ExternalInputQueueReport({
    required this.blockerQueuePath,
    required this.jmaCaptureAssociationPath,
    required this.hinetRepairProbePath,
    required this.hinetAuthenticatedExportReviewPath,
    required this.items,
    required this.errors,
    required this.warnings,
  });

  factory _ExternalInputQueueReport.build({
    required File blockerQueueFile,
    required File jmaCaptureAssociationFile,
    required File hinetRepairProbeFile,
    required File hinetAuthenticatedExportReviewFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final items = <_ExternalInputItem>[];

    final blockerQueue = _readReport(
      blockerQueueFile,
      expectedSchema: 'source_estimation_split_blocker_queue_v1',
      errors: errors,
    );
    final jmaCaptureAssociation = _readReport(
      jmaCaptureAssociationFile,
      expectedSchema: 'jma_reference_capture_association_v1',
      errors: errors,
    );
    final hinetRepairProbe = _readReport(
      hinetRepairProbeFile,
      expectedSchema: 'hinet_capture_repair_probe_v1',
      errors: errors,
    );
    final hinetAuthenticatedExportReview = _readReport(
      hinetAuthenticatedExportReviewFile,
      expectedSchema: 'hinet_authenticated_export_review_v1',
      errors: errors,
    );

    items.addAll(_jmaCaptureInputs(jmaCaptureAssociation));
    items.addAll(_splitBlockerInputs(blockerQueue));
    items.addAll(_hinetRepairInputs(hinetRepairProbe));
    items.addAll(
      _hinetAuthenticatedExportInputs(hinetAuthenticatedExportReview),
    );

    items.sort((left, right) {
      final priority = left.priority.compareTo(right.priority);
      if (priority != 0) return priority;
      final type = left.inputType.compareTo(right.inputType);
      if (type != 0) return type;
      return left.caseId.compareTo(right.caseId);
    });

    if (items.isEmpty && errors.isEmpty) {
      warnings.add('external_input_queue_empty');
    }

    return _ExternalInputQueueReport(
      blockerQueuePath: blockerQueueFile.path,
      jmaCaptureAssociationPath: jmaCaptureAssociationFile.path,
      hinetRepairProbePath: hinetRepairProbeFile.path,
      hinetAuthenticatedExportReviewPath:
          hinetAuthenticatedExportReviewFile.path,
      items: items,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final byType = <String, int>{};
    final bySource = <String, int>{};
    for (final item in items) {
      byType[item.inputType] = (byType[item.inputType] ?? 0) + 1;
      bySource[item.sourceReport] = (bySource[item.sourceReport] ?? 0) + 1;
    }
    return {
      'schemaVersion': 'source_estimation_external_input_queue_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'blockerQueuePath': blockerQueuePath,
      'jmaCaptureAssociationPath': jmaCaptureAssociationPath,
      'hinetRepairProbePath': hinetRepairProbePath,
      'hinetAuthenticatedExportReviewPath': hinetAuthenticatedExportReviewPath,
      'summary': {
        'inputItemCount': items.length,
        'inputTypeCounts': byType,
        'sourceReportCounts': bySource,
        'automaticClearanceCount': 0,
      },
      'errors': errors,
      'warnings': warnings,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final inputTypeCounts = (summary['inputTypeCounts'] as Map)
        .cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Source Estimation External Input Queue')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Blocker queue: `$blockerQueuePath`')
      ..writeln('- JMA capture association: `$jmaCaptureAssociationPath`')
      ..writeln('- Hi-net repair probe: `$hinetRepairProbePath`')
      ..writeln(
        '- Hi-net authenticated export review: '
        '`$hinetAuthenticatedExportReviewPath`',
      )
      ..writeln('- Input items: `${summary['inputItemCount']}`')
      ..writeln('- Automatic clearances: `0`')
      ..writeln()
      ..writeln('## Input Type Counts')
      ..writeln()
      ..writeln('| Input type | Count |')
      ..writeln('| --- | ---: |');
    for (final type in inputTypeCounts.keys.toList()..sort()) {
      buffer.writeln('| `$type` | ${inputTypeCounts[type]} |');
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
      ..writeln('## Queue')
      ..writeln()
      ..writeln(
        '| Priority | Type | Case | Required input | Source report | Details |',
      )
      ..writeln('| ---: | --- | --- | --- | --- | --- |');
    for (final item in items) {
      buffer.writeln(
        '| ${item.priority} | `${item.inputType}` | `${item.caseId}` | '
        '${item.requiredInput} | `${item.sourceReport}` | '
        '${item.details} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This queue does not edit split manifests, review ledgers or capture '
        'packages.',
      )
      ..writeln(
        '- Providing one of these inputs only makes a downstream guard eligible '
        'to re-evaluate; it never clears source truth or capture blockers by '
        'itself.',
      );
    return buffer.toString();
  }
}

class _ExternalInputItem {
  final int priority;
  final String inputType;
  final String caseId;
  final String requiredInput;
  final String sourceReport;
  final String details;

  const _ExternalInputItem({
    required this.priority,
    required this.inputType,
    required this.caseId,
    required this.requiredInput,
    required this.sourceReport,
    required this.details,
  });

  Map<String, Object?> toJson() => {
    'priority': priority,
    'inputType': inputType,
    'caseId': caseId,
    'requiredInput': requiredInput,
    'sourceReport': sourceReport,
    'details': details,
  };
}

List<_ExternalInputItem> _jmaCaptureInputs(Map<String, Object?> report) {
  final items = <_ExternalInputItem>[];
  for (final rawCase in _list(report['cases'])) {
    final item = _map(rawCase);
    final eventId = item['eventId']?.toString() ?? '';
    final captureDirectory = item['captureDirectory'];
    final localCaptureCandidates = _list(item['localCaptureCandidates']);
    final localFixtureCandidates = _list(item['localFixtureCandidates']);
    if (eventId.isEmpty ||
        captureDirectory != null ||
        localCaptureCandidates.isNotEmpty ||
        localFixtureCandidates.isNotEmpty) {
      continue;
    }
    items.add(
      _ExternalInputItem(
        priority: 20,
        inputType: 'local_jma_reference_capture_package',
        caseId: eventId,
        requiredInput:
            'Associate a local replay/capture package in the JMA reference manifest.',
        sourceReport: 'jma_reference_capture_association',
        details: 'status=${item['status']}; originJst=${item['originTimeJst']}',
      ),
    );
  }
  return items;
}

List<_ExternalInputItem> _splitBlockerInputs(Map<String, Object?> report) {
  final items = <_ExternalInputItem>[];
  for (final rawBlocker in _list(report['blockers'])) {
    final blocker = _map(rawBlocker);
    final caseId = blocker['caseId']?.toString() ?? '';
    final action = blocker['nextAction']?.toString() ?? '';
    if (caseId.isEmpty) continue;
    if (action == 'review_jma_catalog_link') {
      items.add(
        _ExternalInputItem(
          priority: 30,
          inputType: 'versioned_jma_final_catalog_record',
          caseId: caseId,
          requiredInput:
              'Link a versioned JMA final catalog record for this recent event.',
          sourceReport: 'source_estimation_split_blocker_queue',
          details: 'plannedUse=${blocker['plannedUse']}',
        ),
      );
    } else if (action == 'link_final_catalog_or_hinet_revision') {
      items.add(
        _ExternalInputItem(
          priority: 40,
          inputType: 'final_catalog_or_hinet_revision',
          caseId: caseId,
          requiredInput:
              'Link a final catalog row or revised Hi-net source before split assignment.',
          sourceReport: 'source_estimation_split_blocker_queue',
          details: 'plannedUse=${blocker['plannedUse']}',
        ),
      );
    }
  }
  return items;
}

List<_ExternalInputItem> _hinetRepairInputs(Map<String, Object?> report) {
  final items = <_ExternalInputItem>[];
  for (final rawCase in _list(report['cases'])) {
    final item = _map(rawCase);
    if (item['repairCandidateReady'] == true) continue;
    final caseId = item['caseId']?.toString() ?? '';
    for (final rawAffected in _list(item['affectedFiles'])) {
      final affected = _map(rawAffected);
      final fileName = affected['fileName']?.toString() ?? '';
      final validGifCount = affected['validGifCandidateCount'];
      if (caseId.isEmpty || fileName.isEmpty || validGifCount != 0) continue;
      final remoteHints = _list(affected['remoteHints'])
          .map((raw) => _map(raw))
          .where((hint) => hint['remoteRetrievalAllowed'] == true)
          .map((hint) => hint['url']?.toString())
          .whereType<String>()
          .toList(growable: false);
      final historicalRemoteHints = _list(affected['remoteHints'])
          .map((raw) => _map(raw))
          .where((hint) => hint['remoteRetrievalAllowed'] != true)
          .map((hint) => hint['url']?.toString())
          .whereType<String>()
          .toList(growable: false);
      items.add(
        _ExternalInputItem(
          priority: 10,
          inputType: 'missing_gif_archive_copy',
          caseId: caseId,
          requiredInput:
              'Place a valid copy of `$fileName` under a repair scan root.',
          sourceReport: 'hinet_capture_repair_probe',
          details: remoteHints.isEmpty
              ? historicalRemoteHints.isEmpty
                    ? 'no deterministic remote hint'
                    : 'historicalRemoteHint=${historicalRemoteHints.first}; '
                          'remoteRetrievalAllowed=false; '
                          'maxRemoteAgeHours=3'
              : 'remoteHint=${remoteHints.first}; '
                    'remoteRetrievalAllowed=true; maxRemoteAgeHours=3',
        ),
      );
    }
  }
  return items;
}

List<_ExternalInputItem> _hinetAuthenticatedExportInputs(
  Map<String, Object?> report,
) {
  final items = <_ExternalInputItem>[];
  for (final rawCase in _list(report['cases'])) {
    final item = _map(rawCase);
    final caseId = item['caseId']?.toString() ?? '';
    if (caseId.isEmpty || item['rowStatus'] != 'pending_export') continue;
    items.add(
      _ExternalInputItem(
        priority: 15,
        inputType: 'authenticated_hinet_export_row',
        caseId: caseId,
        requiredInput:
            'Fill one submitted_for_review authenticated Hi-net/JMA event row.',
        sourceReport: 'hinet_authenticated_export_review',
        details: 'decisionStatus=${item['decisionStatus']}',
      ),
    );
  }
  return items;
}

Map<String, Object?> _readReport(
  File file, {
  required String expectedSchema,
  required List<String> errors,
}) {
  if (!file.existsSync()) {
    errors.add('external_input_dependency_missing:${file.path}');
    return const {};
  }
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  if (decoded['schemaVersion'] != expectedSchema) {
    errors.add('external_input_unexpected_schema:${file.path}');
  }
  if (decoded['status'] != 'pass') {
    errors.add('external_input_dependency_not_pass:${file.path}');
  }
  return decoded;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
