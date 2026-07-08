import 'dart:convert';
import 'dart:io';

const _defaultReviewPath =
    '.dart_tool/hinet_capture_provenance_review/report.json';
const _defaultDecisionPath =
    'docs/data/hinet_capture_provenance_review_decisions.json';
const _defaultOutput =
    '.dart_tool/hinet_capture_exclusion_templates/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_capture_exclusion_templates.generated.md';
const _defaultTemplateDirectory =
    '.dart_tool/hinet_capture_exclusion_templates/files';

void main(List<String> args) {
  final reviewPath = _argument(args, '--review') ?? _defaultReviewPath;
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;
  final templateDirectoryPath =
      _argument(args, '--template-directory') ?? _defaultTemplateDirectory;

  final report = _ExclusionTemplateReport.build(
    reviewFile: File(reviewPath),
    decisionFile: File(decisionPath),
    templateDirectory: Directory(templateDirectoryPath),
  );

  final templateDirectory = Directory(templateDirectoryPath);
  templateDirectory.createSync(recursive: true);
  for (final template in report.templates) {
    final templateFile = File(
      '${templateDirectory.path}/${template.caseId}.json',
    );
    templateFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(template.filePayload)}\n',
    );
  }

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote Hi-net capture exclusion templates');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
  stdout.writeln('files: ${templateDirectory.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildHinetCaptureExclusionTemplateJson({
  String reviewPath = _defaultReviewPath,
  String decisionPath = _defaultDecisionPath,
  String templateDirectory = _defaultTemplateDirectory,
}) {
  return _ExclusionTemplateReport.build(
    reviewFile: File(reviewPath),
    decisionFile: File(decisionPath),
    templateDirectory: Directory(templateDirectory),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ExclusionTemplateReport {
  final String reviewPath;
  final String decisionPath;
  final String templateDirectoryPath;
  final List<_ExclusionTemplate> templates;
  final List<String> errors;
  final List<String> warnings;

  const _ExclusionTemplateReport({
    required this.reviewPath,
    required this.decisionPath,
    required this.templateDirectoryPath,
    required this.templates,
    required this.errors,
    required this.warnings,
  });

  factory _ExclusionTemplateReport.build({
    required File reviewFile,
    required File decisionFile,
    required Directory templateDirectory,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final review = _readMap(
      reviewFile,
      expectedSchema: 'hinet_capture_provenance_review_v1',
      missingError: 'capture_provenance_review_missing',
      schemaError: 'unexpected_capture_provenance_review_schema',
      errors: errors,
    );
    final decisions = _readMap(
      decisionFile,
      expectedSchema: 'hinet_capture_provenance_review_decisions_v1',
      missingError: 'capture_review_decision_file_missing',
      schemaError: 'unexpected_capture_review_decision_schema',
      errors: errors,
    );
    final decisionByCaseId = <String, Map<String, Object?>>{
      for (final raw in _list(decisions['cases']))
        _map(raw)['caseId'].toString(): _map(raw),
    };
    final templates = <_ExclusionTemplate>[];
    for (final rawCase in _list(review['cases'])) {
      final item = _map(rawCase);
      if (item['readyAfterExclusion'] == true) continue;
      if (item['decisionStatus'] != 'pending_capture_repair_or_exclusion') {
        continue;
      }
      final caseId = item['caseId']?.toString() ?? '';
      final decision = decisionByCaseId[caseId];
      if (decision == null) {
        errors.add('capture_exclusion_template_missing_decision:$caseId');
        continue;
      }
      templates.add(
        _ExclusionTemplate.fromReviewCase(
          item,
          decision,
          templateDirectory.path,
        ),
      );
    }
    templates.sort((left, right) => left.caseId.compareTo(right.caseId));
    return _ExclusionTemplateReport(
      reviewPath: reviewFile.path,
      decisionPath: decisionFile.path,
      templateDirectoryPath: templateDirectory.path,
      templates: templates,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'hinet_capture_exclusion_templates_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'reviewPath': reviewPath,
    'decisionPath': decisionPath,
    'templateDirectory': templateDirectoryPath,
    'summary': {
      'exclusionTemplateCount': templates.length,
      'manualReviewRequiredCount': templates.length,
      'automaticClearanceCount': 0,
      'ledgerMutationCount': 0,
      'affectedFileCount': templates.fold<int>(
        0,
        (total, item) => total + item.affectedFiles.length,
      ),
    },
    'errors': errors,
    'warnings': warnings,
    'templates': templates.map((template) => template.toJson()).toList(),
  };

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Capture Exclusion Templates')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Review report: `$reviewPath`')
      ..writeln('- Decision file: `$decisionPath`')
      ..writeln('- Template directory: `$templateDirectoryPath`')
      ..writeln('- Exclusion templates: `${summary['exclusionTemplateCount']}`')
      ..writeln(
        '- Manual-review required: '
        '`${summary['manualReviewRequiredCount']}`',
      )
      ..writeln('- Automatic clearances: `0`')
      ..writeln('- Ledger mutations: `0`')
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
      ..writeln('| Case | File | Affected files | Suggested excluded files |')
      ..writeln('| --- | --- | --- | --- |');
    for (final template in templates) {
      buffer.writeln(
        '| `${template.caseId}` | `${template.outputFile}` | '
        '`${template.affectedFiles.join('`, `')}` | '
        '`${template.suggestedExcludedFiles.join('`, `')}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- These files are scratch templates only. They do not edit '
        '`docs/data/hinet_capture_provenance_review_decisions.json`.',
      )
      ..writeln(
        '- Prefer repairing the missing GIF. Use exclusion only after explicit '
        'review confirms the missing frame is acceptable for constrained split use.',
      );
    return buffer.toString();
  }
}

class _ExclusionTemplate {
  final String caseId;
  final String outputFile;
  final List<String> affectedFiles;
  final List<String> suggestedExcludedFiles;
  final Map<String, Object?> filePayload;

  const _ExclusionTemplate({
    required this.caseId,
    required this.outputFile,
    required this.affectedFiles,
    required this.suggestedExcludedFiles,
    required this.filePayload,
  });

  factory _ExclusionTemplate.fromReviewCase(
    Map<String, Object?> reviewCase,
    Map<String, Object?> decision,
    String templateDirectoryPath,
  ) {
    final caseId = reviewCase['caseId']?.toString() ?? '';
    final affectedFiles = _list(reviewCase['blockingEvidence'])
        .map((entry) => _map(entry)['affectedFile']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final failedCount = _asInt(reviewCase['captureFailedGifCount']) ?? 0;
    final missingCount = _asInt(reviewCase['captureMissingFrameCount']) ?? 0;
    final suggestedExcludedFiles = <String>[
      ...affectedFiles,
      for (
        var index = affectedFiles.length;
        index < failedCount + missingCount;
        index += 1
      )
        'missing_frame_${index - affectedFiles.length + 1}',
    ];
    final outputFile = '$templateDirectoryPath/$caseId.json'.replaceAll(
      '\\',
      '/',
    );
    return _ExclusionTemplate(
      caseId: caseId,
      outputFile: outputFile,
      affectedFiles: affectedFiles,
      suggestedExcludedFiles: suggestedExcludedFiles,
      filePayload: {
        '_instructions': [
          'Prefer repairing the missing GIF before using this exclusion template.',
          'If exclusion is approved, copy this case object into docs/data/hinet_capture_provenance_review_decisions.json.',
          'Replace every <fill-...> placeholder and rerun tools/validate_hinet_capture_provenance_review.ps1.',
        ],
        '_captureIssue': {
          'captureDirectory': reviewCase['captureDirectory'],
          'captureExpectedGifCount': reviewCase['captureExpectedGifCount'],
          'captureDownloadedGifCount': reviewCase['captureDownloadedGifCount'],
          'captureFailedGifCount': failedCount,
          'captureMissingFrameCount': missingCount,
          'blockingEvidence': reviewCase['blockingEvidence'],
        },
        'caseId': caseId,
        'decisionStatus': 'capture_frame_exclusion_approved',
        'reviewedAtUtc': '<fill-reviewed-at-utc>',
        'reviewer': '<fill-reviewer-id>',
        'exclusionApproved': true,
        'excludedFiles': suggestedExcludedFiles,
        'exclusionReason': '<fill-explicit-review-reason>',
        'requiredActions': decision['requiredActions'],
        'notes': decision['notes'],
      },
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'outputFile': outputFile,
    'affectedFiles': affectedFiles,
    'suggestedExcludedFiles': suggestedExcludedFiles,
    'manualReviewRequired': true,
    'automaticClearance': false,
  };
}

Map<String, Object?> _readMap(
  File file, {
  required String expectedSchema,
  required String missingError,
  required String schemaError,
  required List<String> errors,
}) {
  if (!file.existsSync()) {
    errors.add('$missingError:${file.path}');
    return <String, Object?>{};
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  if (data['schemaVersion'] != expectedSchema) {
    errors.add(schemaError);
  }
  if (data['status'] != null && data['status'] != 'pass') {
    errors.add('${schemaError}_not_pass');
  }
  return data;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
