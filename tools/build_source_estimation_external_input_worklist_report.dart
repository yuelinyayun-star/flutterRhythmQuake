import 'dart:convert';
import 'dart:io';

const _defaultQueuePath =
    '.dart_tool/source_estimation_external_input_queue/report.json';
const _defaultTemplatesPath =
    '.dart_tool/source_estimation_external_input_templates/report.json';
const _defaultAttemptsPath =
    '.dart_tool/source_estimation_external_input_attempts/report.json';
const _defaultRepairProbePath =
    '.dart_tool/hinet_capture_repair_probe/report.json';
const _defaultAuthenticatedExportPacketPath =
    '.dart_tool/hinet_authenticated_export_review_packet/report.json';
const _defaultJmaReferenceCapturePacketPath =
    '.dart_tool/jma_reference_capture_review_packet/report.json';
const _defaultJmaFinalCatalogPacketPath =
    '.dart_tool/jma_final_catalog_review_packet/report.json';
const _defaultFinalCatalogOrHinetRevisionPacketPath =
    '.dart_tool/final_catalog_or_hinet_revision_review_packet/report.json';
const _defaultOutput =
    '.dart_tool/source_estimation_external_input_worklist/report.json';
const _defaultMarkdown =
    'docs/baselines/source_estimation_external_input_worklist.generated.md';

