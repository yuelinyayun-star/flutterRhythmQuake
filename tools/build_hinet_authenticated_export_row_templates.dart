import 'dart:convert';
import 'dart:io';

const _defaultRequestPath = 'docs/data/hinet_authenticated_export_request.json';
const _defaultRowsPath = 'docs/data/hinet_authenticated_export_rows.json';
const _defaultOutput =
    '.dart_tool/hinet_authenticated_export_row_templates/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_authenticated_export_row_templates.generated.md';
const _defaultTemplateDirectory =
    '.dart_tool/hinet_authenticated_export_row_templates/files';

void main(List<String> args) {
  final requestPath = _argument(args, '--requests') ?? _defaultRequestPath;
  final rowsPath = _argument(args, '--rows') ?? _defaultRowsPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;
  final templateDirectoryPath =
      _argument(args, '--template-directory') ?? _defaultTemplateDirectory;

  final report = _RowTemplateReport.build(
    requestFile: File(requestPath),
    rowsFile: File(rowsPath),
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

  stdout.writeln('wrote Hi-net authenticated export row templates');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
  stdout.writeln('files: ${templateDirectory.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildHinetAuthenticatedExportRowTemplatesJson({
  String requestPath = _defaultRequestPath,
  String rowsPath = _defaultRowsPath,
  String templateDirectory = _defaultTemplateDirectory,
}) {
  return _RowTemplateReport.build(
    requestFile: File(requestPath),
    rowsFile: File(rowsPath),
    templateDirectory: Directory(templateDirectory),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _RowTemplateReport {
  final String requestPath;
  final String rowsPath;
  final String templateDirectoryPath;
  final List<_RowTemplate> templates;
  final List<String> errors;
  final List<String> warnings;

  const _RowTemplateReport({
    required this.requestPath,
    required this.rowsPath,
    required this.templateDirectoryPath,
    required this.templates,
    required this.errors,
    required this.warnings,
  });

  factory _RowTemplateReport.build({
    required File requestFile,
    required File rowsFile,
    required Directory templateDirectory,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final requestData = _readMap(
      requestFile,
      expectedSchema: 'hinet_authenticated_export_request_v1',
      schemaError: 'unexpected_authenticated_export_request_schema',
      missingError: 'authenticated_export_request_missing',
      errors: errors,
    );
    final rowsData = _readMap(
      rowsFile,
      expectedSchema: 'hinet_authenticated_export_rows_v1',
      schemaError: 'unexpected_authenticated_export_rows_schema',
      missingError: 'authenticated_export_rows_missing',
      errors: errors,
    );

    final sourceUrlByType = <String, String>{
      for (final raw in _list(requestData['sourcePaths']))
        _map(raw)['sourceType'].toString(): _map(raw)['sourceUrl'].toString(),
    };
    final requestByCaseId = <String, Map<String, Object?>>{
      for (final raw in _list(requestData['requests']))
        _map(raw)['caseId'].toString(): _map(raw),
    };

    final templates = <_RowTemplate>[];
    for (final rawRow in _list(rowsData['rows'])) {
      final row = _map(rawRow);
      final caseId = row['caseId']?.toString() ?? '';
      if (row['status'] != 'pending_export') continue;
      final request = requestByCaseId[caseId];
      if (request == null) {
        errors.add('authenticated_export_request_missing_for_template:$caseId');
        continue;
      }
      templates.add(
        _RowTemplate.fromRequest(
          request,
          sourceUrlByType,
          templateDirectory.path,
        ),
      );
    }

    templates.sort((left, right) => left.caseId.compareTo(right.caseId));

    return _RowTemplateReport(
      requestPath: requestFile.path,
      rowsPath: rowsFile.path,
      templateDirectoryPath: templateDirectory.path,
      templates: templates,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'hinet_authenticated_export_row_templates_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'requestPath': requestPath,
    'rowsPath': rowsPath,
    'templateDirectory': templateDirectoryPath,
    'summary': {
      'rowTemplateCount': templates.length,
      'manualReviewRequiredCount': templates.length,
      'automaticClearanceCount': 0,
      'credentialFieldCount': 0,
    },
    'errors': errors,
    'warnings': warnings,
    'templates': templates.map((template) => template.toJson()).toList(),
  };

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Authenticated Export Row Templates')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Request file: `$requestPath`')
      ..writeln('- Rows file: `$rowsPath`')
      ..writeln('- Template directory: `$templateDirectoryPath`')
      ..writeln('- Row templates: `${summary['rowTemplateCount']}`')
      ..writeln(
        '- Manual-review required: '
        '`${summary['manualReviewRequiredCount']}`',
      )
      ..writeln('- Automatic clearances: `0`')
      ..writeln('- Credential fields: `0`')
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
      ..writeln('| Case | File | Preferred source | Query window |')
      ..writeln('| --- | --- | --- | --- |');
    for (final template in templates) {
      buffer.writeln(
        '| `${template.caseId}` | `${template.outputFile}` | '
        '`${template.preferredSourceType}` | '
        '`${template.queryWindowLabel}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- These files are scratch templates only. They are written under '
        '`.dart_tool` and do not edit `docs/data/hinet_authenticated_export_rows.json`.',
      )
      ..writeln(
        '- Fill a template from an authenticated event-level Hi-net/JMA row, '
        'then pass it to `tools/import_hinet_authenticated_export_row.dart`.',
      )
      ..writeln(
        '- Do not add credentials, cookies or session material to any template.',
      );
    return buffer.toString();
  }
}

class _RowTemplate {
  final String caseId;
  final String outputFile;
  final String preferredSourceType;
  final String queryWindowLabel;
  final Map<String, Object?> filePayload;

  const _RowTemplate({
    required this.caseId,
    required this.outputFile,
    required this.preferredSourceType,
    required this.queryWindowLabel,
    required this.filePayload,
  });

  factory _RowTemplate.fromRequest(
    Map<String, Object?> request,
    Map<String, String> sourceUrlByType,
    String templateDirectoryPath,
  ) {
    final caseId = request['caseId']?.toString() ?? '';
    final preferredSourceType =
        request['preferredSourceType']?.toString() ??
        'hinet_jma_unified_catalog';
    final sourceUrl =
        sourceUrlByType[preferredSourceType] ?? '<fill-source-url>';
    final queryWindow = _map(request['queryWindowJst']);
    final start = queryWindow['start']?.toString() ?? '<start>';
    final end = queryWindow['end']?.toString() ?? '<end>';
    final outputFile = '$templateDirectoryPath/$caseId.json'.replaceAll(
      '\\',
      '/',
    );

    return _RowTemplate(
      caseId: caseId,
      outputFile: outputFile,
      preferredSourceType: preferredSourceType,
      queryWindowLabel: '$start..$end',
      filePayload: {
        '_instructions': [
          'Fill values from one authenticated event-level Hi-net/JMA row.',
          'Remove no fields; do not add username, password, cookie, token or session data.',
          'Run: dart run tools/import_hinet_authenticated_export_row.dart --input $outputFile --dry-run',
        ],
        '_queryTarget': {
          'caseId': caseId,
          'queryWindowJst': queryWindow,
          'targetOriginTimeJst': request['targetOriginTimeJst'],
          'targetLatitude': request['targetLatitude'],
          'targetLongitude': request['targetLongitude'],
          'targetDepthKm': request['targetDepthKm'],
          'targetMagnitude': request['targetMagnitude'],
          'targetRegion': request['targetRegion'],
          'notes': request['notes'],
        },
        'caseId': caseId,
        'sourceType': preferredSourceType,
        'sourceUrl': sourceUrl,
        'sourceVersionOrPageDate': '<fill-authenticated-page-date-or-version>',
        'checkedAtUtc': '<fill-checked-at-utc>',
        'reviewer': '<fill-reviewer-id>',
        'originTimeJst': '<fill-catalog-origin-time-jst>',
        'latitude': null,
        'longitude': null,
        'depthKm': null,
        'magnitude': null,
        'region': '<fill-catalog-region>',
        'rawRowText': '<fill-verbatim-event-row-text>',
      },
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'outputFile': outputFile,
    'preferredSourceType': preferredSourceType,
    'queryWindowJst': queryWindowLabel,
    'manualReviewRequired': true,
    'automaticClearance': false,
    'templateFields': filePayload.keys
        .where((key) => !key.startsWith('_'))
        .toList(growable: false),
  };
}

Map<String, Object?> _readMap(
  File file, {
  required String expectedSchema,
  required String schemaError,
  required String missingError,
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
  return data;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
