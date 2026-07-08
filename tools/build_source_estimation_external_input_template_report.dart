import 'dart:convert';
import 'dart:io';

const _defaultQueuePath =
    '.dart_tool/source_estimation_external_input_queue/report.json';
const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultOutput =
    '.dart_tool/source_estimation_external_input_templates/report.json';
const _defaultMarkdown =
    'docs/baselines/source_estimation_external_input_templates.generated.md';

void main(List<String> args) {
  final queuePath = _argument(args, '--queue') ?? _defaultQueuePath;
  final fixtureDirectory =
      _argument(args, '--fixture-directory') ?? _defaultFixtureDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _TemplateReport.build(
    queueFile: File(queuePath),
    fixtureDirectory: Directory(fixtureDirectory),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-estimation external input template report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildSourceEstimationExternalInputTemplateJson({
  String queuePath = _defaultQueuePath,
  String fixtureDirectory = _defaultFixtureDirectory,
}) {
  return _TemplateReport.build(
    queueFile: File(queuePath),
    fixtureDirectory: Directory(fixtureDirectory),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _TemplateReport {
  final String queuePath;
  final String fixtureDirectoryPath;
  final List<_InputTemplate> templates;
  final List<String> errors;
  final List<String> warnings;

  const _TemplateReport({
    required this.queuePath,
    required this.fixtureDirectoryPath,
    required this.templates,
    required this.errors,
    required this.warnings,
  });

  factory _TemplateReport.build({
    required File queueFile,
    required Directory fixtureDirectory,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final templates = <_InputTemplate>[];
    final fixtureByCaseId = _fixtureIndex(fixtureDirectory, warnings);

    if (!queueFile.existsSync()) {
      errors.add('external_input_queue_missing:${queueFile.path}');
    } else {
      final queue =
          jsonDecode(queueFile.readAsStringSync()) as Map<String, Object?>;
      if (queue['schemaVersion'] !=
          'source_estimation_external_input_queue_v1') {
        errors.add('external_input_queue_unexpected_schema:${queueFile.path}');
      }
      if (queue['status'] != 'pass') {
        errors.add('external_input_queue_not_pass:${queueFile.path}');
      }
      for (final rawItem in _list(queue['items'])) {
        final item = _map(rawItem);
        final template = _InputTemplate.fromQueueItem(item, fixtureByCaseId);
        if (template == null) {
          warnings.add(
            'external_input_template_unknown_type:${item['inputType']}',
          );
        } else {
          templates.add(template);
        }
      }
    }

    templates.sort((left, right) {
      final priority = left.priority.compareTo(right.priority);
      if (priority != 0) return priority;
      final type = left.inputType.compareTo(right.inputType);
      if (type != 0) return type;
      return left.caseId.compareTo(right.caseId);
    });

    return _TemplateReport(
      queuePath: queueFile.path,
      fixtureDirectoryPath: fixtureDirectory.path,
      templates: templates,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final byType = <String, int>{};
    for (final template in templates) {
      byType[template.inputType] = (byType[template.inputType] ?? 0) + 1;
    }
    return {
      'schemaVersion': 'source_estimation_external_input_templates_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'queuePath': queuePath,
      'fixtureDirectory': fixtureDirectoryPath,
      'summary': {
        'templateCount': templates.length,
        'inputTypeCounts': byType,
        'manualReviewRequiredCount': templates
            .where((template) => template.manualReviewRequired)
            .length,
        'automaticClearanceCount': 0,
        'ledgerMutationCount': 0,
      },
      'errors': errors,
      'warnings': warnings,
      'templates': templates.map((template) => template.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final counts = (summary['inputTypeCounts'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Source Estimation External Input Templates')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Queue: `$queuePath`')
      ..writeln('- Fixture directory: `$fixtureDirectoryPath`')
      ..writeln('- Templates: `${summary['templateCount']}`')
      ..writeln(
        '- Manual-review required: '
        '`${summary['manualReviewRequiredCount']}`',
      )
      ..writeln('- Automatic clearances: `0`')
      ..writeln('- Ledger mutations: `0`')
      ..writeln()
      ..writeln('## Input Type Counts')
      ..writeln()
      ..writeln('| Input type | Count |')
      ..writeln('| --- | ---: |');
    for (final type in counts.keys.toList()..sort()) {
      buffer.writeln('| `$type` | ${counts[type]} |');
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
      ..writeln('## Templates')
      ..writeln()
      ..writeln('| Priority | Type | Case | Target | Action | Validation |')
      ..writeln('| ---: | --- | --- | --- | --- | --- |');
    for (final template in templates) {
      buffer.writeln(
        '| ${template.priority} | `${template.inputType}` | '
        '`${template.caseId}` | `${template.targetPath}` | '
        '${template.action} | `${template.validationCommand}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- These templates are instructions only. This report does not edit '
        'capture packages, ledgers, fixtures, split manifests or production '
        'source-estimation behavior.',
      )
      ..writeln(
        '- Filling a template only makes the corresponding downstream guard '
        'eligible to re-run. It never clears source truth or capture blockers '
        'by itself.',
      );
    return buffer.toString();
  }
}

class _InputTemplate {
  final int priority;
  final String inputType;
  final String caseId;
  final String targetPath;
  final String action;
  final String validationCommand;
  final bool manualReviewRequired;
  final Map<String, Object?> template;
  final List<String> notes;

  const _InputTemplate({
    required this.priority,
    required this.inputType,
    required this.caseId,
    required this.targetPath,
    required this.action,
    required this.validationCommand,
    required this.manualReviewRequired,
    required this.template,
    required this.notes,
  });

  static _InputTemplate? fromQueueItem(
    Map<String, Object?> item,
    Map<String, String> fixtureByCaseId,
  ) {
    final inputType = item['inputType']?.toString() ?? '';
    final caseId = item['caseId']?.toString() ?? '';
    final priority = (item['priority'] as num?)?.toInt() ?? 999;
    final details = item['details']?.toString() ?? '';
    final requiredInput = item['requiredInput']?.toString() ?? '';
    final fixturePath =
        fixtureByCaseId[caseId] ??
        'test/fixtures/source_estimation/<fixture-for-$caseId>.json';
    switch (inputType) {
      case 'missing_gif_archive_copy':
        final fileName = _firstBacktick(requiredInput) ?? '<missing.gif>';
        final remoteHint =
            _detailValue(details, 'remoteHint') ??
            _detailValue(details, 'historicalRemoteHint');
        final remoteRetrievalAllowed =
            _detailValue(details, 'remoteRetrievalAllowed') == 'true';
        return _InputTemplate(
          priority: priority,
          inputType: inputType,
          caseId: caseId,
          targetPath:
              'tmp/captures | tmp/quarantine | test/fixtures/source_estimation',
          action: 'place a valid GIF copy under a repair scan root',
          validationCommand:
              'powershell -NoProfile -ExecutionPolicy Bypass -File tools\\validate_hinet_capture_repair_probe.ps1',
          manualReviewRequired: true,
          template: {
            'fileName': fileName,
            'acceptedScanRoots': [
              'tmp/captures',
              'tmp/quarantine',
              'test/fixtures/source_estimation',
            ],
            'remoteHint': remoteHint,
            'remoteRetrievalAllowed': remoteRetrievalAllowed,
            'maxRemoteAgeHours': 3,
            'afterPlacingFile': [
              'run the repair probe',
              'review the resulting candidate path, byte count and SHA-256',
            ],
          },
          notes: const [
            'A remote hint is not evidence until a local valid GIF exists.',
            'Do not remotely fetch kmoni GIFs older than 3 hours; historical URL hints are provenance only.',
            'This template does not copy the GIF into the replay package.',
          ],
        );
      case 'authenticated_hinet_export_row':
        return _InputTemplate(
          priority: priority,
          inputType: inputType,
          caseId: caseId,
          targetPath: 'docs/data/hinet_authenticated_export_rows.json',
          action: 'replace the pending row with a submitted_for_review row',
          validationCommand:
              'powershell -NoProfile -ExecutionPolicy Bypass -File tools\\validate_hinet_authenticated_export_review.ps1',
          manualReviewRequired: true,
          template: {
            'caseId': caseId,
            'status': 'submitted_for_review',
            'submittedRow': {
              'caseId': caseId,
              'sourceType':
                  '<hinet_preliminary_catalog|hinet_jma_unified_catalog>',
              'sourceUrl': '<authenticated-event-row-url>',
              'sourceVersionOrPageDate': '<page-date-or-catalog-version>',
              'checkedAtUtc': '<YYYY-MM-DDTHH:MM:SSZ>',
              'reviewer': '<reviewer-id>',
              'originTimeJst': '<YYYY-MM-DDTHH:MM:SS+09:00>',
              'latitude': '<number>',
              'longitude': '<number>',
              'depthKm': '<number>',
              'magnitude': '<number>',
              'region': '<region>',
              'rawRowText': '<verbatim event-row text>',
            },
            'rejectionReason': null,
            'decisionImpact': 'candidate_evidence_only_until_reviewed',
          },
          notes: const [
            'JMA daily hypocenter rows and EQuake text must not be submitted here.',
            'A valid submitted row still needs explicit decision-ledger review.',
          ],
        );
      case 'local_jma_reference_capture_package':
        final dryRunCommand =
            'dart run tools/import_jma_reference_capture_package.dart '
            '--input <filled-capture-association-json> --dry-run';
        return _InputTemplate(
          priority: priority,
          inputType: inputType,
          caseId: caseId,
          targetPath: 'docs/data/jma_reference_event_candidates.json',
          action: 'associate an existing local replay/capture package',
          validationCommand:
              'powershell -NoProfile -ExecutionPolicy Bypass -File tools\\validate_jma_reference_capture_association.ps1',
          manualReviewRequired: true,
          template: {
            'eventId': caseId,
            'status': 'capture_associated_pending_final_catalog',
            'reviewedAtUtc': '<YYYY-MM-DDTHH:MM:SSZ>',
            'reviewer': '<reviewer-id>',
            'captureDirectory': '<path-to-local-replay-or-capture-package>',
            'manifestPath': '<path-to-manifest-json-under-capture-directory>',
            'packageSource': '<local-capture-source-description>',
            'associationReason': '<why-this-package-matches-the-event>',
            'requiredLocalFiles': [
              'manifest.json or replay_manifest.json',
              'frame data / raw GIFs as recorded by the package manifest',
            ],
            'dryRunCommand': dryRunCommand,
            'afterFilling': [
              'run the dryRunCommand before any write',
              'inspect importer errors and package frame evidence',
              'rerun the JMA reference capture association validator',
            ],
          },
          notes: const [
            'Use tools/import_jma_reference_capture_package.dart with --dry-run first.',
            'Associating a capture package does not make the JMA reference a final catalog truth label.',
            'Keep the event reference-only until final-catalog linking clears.',
            'This template must not clear final-catalog blockers or assign split membership.',
          ],
        );
      case 'versioned_jma_final_catalog_record':
        return _InputTemplate(
          priority: priority,
          inputType: inputType,
          caseId: caseId,
          targetPath: fixturePath,
          action:
              'import a versioned JMA catalog and link the matching fixture',
          validationCommand:
              'powershell -NoProfile -ExecutionPolicy Bypass -File tools\\validate_jma_catalog_availability.ps1',
          manualReviewRequired: true,
          template: {
            'importCommand':
                'dart run tools/import_jma_hypocenter.dart --input <official-hypocenter-file> --output docs/data/jma_catalogs/<catalog>.json --catalog-id <id> --revision <revision> --source-url <official-url>',
            'dryRunLinkCommand':
                'dart run tools/link_jma_catalog.dart --catalog docs/data/jma_catalogs/<catalog>.json --case $fixturePath',
            'writeLinkCommand':
                'dart run tools/link_jma_catalog.dart --catalog docs/data/jma_catalogs/<catalog>.json --case $fixturePath --write',
          },
          notes: const [
            'Only use a versioned official JMA final catalog record.',
            'Run without --write first and inspect match status/candidates.',
          ],
        );
      case 'final_catalog_or_hinet_revision':
        return _InputTemplate(
          priority: priority,
          inputType: inputType,
          caseId: caseId,
          targetPath: fixturePath,
          action: 'link a final catalog row or revised Hi-net source',
          validationCommand:
              'powershell -NoProfile -ExecutionPolicy Bypass -File tools\\validate_source_estimation_split_blocker_queue.ps1',
          manualReviewRequired: true,
          template: {
            'preferredPath': 'versioned JMA final catalog link',
            'alternatePath': 'reviewed revised Hi-net source evidence',
            'fixturePath': fixturePath,
            'decisionLedger':
                'docs/data/hinet_truth_quality_review_decisions.json',
          },
          notes: const [
            'Do not use EQuake source-estimation text as truth.',
            'Do not update split assignment until the blocker queue drops this case.',
          ],
        );
      default:
        return null;
    }
  }

  Map<String, Object?> toJson() => {
    'priority': priority,
    'inputType': inputType,
    'caseId': caseId,
    'targetPath': targetPath,
    'action': action,
    'validationCommand': validationCommand,
    'manualReviewRequired': manualReviewRequired,
    'automaticClearance': false,
    'template': template,
    'notes': notes,
  };
}

Map<String, String> _fixtureIndex(Directory directory, List<String> warnings) {
  final result = <String, String>{};
  if (!directory.existsSync()) {
    warnings.add('fixture_directory_missing:${directory.path}');
    return result;
  }
  for (final entity in directory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    try {
      final decoded =
          jsonDecode(entity.readAsStringSync()) as Map<String, Object?>;
      final caseId = decoded['caseId']?.toString();
      if (caseId != null && caseId.isNotEmpty) {
        result[caseId] = entity.path.replaceAll('\\', '/');
      }
    } catch (_) {
      // Non-case JSON files in the fixture directory are ignored.
    }
  }
  return result;
}

String? _firstBacktick(String value) {
  final match = RegExp(r'`([^`]+)`').firstMatch(value);
  return match?.group(1);
}

String? _detailValue(String details, String key) {
  final parts = details.split(';').map((part) => part.trim());
  for (final part in parts) {
    final prefix = '$key=';
    if (part.startsWith(prefix)) return part.substring(prefix.length);
  }
  return null;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