void main(List<String> args) {
  final queuePath = _argument(args, '--queue') ?? _defaultQueuePath;
  final templatesPath = _argument(args, '--templates') ?? _defaultTemplatesPath;
  final attemptsPath = _argument(args, '--attempts') ?? _defaultAttemptsPath;
  final repairProbePath =
      _argument(args, '--repair-probe') ?? _defaultRepairProbePath;
  final authenticatedExportPacketPath =
      _argument(args, '--authenticated-export-packet') ??
      _defaultAuthenticatedExportPacketPath;
  final jmaReferenceCapturePacketPath =
      _argument(args, '--jma-reference-capture-packet') ??
      _defaultJmaReferenceCapturePacketPath;
  final jmaFinalCatalogPacketPath =
      _argument(args, '--jma-final-catalog-packet') ??
      _defaultJmaFinalCatalogPacketPath;
  final finalCatalogOrHinetRevisionPacketPath =
      _argument(args, '--final-catalog-or-hinet-revision-packet') ??
      _defaultFinalCatalogOrHinetRevisionPacketPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ExternalInputWorklistReport.build(
    queueFile: File(queuePath),
    templatesFile: File(templatesPath),
    attemptsFile: File(attemptsPath),
    repairProbeFile: File(repairProbePath),
    authenticatedExportPacketFile: File(authenticatedExportPacketPath),
    jmaReferenceCapturePacketFile: File(jmaReferenceCapturePacketPath),
    jmaFinalCatalogPacketFile: File(jmaFinalCatalogPacketPath),
    finalCatalogOrHinetRevisionPacketFile: File(
      finalCatalogOrHinetRevisionPacketPath,
    ),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-estimation external input worklist report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildSourceEstimationExternalInputWorklistJson({
  String queuePath = _defaultQueuePath,
  String templatesPath = _defaultTemplatesPath,
  String attemptsPath = _defaultAttemptsPath,
  String repairProbePath = _defaultRepairProbePath,
  String authenticatedExportPacketPath = _defaultAuthenticatedExportPacketPath,
  String jmaReferenceCapturePacketPath = _defaultJmaReferenceCapturePacketPath,
  String jmaFinalCatalogPacketPath = _defaultJmaFinalCatalogPacketPath,
  String finalCatalogOrHinetRevisionPacketPath =
      _defaultFinalCatalogOrHinetRevisionPacketPath,
}) {
  return _ExternalInputWorklistReport.build(
    queueFile: File(queuePath),
    templatesFile: File(templatesPath),
    attemptsFile: File(attemptsPath),
    repairProbeFile: File(repairProbePath),
    authenticatedExportPacketFile: File(authenticatedExportPacketPath),
    jmaReferenceCapturePacketFile: File(jmaReferenceCapturePacketPath),
    jmaFinalCatalogPacketFile: File(jmaFinalCatalogPacketPath),
    finalCatalogOrHinetRevisionPacketFile: File(
      finalCatalogOrHinetRevisionPacketPath,
    ),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ExternalInputWorklistReport {
  final String queuePath;
  final String templatesPath;
  final String attemptsPath;
  final String repairProbePath;
  final String authenticatedExportPacketPath;
  final String jmaReferenceCapturePacketPath;
  final String jmaFinalCatalogPacketPath;
  final String finalCatalogOrHinetRevisionPacketPath;
  final List<_WorklistRow> rows;
  final List<String> errors;
  final List<String> warnings;

  const _ExternalInputWorklistReport({
    required this.queuePath,
    required this.templatesPath,
    required this.attemptsPath,
    required this.repairProbePath,
    required this.authenticatedExportPacketPath,
    required this.jmaReferenceCapturePacketPath,
    required this.jmaFinalCatalogPacketPath,
    required this.finalCatalogOrHinetRevisionPacketPath,
    required this.rows,
    required this.errors,
    required this.warnings,
  });

  factory _ExternalInputWorklistReport.build({
    required File queueFile,
    required File templatesFile,
    required File attemptsFile,
    required File repairProbeFile,
    required File authenticatedExportPacketFile,
    required File jmaReferenceCapturePacketFile,
    required File jmaFinalCatalogPacketFile,
    required File finalCatalogOrHinetRevisionPacketFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final queue = _readReport(
      queueFile,
      expectedSchema: 'source_estimation_external_input_queue_v1',
      errors: errors,
      prefix: 'external_input_worklist_queue',
    );
    final templates = _readReport(
      templatesFile,
      expectedSchema: 'source_estimation_external_input_templates_v1',
      errors: errors,
      prefix: 'external_input_worklist_templates',
    );
    final attempts = _readReport(
      attemptsFile,
      expectedSchema: 'source_estimation_external_input_attempt_report_v1',
      errors: errors,
      prefix: 'external_input_worklist_attempts',
    );
    final repairProbe = _readOptionalReport(
      repairProbeFile,
      expectedSchema: 'hinet_capture_repair_probe_v1',
      errors: errors,
      warnings: warnings,
      prefix: 'external_input_worklist_repair_probe',
    );
    final authenticatedExportPacket = _readOptionalReport(
      authenticatedExportPacketFile,
      expectedSchema: 'hinet_authenticated_export_review_packet_v1',
      errors: errors,
      warnings: warnings,
      prefix: 'external_input_worklist_authenticated_export_packet',
    );
    final jmaReferenceCapturePacket = _readOptionalReport(
      jmaReferenceCapturePacketFile,
      expectedSchema: 'jma_reference_capture_review_packet_v1',
      errors: errors,
      warnings: warnings,
      prefix: 'external_input_worklist_jma_reference_capture_packet',
    );
    final jmaFinalCatalogPacket = _readOptionalReport(
      jmaFinalCatalogPacketFile,
      expectedSchema: 'jma_final_catalog_review_packet_v1',
      errors: errors,
      warnings: warnings,
      prefix: 'external_input_worklist_jma_final_catalog_packet',
    );
    final finalCatalogOrHinetRevisionPacket = _readOptionalReport(
      finalCatalogOrHinetRevisionPacketFile,
      expectedSchema: 'final_catalog_or_hinet_revision_review_packet_v1',
      errors: errors,
      warnings: warnings,
      prefix: 'external_input_worklist_final_catalog_or_hinet_revision_packet',
    );

    final templateByKey = <String, _TemplateItem>{};
    for (final rawTemplate in _list(templates['templates'])) {
      final template = _TemplateItem.fromJson(_map(rawTemplate));
      if (template.key.isEmpty) continue;
      if (templateByKey.containsKey(template.key)) {
        errors.add(
          'external_input_worklist_duplicate_template:${template.key}',
        );
      }
      templateByKey[template.key] = template;
    }

    final attemptsByKey = <String, List<_AttemptItem>>{};
    for (final rawAttempt in _list(attempts['attempts'])) {
      final attempt = _AttemptItem.fromJson(_map(rawAttempt));
      if (attempt.key.isEmpty) continue;
      attemptsByKey.putIfAbsent(attempt.key, () => []).add(attempt);
      if (attempt.automaticClearance) {
        errors.add(
          'external_input_worklist_attempt_allows_clearance:${attempt.key}',
        );
      }
      if (attempt.evidenceStrength != 'negative_attempt_only') {
        errors.add(
          'external_input_worklist_nonnegative_attempt:${attempt.key}',
        );
      }
    }

    final repairTemplateByCaseId = <String, _RepairProbeTemplateItem>{};
    for (final rawTemplate in _list(repairProbe['repairInputTemplates'])) {
      final repairTemplate = _RepairProbeTemplateItem.fromJson(
        _map(rawTemplate),
      );
      if (repairTemplate.caseId.isEmpty) continue;
      if (repairTemplateByCaseId.containsKey(repairTemplate.caseId)) {
        errors.add(
          'external_input_worklist_duplicate_repair_template:'
          '${repairTemplate.caseId}',
        );
      }
      if (!repairTemplate.manualReviewRequired) {
        errors.add(
          'external_input_worklist_repair_template_not_manual:'
          '${repairTemplate.caseId}',
        );
      }
      if (repairTemplate.automaticClearance) {
        errors.add(
          'external_input_worklist_repair_template_allows_clearance:'
          '${repairTemplate.caseId}',
        );
      }
      repairTemplateByCaseId[repairTemplate.caseId] = repairTemplate;
    }

    final authenticatedExportPacketByCaseId =
        <String, _AuthenticatedExportPacketItem>{};
    for (final rawPacket in _list(authenticatedExportPacket['packets'])) {
      final packet = _AuthenticatedExportPacketItem.fromJson(_map(rawPacket));
      if (packet.caseId.isEmpty) continue;
      if (authenticatedExportPacketByCaseId.containsKey(packet.caseId)) {
        errors.add(
          'external_input_worklist_duplicate_authenticated_export_packet:'
          '${packet.caseId}',
        );
      }
      if (!packet.manualReviewRequired) {
        errors.add(
          'external_input_worklist_authenticated_export_packet_not_manual:'
          '${packet.caseId}',
        );
      }
      if (packet.automaticClearance) {
        errors.add(
          'external_input_worklist_authenticated_export_packet_allows_clearance:'
          '${packet.caseId}',
        );
      }
      authenticatedExportPacketByCaseId[packet.caseId] = packet;
    }

    final jmaReferenceCapturePacketByCaseId =
        <String, _JmaReferenceCapturePacketItem>{};
    for (final rawPacket in _list(jmaReferenceCapturePacket['packets'])) {
      final packet = _JmaReferenceCapturePacketItem.fromJson(_map(rawPacket));
      if (packet.caseId.isEmpty) continue;
      if (jmaReferenceCapturePacketByCaseId.containsKey(packet.caseId)) {
        errors.add(
          'external_input_worklist_duplicate_jma_reference_capture_packet:'
          '${packet.caseId}',
        );
      }
      if (!packet.manualReviewRequired) {
        errors.add(
          'external_input_worklist_jma_reference_capture_packet_not_manual:'
          '${packet.caseId}',
        );
      }
      if (packet.automaticClearance ||
          packet.manifestMutation ||
          packet.captureAssociationClearedByPacket ||
          packet.finalCatalogTruth) {
        errors.add(
          'external_input_worklist_jma_reference_capture_packet_allows_mutation:'
          '${packet.caseId}',
        );
      }
      jmaReferenceCapturePacketByCaseId[packet.caseId] = packet;
    }

    final jmaFinalCatalogPacketByCaseId =
        <String, _JmaFinalCatalogPacketItem>{};
    for (final rawPacket in _list(jmaFinalCatalogPacket['packets'])) {
      final packet = _JmaFinalCatalogPacketItem.fromJson(_map(rawPacket));
      if (packet.caseId.isEmpty) continue;
      if (jmaFinalCatalogPacketByCaseId.containsKey(packet.caseId)) {
        errors.add(
          'external_input_worklist_duplicate_jma_final_catalog_packet:'
          '${packet.caseId}',
        );
      }
      if (!packet.manualReviewRequired) {
        errors.add(
          'external_input_worklist_jma_final_catalog_packet_not_manual:'
          '${packet.caseId}',
        );
      }
      if (packet.automaticClearance ||
          packet.fixtureMutation ||
          packet.catalogTruthWrite ||
          packet.writeLinkAllowed) {
        errors.add(
          'external_input_worklist_jma_final_catalog_packet_allows_mutation:'
          '${packet.caseId}',
        );
      }
      jmaFinalCatalogPacketByCaseId[packet.caseId] = packet;
    }

    final finalCatalogOrHinetRevisionPacketByCaseId =
        <String, _FinalCatalogOrHinetRevisionPacketItem>{};
    for (final rawPacket in _list(
      finalCatalogOrHinetRevisionPacket['packets'],
    )) {
      final packet = _FinalCatalogOrHinetRevisionPacketItem.fromJson(
        _map(rawPacket),
      );
      if (packet.caseId.isEmpty) continue;
      if (finalCatalogOrHinetRevisionPacketByCaseId.containsKey(
        packet.caseId,
      )) {
        errors.add(
          'external_input_worklist_duplicate_final_catalog_or_hinet_revision_packet:'
          '${packet.caseId}',
        );
      }
      if (!packet.manualReviewRequired) {
        errors.add(
          'external_input_worklist_final_catalog_or_hinet_revision_packet_not_manual:'
          '${packet.caseId}',
        );
      }
      if (packet.automaticClearance ||
          packet.fixtureMutation ||
          packet.splitManifestMutation ||
          packet.truthPromotion ||
          packet.resolutionAllowedByPacket) {
        errors.add(
          'external_input_worklist_final_catalog_or_hinet_revision_packet_allows_mutation:'
          '${packet.caseId}',
        );
      }
      finalCatalogOrHinetRevisionPacketByCaseId[packet.caseId] = packet;
    }

    final rows = <_WorklistRow>[];
    for (final rawQueueItem in _list(queue['items'])) {
      final queueItem = _QueueItem.fromJson(_map(rawQueueItem));
      if (queueItem.key.isEmpty) continue;
      final template = templateByKey[queueItem.key];
      if (template == null) {
        errors.add('external_input_worklist_missing_template:${queueItem.key}');
      } else {
        if (!template.manualReviewRequired) {
          errors.add(
            'external_input_worklist_template_not_manual:${queueItem.key}',
          );
        }
        if (template.automaticClearance) {
          errors.add(
            'external_input_worklist_template_allows_clearance:${queueItem.key}',
          );
        }
      }
      final itemAttempts = List<_AttemptItem>.of(
        attemptsByKey[queueItem.key] ?? const [],
      );
      itemAttempts.sort((left, right) {
        return left.attemptedAtUtc.compareTo(right.attemptedAtUtc);
      });
      rows.add(
        _WorklistRow.fromParts(
          queueItem: queueItem,
          template: template,
          attempts: itemAttempts,
          repairTemplate: queueItem.inputType == 'missing_gif_archive_copy'
              ? repairTemplateByCaseId[queueItem.caseId]
              : null,
          authenticatedExportPacket:
              queueItem.inputType == 'authenticated_hinet_export_row'
              ? authenticatedExportPacketByCaseId[queueItem.caseId]
              : null,
          jmaReferenceCapturePacket:
              queueItem.inputType == 'local_jma_reference_capture_package'
              ? jmaReferenceCapturePacketByCaseId[queueItem.caseId]
              : null,
          jmaFinalCatalogPacket:
              queueItem.inputType == 'versioned_jma_final_catalog_record'
              ? jmaFinalCatalogPacketByCaseId[queueItem.caseId]
              : null,
          finalCatalogOrHinetRevisionPacket:
              queueItem.inputType == 'final_catalog_or_hinet_revision'
              ? finalCatalogOrHinetRevisionPacketByCaseId[queueItem.caseId]
              : null,
        ),
      );
    }

    rows.sort((left, right) {
      final priority = left.priority.compareTo(right.priority);
      if (priority != 0) return priority;
      final type = left.inputType.compareTo(right.inputType);
      if (type != 0) return type;
      return left.caseId.compareTo(right.caseId);
    });

    return _ExternalInputWorklistReport(
      queuePath: queueFile.path,
      templatesPath: templatesFile.path,
      attemptsPath: attemptsFile.path,
      repairProbePath: repairProbeFile.path,
      authenticatedExportPacketPath: authenticatedExportPacketFile.path,
      jmaReferenceCapturePacketPath: jmaReferenceCapturePacketFile.path,
      jmaFinalCatalogPacketPath: jmaFinalCatalogPacketFile.path,
      finalCatalogOrHinetRevisionPacketPath:
          finalCatalogOrHinetRevisionPacketFile.path,
      rows: rows,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final typeCounts = <String, int>{};
    final attemptedTypeCounts = <String, int>{};
    for (final row in rows) {
      typeCounts[row.inputType] = (typeCounts[row.inputType] ?? 0) + 1;
      if (row.attemptCount > 0) {
        attemptedTypeCounts[row.inputType] =
            (attemptedTypeCounts[row.inputType] ?? 0) + 1;
      }
    }
    final attemptedRows = rows.where((row) => row.attemptCount > 0).length;
    final next = rows.isEmpty ? null : rows.first;
    return {
      'schemaVersion': 'source_estimation_external_input_worklist_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'queuePath': queuePath,
      'templatesPath': templatesPath,
      'attemptsPath': attemptsPath,
      'repairProbePath': repairProbePath,
      'authenticatedExportPacketPath': authenticatedExportPacketPath,
      'jmaReferenceCapturePacketPath': jmaReferenceCapturePacketPath,
      'jmaFinalCatalogPacketPath': jmaFinalCatalogPacketPath,
      'finalCatalogOrHinetRevisionPacketPath':
          finalCatalogOrHinetRevisionPacketPath,
      'summary': {
        'openInputCount': rows.length,
        'inputTypeCounts': typeCounts,
        'attemptedInputCount': attemptedRows,
        'unattemptedInputCount': rows.length - attemptedRows,
        'attemptedInputTypeCounts': attemptedTypeCounts,
        'manualReviewRequiredCount': rows
            .where((row) => row.manualReviewRequired)
            .length,
        'automaticClearanceCount': rows
            .where((row) => row.automaticClearance)
            .length,
        'operationArtifactCount': rows
            .where((row) => row.operationArtifact != null)
            .length,
        'highestPriority': next?.priority,
        'nextInputType': next?.inputType,
        'nextCaseId': next?.caseId,
        'nextHasAttempts': next == null ? false : next.attemptCount > 0,
      },
      'errors': errors,
      'warnings': warnings,
      'rows': rows.map((row) => row.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final typeCounts = (summary['inputTypeCounts'] as Map)
        .cast<String, Object?>();
    final attemptedTypeCounts = (summary['attemptedInputTypeCounts'] as Map)
        .cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Source Estimation External Input Worklist')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Queue: `$queuePath`')
      ..writeln('- Templates: `$templatesPath`')
      ..writeln('- Attempts: `$attemptsPath`')
      ..writeln('- Repair probe: `$repairProbePath`')
      ..writeln(
        '- Authenticated export packet: `$authenticatedExportPacketPath`',
      )
      ..writeln(
        '- JMA reference capture packet: `$jmaReferenceCapturePacketPath`',
      )
      ..writeln('- JMA final catalog packet: `$jmaFinalCatalogPacketPath`')
      ..writeln(
        '- Final catalog or Hi-net revision packet: '
        '`$finalCatalogOrHinetRevisionPacketPath`',
      )
      ..writeln('- Open inputs: `${summary['openInputCount']}`')
      ..writeln(
        '- Inputs with recorded attempts: `${summary['attemptedInputCount']}`',
      )
      ..writeln(
        '- Inputs without attempts: `${summary['unattemptedInputCount']}`',
      )
      ..writeln(
        '- Automatic clearances: `${summary['automaticClearanceCount']}`',
      )
      ..writeln('- Operation artifacts: `${summary['operationArtifactCount']}`')
      ..writeln(
        '- Next input: `${summary['nextInputType']}::${summary['nextCaseId']}`',
      )
      ..writeln()
      ..writeln('## Input Type Counts')
      ..writeln()
      ..writeln('| Input type | Open | With attempts |')
      ..writeln('| --- | ---: | ---: |');
    for (final type in typeCounts.keys.toList()..sort()) {
      buffer.writeln(
        '| `$type` | ${typeCounts[type]} | ${attemptedTypeCounts[type] ?? 0} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Worklist')
      ..writeln()
      ..writeln(
        '| Priority | Type | Case | Attempts | Last result | Action | Operation artifact | Validation |',
      )
      ..writeln('| ---: | --- | --- | ---: | --- | --- | --- | --- |');
    for (final row in rows) {
      buffer.writeln(
        '| ${row.priority} | `${row.inputType}` | `${row.caseId}` | '
        '${row.attemptCount} | `${row.lastAttemptResult ?? '--'}` | '
        '${row.action} | ${row.operationArtifactLabel} | '
        '`${row.validationCommand ?? '--'}` |',
      );
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
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This worklist is operational only. It does not clear capture, '
        'catalog, truth-quality or split blockers.',
      )
      ..writeln(
        '- Recorded negative attempts remain non-evidence and only prevent '
        'repeating untracked searches.',
      );
    return buffer.toString();
  }
}

class _QueueItem {
  final int priority;
  final String inputType;
  final String caseId;
  final String requiredInput;

  const _QueueItem({
    required this.priority,
    required this.inputType,
    required this.caseId,
    required this.requiredInput,
  });

  String get key => _key(inputType, caseId);

  static _QueueItem fromJson(Map<String, Object?> json) => _QueueItem(
    priority: (json['priority'] as num?)?.toInt() ?? 999,
    inputType: _string(json['inputType']),
    caseId: _string(json['caseId']),
    requiredInput: _string(json['requiredInput']),
  );
}

class _TemplateItem {
  final String inputType;
  final String caseId;
  final String action;
  final String validationCommand;
  final bool manualReviewRequired;
  final bool automaticClearance;

  const _TemplateItem({
    required this.inputType,
    required this.caseId,
    required this.action,
    required this.validationCommand,
    required this.manualReviewRequired,
    required this.automaticClearance,
  });

  String get key => _key(inputType, caseId);

  static _TemplateItem fromJson(Map<String, Object?> json) => _TemplateItem(
    inputType: _string(json['inputType']),
    caseId: _string(json['caseId']),
    action: _string(json['action']),
    validationCommand: _string(json['validationCommand']),
    manualReviewRequired: json['manualReviewRequired'] == true,
    automaticClearance: json['automaticClearance'] == true,
  );
}

class _AttemptItem {
  final String inputType;
  final String caseId;
  final String attemptedAtUtc;
  final String result;
  final String evidenceStrength;
  final bool automaticClearance;

  const _AttemptItem({
    required this.inputType,
    required this.caseId,
    required this.attemptedAtUtc,
    required this.result,
    required this.evidenceStrength,
    required this.automaticClearance,
  });

  String get key => _key(inputType, caseId);

  static _AttemptItem fromJson(Map<String, Object?> json) => _AttemptItem(
    inputType: _string(json['inputType']),
    caseId: _string(json['caseId']),
    attemptedAtUtc: _string(json['attemptedAtUtc']),
    result: _string(json['result']),
    evidenceStrength: _string(json['evidenceStrength']),
    automaticClearance: json['automaticClearance'] == true,
  );
}

class _RepairProbeTemplateItem {
  final String caseId;
  final String expectedFileName;
  final String outputFile;
  final String dryRunCommand;
  final String candidateStatus;
  final bool manualReviewRequired;
  final bool automaticClearance;

  const _RepairProbeTemplateItem({
    required this.caseId,
    required this.expectedFileName,
    required this.outputFile,
    required this.dryRunCommand,
    required this.candidateStatus,
    required this.manualReviewRequired,
    required this.automaticClearance,
  });

  static _RepairProbeTemplateItem fromJson(Map<String, Object?> json) =>
      _RepairProbeTemplateItem(
        caseId: _string(json['caseId']),
        expectedFileName: _string(json['expectedFileName']),
        outputFile: _string(json['outputFile']),
        dryRunCommand: _string(json['dryRunCommand']),
        candidateStatus: _string(json['candidateStatus']),
        manualReviewRequired: json['manualReviewRequired'] == true,
        automaticClearance: json['automaticClearance'] == true,
      );

  Map<String, Object?> toOperationArtifact() => {
    'kind': 'hinet_capture_repair_input_template',
    'expectedFileName': expectedFileName,
    'templateFile': outputFile,
    'dryRunCommand': dryRunCommand,
    'candidateStatus': candidateStatus,
    'manualReviewRequired': manualReviewRequired,
    'automaticClearance': automaticClearance,
  };
}

class _AuthenticatedExportPacketItem {
  final String caseId;
  final String rowStatus;
  final String preferredSourceType;
  final String fallbackSourceType;
  final String preferredSourceUrl;
  final String fallbackSourceUrl;
  final String queryWindowJst;
  final String targetOriginTimeJst;
  final String templateFile;
  final String importDryRunCommand;
  final bool manualReviewRequired;
  final bool automaticClearance;

  const _AuthenticatedExportPacketItem({
    required this.caseId,
    required this.rowStatus,
    required this.preferredSourceType,
    required this.fallbackSourceType,
    required this.preferredSourceUrl,
    required this.fallbackSourceUrl,
    required this.queryWindowJst,
    required this.targetOriginTimeJst,
    required this.templateFile,
    required this.importDryRunCommand,
    required this.manualReviewRequired,
    required this.automaticClearance,
  });

  static _AuthenticatedExportPacketItem fromJson(Map<String, Object?> json) =>
      _AuthenticatedExportPacketItem(
        caseId: _string(json['caseId']),
        rowStatus: _string(json['rowStatus']),
        preferredSourceType: _string(json['preferredSourceType']),
        fallbackSourceType: _string(json['fallbackSourceType']),
        preferredSourceUrl: _string(json['preferredSourceUrl']),
        fallbackSourceUrl: _string(json['fallbackSourceUrl']),
        queryWindowJst: _string(json['queryWindowJst']),
        targetOriginTimeJst: _string(json['targetOriginTimeJst']),
        templateFile: _string(json['templateFile']),
        importDryRunCommand: _string(json['importDryRunCommand']),
        manualReviewRequired: json['manualReviewRequired'] == true,
        automaticClearance: json['automaticClearance'] == true,
      );

  Map<String, Object?> toOperationArtifact() => {
    'kind': 'hinet_authenticated_export_row_template',
    'templateFile': templateFile,
    'dryRunCommand': importDryRunCommand,
    'rowStatus': rowStatus,
    'preferredSourceType': preferredSourceType,
    'preferredSourceUrl': preferredSourceUrl,
    'fallbackSourceType': fallbackSourceType,
    'fallbackSourceUrl': fallbackSourceUrl,
    'queryWindowJst': queryWindowJst,
    'targetOriginTimeJst': targetOriginTimeJst,
    'manualReviewRequired': manualReviewRequired,
    'automaticClearance': automaticClearance,
  };
}

class _JmaReferenceCapturePacketItem {
  final String caseId;
  final String status;
  final String originTimeJst;
  final String region;
  final String associationTargetPath;
  final List<String> requiredLocalFiles;
  final List<String> acceptedLocalRoots;
  final List<String> reviewFields;
  final String validationCommand;
  final String dryRunCommand;
  final bool manualReviewRequired;
  final bool automaticClearance;
  final bool manifestMutation;
  final bool captureAssociationClearedByPacket;
  final bool finalCatalogTruth;

  const _JmaReferenceCapturePacketItem({
    required this.caseId,
    required this.status,
    required this.originTimeJst,
    required this.region,
    required this.associationTargetPath,
    required this.requiredLocalFiles,
    required this.acceptedLocalRoots,
    required this.reviewFields,
    required this.validationCommand,
    required this.dryRunCommand,
    required this.manualReviewRequired,
    required this.automaticClearance,
    required this.manifestMutation,
    required this.captureAssociationClearedByPacket,
    required this.finalCatalogTruth,
  });

  static _JmaReferenceCapturePacketItem fromJson(Map<String, Object?> json) =>
      _JmaReferenceCapturePacketItem(
        caseId: _string(json['eventId']),
        status: _string(json['status']),
        originTimeJst: _string(json['originTimeJst']),
        region: _string(json['region']),
        associationTargetPath: _string(json['associationTargetPath']),
        requiredLocalFiles: _stringList(json['requiredLocalFiles']),
        acceptedLocalRoots: _stringList(json['acceptedLocalRoots']),
        reviewFields: _stringList(json['reviewFields']),
        validationCommand: _string(json['validationCommand']),
        dryRunCommand: _string(json['dryRunCommand']),
        manualReviewRequired: json['manualReviewRequired'] == true,
        automaticClearance: json['automaticClearance'] == true,
        manifestMutation: json['manifestMutation'] == true,
        captureAssociationClearedByPacket:
            json['captureAssociationClearedByPacket'] == true,
        finalCatalogTruth: json['finalCatalogTruth'] == true,
      );

  Map<String, Object?> toOperationArtifact() => {
    'kind': 'jma_reference_capture_review_packet',
    'packetStatus': status,
    'originTimeJst': originTimeJst,
    'region': region,
    'associationTargetPath': associationTargetPath,
    'requiredLocalFiles': requiredLocalFiles,
    'acceptedLocalRoots': acceptedLocalRoots,
    'reviewFields': reviewFields,
    'validationCommand': validationCommand,
    'dryRunCommand': dryRunCommand,
    'manualReviewRequired': manualReviewRequired,
    'automaticClearance': automaticClearance,
    'manifestMutation': manifestMutation,
    'captureAssociationClearedByPacket': captureAssociationClearedByPacket,
    'finalCatalogTruth': finalCatalogTruth,
  };
}

class _JmaFinalCatalogPacketItem {
  final String caseId;
  final String fixturePath;
  final String status;
  final String evidence;
  final int? eventYear;
  final int? latestAvailableFinalCatalogYear;
  final String importCommand;
  final String dryRunLinkCommand;
  final String writeLinkCommand;
  final bool writeLinkAllowed;
  final List<String> reviewFields;
  final bool manualReviewRequired;
  final bool automaticClearance;
  final bool fixtureMutation;
  final bool catalogTruthWrite;

  const _JmaFinalCatalogPacketItem({
    required this.caseId,
    required this.fixturePath,
    required this.status,
    required this.evidence,
    required this.eventYear,
    required this.latestAvailableFinalCatalogYear,
    required this.importCommand,
    required this.dryRunLinkCommand,
    required this.writeLinkCommand,
    required this.writeLinkAllowed,
    required this.reviewFields,
    required this.manualReviewRequired,
    required this.automaticClearance,
    required this.fixtureMutation,
    required this.catalogTruthWrite,
  });

  static _JmaFinalCatalogPacketItem fromJson(Map<String, Object?> json) =>
      _JmaFinalCatalogPacketItem(
        caseId: _string(json['caseId']),
        fixturePath: _string(json['fixturePath']),
        status: _string(json['status']),
        evidence: _string(json['evidence']),
        eventYear: _int(json['eventYear']),
        latestAvailableFinalCatalogYear: _int(
          json['latestAvailableFinalCatalogYear'],
        ),
        importCommand: _string(json['importCommand']),
        dryRunLinkCommand: _string(json['dryRunLinkCommand']),
        writeLinkCommand: _string(json['writeLinkCommand']),
        writeLinkAllowed: json['writeLinkAllowed'] == true,
        reviewFields: _stringList(json['reviewFields']),
        manualReviewRequired: json['manualReviewRequired'] == true,
        automaticClearance: json['automaticClearance'] == true,
        fixtureMutation: json['fixtureMutation'] == true,
        catalogTruthWrite: json['catalogTruthWrite'] == true,
      );

  Map<String, Object?> toOperationArtifact() => {
    'kind': 'jma_final_catalog_review_packet',
    'packetStatus': status,
    'fixturePath': fixturePath,
    'evidence': evidence,
    'eventYear': eventYear,
    'latestAvailableFinalCatalogYear': latestAvailableFinalCatalogYear,
    'importCommand': importCommand,
    'dryRunLinkCommand': dryRunLinkCommand,
    'writeLinkCommand': writeLinkCommand,
    'writeLinkAllowed': writeLinkAllowed,
    'reviewFields': reviewFields,
    'manualReviewRequired': manualReviewRequired,
    'automaticClearance': automaticClearance,
    'fixtureMutation': fixtureMutation,
    'catalogTruthWrite': catalogTruthWrite,
  };
}

class _FinalCatalogOrHinetRevisionPacketItem {
  final String caseId;
  final String fixturePath;
  final String truthSource;
  final String truthQuality;
  final String validationCommand;
  final List<Object?> requiredResolutionPaths;
  final List<String> reviewFields;
  final int negativeAttemptOnlyCount;
  final bool manualReviewRequired;
  final bool automaticClearance;
  final bool fixtureMutation;
  final bool splitManifestMutation;
  final bool truthPromotion;
  final bool resolutionAllowedByPacket;

  const _FinalCatalogOrHinetRevisionPacketItem({
    required this.caseId,
    required this.fixturePath,
    required this.truthSource,
    required this.truthQuality,
    required this.validationCommand,
    required this.requiredResolutionPaths,
    required this.reviewFields,
    required this.negativeAttemptOnlyCount,
    required this.manualReviewRequired,
    required this.automaticClearance,
    required this.fixtureMutation,
    required this.splitManifestMutation,
    required this.truthPromotion,
    required this.resolutionAllowedByPacket,
  });

  static _FinalCatalogOrHinetRevisionPacketItem fromJson(
    Map<String, Object?> json,
  ) => _FinalCatalogOrHinetRevisionPacketItem(
    caseId: _string(json['caseId']),
    fixturePath: _string(json['fixturePath']),
    truthSource: _string(json['truthSource']),
    truthQuality: _string(json['truthQuality']),
    validationCommand: _string(json['validationCommand']),
    requiredResolutionPaths: _list(json['requiredResolutionPaths']),
    reviewFields: _stringList(json['reviewFields']),
    negativeAttemptOnlyCount: _int(json['negativeAttemptOnlyCount']) ?? 0,
    manualReviewRequired: json['manualReviewRequired'] == true,
    automaticClearance: json['automaticClearance'] == true,
    fixtureMutation: json['fixtureMutation'] == true,
    splitManifestMutation: json['splitManifestMutation'] == true,
    truthPromotion: json['truthPromotion'] == true,
    resolutionAllowedByPacket: json['resolutionAllowedByPacket'] == true,
  );

  Map<String, Object?> toOperationArtifact() => {
    'kind': 'final_catalog_or_hinet_revision_review_packet',
    'packetStatus': truthQuality,
    'fixturePath': fixturePath,
    'truthSource': truthSource,
    'validationCommand': validationCommand,
    'requiredResolutionPaths': requiredResolutionPaths,
    'reviewFields': reviewFields,
    'negativeAttemptOnlyCount': negativeAttemptOnlyCount,
    'manualReviewRequired': manualReviewRequired,
    'automaticClearance': automaticClearance,
    'fixtureMutation': fixtureMutation,
    'splitManifestMutation': splitManifestMutation,
    'truthPromotion': truthPromotion,
    'resolutionAllowedByPacket': resolutionAllowedByPacket,
  };
}

class _WorklistRow {
  final int priority;
  final String inputType;
  final String caseId;
  final String action;
  final String? validationCommand;
  final bool manualReviewRequired;
  final bool automaticClearance;
  final int attemptCount;
  final String? lastAttemptResult;
  final Map<String, Object?>? operationArtifact;

  const _WorklistRow({
    required this.priority,
    required this.inputType,
    required this.caseId,
    required this.action,
    required this.validationCommand,
    required this.manualReviewRequired,
    required this.automaticClearance,
    required this.attemptCount,
    required this.lastAttemptResult,
    required this.operationArtifact,
  });

  factory _WorklistRow.fromParts({
    required _QueueItem queueItem,
    required _TemplateItem? template,
    required List<_AttemptItem> attempts,
    required _RepairProbeTemplateItem? repairTemplate,
    required _AuthenticatedExportPacketItem? authenticatedExportPacket,
    required _JmaReferenceCapturePacketItem? jmaReferenceCapturePacket,
    required _JmaFinalCatalogPacketItem? jmaFinalCatalogPacket,
    required _FinalCatalogOrHinetRevisionPacketItem?
    finalCatalogOrHinetRevisionPacket,
  }) {
    return _WorklistRow(
      priority: queueItem.priority,
      inputType: queueItem.inputType,
      caseId: queueItem.caseId,
      action: template?.action.isNotEmpty == true
          ? template!.action
          : queueItem.requiredInput,
      validationCommand: template?.validationCommand.isNotEmpty == true
          ? template!.validationCommand
          : null,
      manualReviewRequired: template?.manualReviewRequired ?? true,
      automaticClearance: template?.automaticClearance ?? false,
      attemptCount: attempts.length,
      lastAttemptResult: attempts.isEmpty ? null : attempts.last.result,
      operationArtifact:
          repairTemplate?.toOperationArtifact() ??
          authenticatedExportPacket?.toOperationArtifact() ??
          jmaReferenceCapturePacket?.toOperationArtifact() ??
          jmaFinalCatalogPacket?.toOperationArtifact() ??
          finalCatalogOrHinetRevisionPacket?.toOperationArtifact(),
    );
  }

  String get operationArtifactLabel {
    final artifact = operationArtifact;
    if (artifact == null) return '`--`';
    final templateFile = artifact['templateFile']?.toString() ?? '';
    final status =
        artifact['candidateStatus']?.toString() ??
        artifact['rowStatus']?.toString() ??
        artifact['packetStatus']?.toString() ??
        '';
    if (templateFile.isEmpty) return '`$status`';
    return '`$templateFile` (`$status`)';
  }

  Map<String, Object?> toJson() => {
    'priority': priority,
    'inputType': inputType,
    'caseId': caseId,
    'action': action,
    'validationCommand': validationCommand,
    'manualReviewRequired': manualReviewRequired,
    'automaticClearance': automaticClearance,
    'attemptCount': attemptCount,
    'lastAttemptResult': lastAttemptResult,
    if (operationArtifact != null) 'operationArtifact': operationArtifact,
  };
}

Map<String, Object?> _readReport(
  File file, {
  required String expectedSchema,
  required List<String> errors,
  required String prefix,
}) {
  if (!file.existsSync()) {
    errors.add('$prefix:missing:${file.path}');
    return const {};
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      errors.add('$prefix:not_object:${file.path}');
      return const {};
    }
    final report = decoded.cast<String, Object?>();
    if (report['schemaVersion'] != expectedSchema) {
      errors.add('$prefix:unexpected_schema:${file.path}');
    }
    if (report['status'] != 'pass') {
      errors.add('$prefix:not_pass:${file.path}');
    }
    return report;
  } catch (error) {
    errors.add('$prefix:decode_failed:${file.path}:$error');
    return const {};
  }
}

Map<String, Object?> _readOptionalReport(
  File file, {
  required String expectedSchema,
  required List<String> errors,
  required List<String> warnings,
  required String prefix,
}) {
  if (!file.existsSync()) {
    warnings.add('$prefix:missing:${file.path}');
    return const {};
  }
  return _readReport(
    file,
    expectedSchema: expectedSchema,
    errors: errors,
    prefix: prefix,
  );
}

String _key(String inputType, String caseId) {
  if (inputType.isEmpty || caseId.isEmpty) return '';
  return '$inputType::$caseId';
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};

String _string(Object? value) => value?.toString().trim() ?? '';

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<String> _stringList(Object? value) =>
    _list(value).map((item) => item.toString()).toList(growable: false);
