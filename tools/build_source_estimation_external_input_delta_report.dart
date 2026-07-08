import 'dart:convert';
import 'dart:io';

const _defaultQueuePath =
    '.dart_tool/source_estimation_external_input_queue/report.json';
const _defaultTemplatesPath =
    '.dart_tool/source_estimation_external_input_templates/report.json';
const _defaultOutput =
    '.dart_tool/source_estimation_external_input_delta/report.json';
const _defaultMarkdown =
    'docs/baselines/source_estimation_external_input_delta.generated.md';

void main(List<String> args) {
  final queuePath = _argument(args, '--queue') ?? _defaultQueuePath;
  final templatesPath = _argument(args, '--templates') ?? _defaultTemplatesPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ExternalInputDeltaReport.build(
    queueFile: File(queuePath),
    templatesFile: File(templatesPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-estimation external input delta report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildSourceEstimationExternalInputDeltaJson({
  String queuePath = _defaultQueuePath,
  String templatesPath = _defaultTemplatesPath,
}) {
  return _ExternalInputDeltaReport.build(
    queueFile: File(queuePath),
    templatesFile: File(templatesPath),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ExternalInputDeltaReport {
  final String queuePath;
  final String templatesPath;
  final List<_DeltaRow> rows;
  final List<String> errors;
  final List<String> warnings;

  const _ExternalInputDeltaReport({
    required this.queuePath,
    required this.templatesPath,
    required this.rows,
    required this.errors,
    required this.warnings,
  });

  factory _ExternalInputDeltaReport.build({
    required File queueFile,
    required File templatesFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final queue = _readReport(
      queueFile,
      expectedSchema: 'source_estimation_external_input_queue_v1',
      errors: errors,
      prefix: 'external_input_delta_queue',
    );
    final templates = _readReport(
      templatesFile,
      expectedSchema: 'source_estimation_external_input_templates_v1',
      errors: errors,
      prefix: 'external_input_delta_templates',
    );

    final queueItems = _list(queue['items'])
        .map(_map)
        .map(_QueueItem.fromJson)
        .where((item) => item.key.isNotEmpty)
        .toList(growable: false);
    final templateItems = _list(templates['templates'])
        .map(_map)
        .map(_TemplateItem.fromJson)
        .where((item) => item.key.isNotEmpty)
        .toList(growable: false);

    final queueByKey = <String, _QueueItem>{};
    for (final item in queueItems) {
      if (queueByKey.containsKey(item.key)) {
        errors.add('external_input_delta_duplicate_queue_item:${item.key}');
      }
      queueByKey[item.key] = item;
    }

    final templatesByKey = <String, List<_TemplateItem>>{};
    for (final template in templateItems) {
      templatesByKey.putIfAbsent(template.key, () => []).add(template);
    }

    final rows = <_DeltaRow>[];
    for (final queueItem in queueItems) {
      final matchingTemplates = templatesByKey[queueItem.key] ?? const [];
      if (matchingTemplates.isEmpty) {
        errors.add('external_input_delta_missing_template:${queueItem.key}');
        rows.add(_DeltaRow.missing(queueItem));
        continue;
      }
      if (matchingTemplates.length > 1) {
        errors.add('external_input_delta_duplicate_template:${queueItem.key}');
      }
      for (final template in matchingTemplates) {
        final row = _DeltaRow.compare(queueItem, template);
        rows.add(row);
        if (row.priorityMatches == false) {
          errors.add('external_input_delta_priority_mismatch:${queueItem.key}');
        }
        if (row.manualReviewRequired != true) {
          errors.add(
            'external_input_delta_template_not_manual_review:${queueItem.key}',
          );
        }
        if (row.automaticClearance != false) {
          errors.add(
            'external_input_delta_template_allows_clearance:${queueItem.key}',
          );
        }
      }
    }

    for (final template in templateItems) {
      if (!queueByKey.containsKey(template.key)) {
        errors.add('external_input_delta_stale_template:${template.key}');
        rows.add(_DeltaRow.stale(template));
      }
    }

    final templateSummary = _map(templates['summary']);
    if (templateSummary['automaticClearanceCount'] != 0) {
      errors.add('external_input_delta_summary_allows_clearance');
    }
    if (templateSummary['ledgerMutationCount'] != 0) {
      errors.add('external_input_delta_summary_mutates_ledger');
    }

    rows.sort((left, right) {
      final priority = left.priority.compareTo(right.priority);
      if (priority != 0) return priority;
      final type = left.inputType.compareTo(right.inputType);
      if (type != 0) return type;
      return left.caseId.compareTo(right.caseId);
    });

    return _ExternalInputDeltaReport(
      queuePath: queueFile.path,
      templatesPath: templatesFile.path,
      rows: rows,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final matchedRows = rows.where((row) => row.status == 'matched').length;
    final missingRows = rows
        .where((row) => row.status == 'missing_template')
        .length;
    final staleRows = rows
        .where((row) => row.status == 'stale_template')
        .length;
    return {
      'schemaVersion': 'source_estimation_external_input_delta_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'queuePath': queuePath,
      'templatesPath': templatesPath,
      'summary': {
        'deltaRowCount': rows.length,
        'matchedTemplateCount': matchedRows,
        'missingTemplateCount': missingRows,
        'staleTemplateCount': staleRows,
        'priorityMismatchCount': rows
            .where((row) => row.priorityMatches == false)
            .length,
        'nonManualReviewTemplateCount': rows
            .where((row) => row.manualReviewRequired == false)
            .length,
        'automaticClearanceTemplateCount': rows
            .where((row) => row.automaticClearance == true)
            .length,
        'coverageComplete': missingRows == 0 && staleRows == 0,
        'safeTemplateSemantics': rows.every(
          (row) =>
              row.status != 'matched' ||
              (row.manualReviewRequired == true &&
                  row.automaticClearance == false),
        ),
      },
      'errors': errors,
      'warnings': warnings,
      'rows': rows.map((row) => row.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Source Estimation External Input Delta')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Queue: `$queuePath`')
      ..writeln('- Templates: `$templatesPath`')
      ..writeln('- Matched templates: `${summary['matchedTemplateCount']}`')
      ..writeln('- Missing templates: `${summary['missingTemplateCount']}`')
      ..writeln('- Stale templates: `${summary['staleTemplateCount']}`')
      ..writeln('- Coverage complete: `${summary['coverageComplete']}`')
      ..writeln(
        '- Safe template semantics: `${summary['safeTemplateSemantics']}`',
      )
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
      ..writeln('## Delta')
      ..writeln()
      ..writeln(
        '| Priority | Type | Case | Status | Priority match | Manual review | Auto clearance |',
      )
      ..writeln('| ---: | --- | --- | --- | --- | --- | --- |');
    for (final row in rows) {
      buffer.writeln(
        '| ${row.priority} | `${row.inputType}` | `${row.caseId}` | '
        '`${row.status}` | `${row.priorityMatches}` | '
        '`${row.manualReviewRequired}` | `${row.automaticClearance}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This delta only verifies that the intake queue and generated '
        'templates agree one-for-one.',
      )
      ..writeln(
        '- A matched template is still operational documentation only; it does '
        'not clear capture, catalog, truth-quality or split blockers.',
      );
    return buffer.toString();
  }
}

class _QueueItem {
  final int priority;
  final String inputType;
  final String caseId;

  const _QueueItem({
    required this.priority,
    required this.inputType,
    required this.caseId,
  });

  String get key => _key(inputType, caseId);

  static _QueueItem fromJson(Map<String, Object?> json) => _QueueItem(
    priority: (json['priority'] as num?)?.toInt() ?? 999,
    inputType: json['inputType']?.toString() ?? '',
    caseId: json['caseId']?.toString() ?? '',
  );
}

class _TemplateItem {
  final int priority;
  final String inputType;
  final String caseId;
  final bool? manualReviewRequired;
  final bool? automaticClearance;

  const _TemplateItem({
    required this.priority,
    required this.inputType,
    required this.caseId,
    required this.manualReviewRequired,
    required this.automaticClearance,
  });

  String get key => _key(inputType, caseId);

  static _TemplateItem fromJson(Map<String, Object?> json) => _TemplateItem(
    priority: (json['priority'] as num?)?.toInt() ?? 999,
    inputType: json['inputType']?.toString() ?? '',
    caseId: json['caseId']?.toString() ?? '',
    manualReviewRequired: json['manualReviewRequired'] as bool?,
    automaticClearance: json['automaticClearance'] as bool?,
  );
}

class _DeltaRow {
  final int priority;
  final String inputType;
  final String caseId;
  final String status;
  final bool? priorityMatches;
  final bool? manualReviewRequired;
  final bool? automaticClearance;

  const _DeltaRow({
    required this.priority,
    required this.inputType,
    required this.caseId,
    required this.status,
    required this.priorityMatches,
    required this.manualReviewRequired,
    required this.automaticClearance,
  });

  factory _DeltaRow.compare(_QueueItem queue, _TemplateItem template) {
    return _DeltaRow(
      priority: queue.priority,
      inputType: queue.inputType,
      caseId: queue.caseId,
      status: 'matched',
      priorityMatches: queue.priority == template.priority,
      manualReviewRequired: template.manualReviewRequired,
      automaticClearance: template.automaticClearance,
    );
  }

  factory _DeltaRow.missing(_QueueItem queue) {
    return _DeltaRow(
      priority: queue.priority,
      inputType: queue.inputType,
      caseId: queue.caseId,
      status: 'missing_template',
      priorityMatches: null,
      manualReviewRequired: null,
      automaticClearance: null,
    );
  }

  factory _DeltaRow.stale(_TemplateItem template) {
    return _DeltaRow(
      priority: template.priority,
      inputType: template.inputType,
      caseId: template.caseId,
      status: 'stale_template',
      priorityMatches: null,
      manualReviewRequired: template.manualReviewRequired,
      automaticClearance: template.automaticClearance,
    );
  }

  Map<String, Object?> toJson() => {
    'priority': priority,
    'inputType': inputType,
    'caseId': caseId,
    'status': status,
    'priorityMatches': priorityMatches,
    'manualReviewRequired': manualReviewRequired,
    'automaticClearance': automaticClearance,
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
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  if (decoded['schemaVersion'] != expectedSchema) {
    errors.add('$prefix:unexpected_schema:${file.path}');
  }
  if (decoded['status'] != 'pass') {
    errors.add('$prefix:not_pass:${file.path}');
  }
  return decoded;
}

String _key(String inputType, String caseId) {
  if (inputType.isEmpty || caseId.isEmpty) return '';
  return '$inputType::$caseId';
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
