import 'dart:convert';
import 'dart:io';

const _defaultRequestPath = 'docs/data/hinet_authenticated_export_request.json';
const _defaultRowsPath = 'docs/data/hinet_authenticated_export_rows.json';
const _defaultTemplateReportPath =
    '.dart_tool/hinet_authenticated_export_row_templates/report.json';
const _defaultOutput =
    '.dart_tool/hinet_authenticated_export_review_packet/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_authenticated_export_review_packet.generated.md';

void main(List<String> args) {
  final requestPath = _argument(args, '--requests') ?? _defaultRequestPath;
  final rowsPath = _argument(args, '--rows') ?? _defaultRowsPath;
  final templateReportPath =
      _argument(args, '--templates') ?? _defaultTemplateReportPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ReviewPacketReport.build(
    requestFile: File(requestPath),
    rowsFile: File(rowsPath),
    templateReportFile: File(templateReportPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote Hi-net authenticated export review packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildHinetAuthenticatedExportReviewPacketJson({
  String requestPath = _defaultRequestPath,
  String rowsPath = _defaultRowsPath,
  String templateReportPath = _defaultTemplateReportPath,
}) {
  return _ReviewPacketReport.build(
    requestFile: File(requestPath),
    rowsFile: File(rowsPath),
    templateReportFile: File(templateReportPath),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ReviewPacketReport {
  final String requestPath;
  final String rowsPath;
  final String templateReportPath;
  final List<_ReviewPacket> packets;
  final List<String> errors;
  final List<String> warnings;

  const _ReviewPacketReport({
    required this.requestPath,
    required this.rowsPath,
    required this.templateReportPath,
    required this.packets,
    required this.errors,
    required this.warnings,
  });

  factory _ReviewPacketReport.build({
    required File requestFile,
    required File rowsFile,
    required File templateReportFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final requestData = _readMap(
      requestFile,
      expectedSchema: 'hinet_authenticated_export_request_v1',
      missingError: 'authenticated_export_request_missing',
      schemaError: 'unexpected_authenticated_export_request_schema',
      errors: errors,
    );
    final rowsData = _readMap(
      rowsFile,
      expectedSchema: 'hinet_authenticated_export_rows_v1',
      missingError: 'authenticated_export_rows_missing',
      schemaError: 'unexpected_authenticated_export_rows_schema',
      errors: errors,
    );
    final templateReport = _readMap(
      templateReportFile,
      expectedSchema: 'hinet_authenticated_export_row_templates_v1',
      missingError: 'authenticated_export_row_template_report_missing',
      schemaError: 'unexpected_authenticated_export_row_template_schema',
      errors: errors,
      requirePassStatus: true,
    );

    final sourceUrlByType = <String, String>{
      for (final raw in _list(requestData['sourcePaths']))
        _map(raw)['sourceType'].toString(): _map(raw)['sourceUrl'].toString(),
    };
    final requestByCaseId = <String, Map<String, Object?>>{
      for (final raw in _list(requestData['requests']))
        _map(raw)['caseId'].toString(): _map(raw),
    };
    final templateByCaseId = <String, Map<String, Object?>>{
      for (final raw in _list(templateReport['templates']))
        _map(raw)['caseId'].toString(): _map(raw),
    };

    final packets = <_ReviewPacket>[];
    for (final rawRow in _list(rowsData['rows'])) {
      final row = _map(rawRow);
      if (row['status'] != 'pending_export') continue;
      final caseId = row['caseId']?.toString() ?? '';
      final request = requestByCaseId[caseId];
      if (request == null) {
        errors.add('authenticated_export_packet_missing_request:$caseId');
        continue;
      }
      final template = templateByCaseId[caseId];
      if (template == null) {
        errors.add('authenticated_export_packet_missing_template:$caseId');
        continue;
      }
      if (template['manualReviewRequired'] != true) {
        errors.add('authenticated_export_packet_template_not_manual:$caseId');
      }
      if (template['automaticClearance'] == true) {
        errors.add(
          'authenticated_export_packet_template_allows_clearance:$caseId',
        );
      }
      packets.add(
        _ReviewPacket.fromRequest(
          request: request,
          row: row,
          template: template,
          sourceUrlByType: sourceUrlByType,
        ),
      );
    }
    packets.sort((left, right) => left.caseId.compareTo(right.caseId));

    return _ReviewPacketReport(
      requestPath: requestFile.path,
      rowsPath: rowsFile.path,
      templateReportPath: templateReportFile.path,
      packets: packets,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'hinet_authenticated_export_review_packet_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'requestPath': requestPath,
    'rowsPath': rowsPath,
    'templateReportPath': templateReportPath,
    'summary': {
      'packetCount': packets.length,
      'manualReviewRequiredCount': packets.length,
      'automaticClearanceCount': 0,
      'ledgerMutationCount': 0,
      'submittedForReviewCount': 0,
      'decisionEvidenceReadyCount': 0,
      'credentialFieldCount': 0,
    },
    'errors': errors,
    'warnings': warnings,
    'packets': packets.map((packet) => packet.toJson()).toList(),
  };

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Authenticated Export Review Packet')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Requests: `$requestPath`')
      ..writeln('- Rows: `$rowsPath`')
      ..writeln('- Row templates: `$templateReportPath`')
      ..writeln('- Packets: `${summary['packetCount']}`')
      ..writeln(
        '- Manual-review required: '
        '`${summary['manualReviewRequiredCount']}`',
      )
      ..writeln('- Automatic clearances: `0`')
      ..writeln('- Ledger mutations: `0`')
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
      ..writeln('## Packets')
      ..writeln();
    for (final packet in packets) {
      buffer
        ..writeln('### `${packet.caseId}`')
        ..writeln()
        ..writeln('- Row status: `${packet.rowStatus}`')
        ..writeln('- Preferred source: `${packet.preferredSourceType}`')
        ..writeln('- Fallback source: `${packet.fallbackSourceType}`')
        ..writeln('- Source URL: `${packet.preferredSourceUrl}`')
        ..writeln('- Query window JST: `${packet.queryWindowJst}`')
        ..writeln('- Target origin JST: `${packet.targetOriginTimeJst}`')
        ..writeln('- Target region: `${packet.targetRegion}`')
        ..writeln('- Template file: `${packet.templateFile}`')
        ..writeln('- Import dry-run:')
        ..writeln()
        ..writeln('```powershell')
        ..writeln(packet.importDryRunCommand)
        ..writeln('```')
        ..writeln()
        ..writeln(
          '- Decision: fill only from an authenticated event-level Hi-net/JMA '
          'row. This packet does not submit, approve or clear evidence.',
        )
        ..writeln();
    }
    return buffer.toString();
  }
}

class _ReviewPacket {
  final String caseId;
  final String rowStatus;
  final String preferredSourceType;
  final String fallbackSourceType;
  final String preferredSourceUrl;
  final String fallbackSourceUrl;
  final String queryWindowJst;
  final String targetOriginTimeJst;
  final double? targetLatitude;
  final double? targetLongitude;
  final double? targetDepthKm;
  final double? targetMagnitude;
  final String targetRegion;
  final String notes;
  final String templateFile;
  final List<String> templateFields;
  final String importDryRunCommand;

  const _ReviewPacket({
    required this.caseId,
    required this.rowStatus,
    required this.preferredSourceType,
    required this.fallbackSourceType,
    required this.preferredSourceUrl,
    required this.fallbackSourceUrl,
    required this.queryWindowJst,
    required this.targetOriginTimeJst,
    required this.targetLatitude,
    required this.targetLongitude,
    required this.targetDepthKm,
    required this.targetMagnitude,
    required this.targetRegion,
    required this.notes,
    required this.templateFile,
    required this.templateFields,
    required this.importDryRunCommand,
  });

  factory _ReviewPacket.fromRequest({
    required Map<String, Object?> request,
    required Map<String, Object?> row,
    required Map<String, Object?> template,
    required Map<String, String> sourceUrlByType,
  }) {
    final caseId = request['caseId']?.toString() ?? '';
    final preferredSourceType =
        request['preferredSourceType']?.toString() ??
        'hinet_jma_unified_catalog';
    final fallbackSourceType =
        request['fallbackSourceType']?.toString() ??
        'hinet_preliminary_catalog';
    final queryWindow = _map(request['queryWindowJst']);
    final queryWindowJst =
        '${queryWindow['start']?.toString() ?? ''}..'
        '${queryWindow['end']?.toString() ?? ''}';
    final templateFile = template['outputFile']?.toString() ?? '';

    return _ReviewPacket(
      caseId: caseId,
      rowStatus: row['status']?.toString() ?? '',
      preferredSourceType: preferredSourceType,
      fallbackSourceType: fallbackSourceType,
      preferredSourceUrl: sourceUrlByType[preferredSourceType] ?? '',
      fallbackSourceUrl: sourceUrlByType[fallbackSourceType] ?? '',
      queryWindowJst: queryWindowJst,
      targetOriginTimeJst: request['targetOriginTimeJst']?.toString() ?? '',
      targetLatitude: _asDouble(request['targetLatitude']),
      targetLongitude: _asDouble(request['targetLongitude']),
      targetDepthKm: _asDouble(request['targetDepthKm']),
      targetMagnitude: _asDouble(request['targetMagnitude']),
      targetRegion: request['targetRegion']?.toString() ?? '',
      notes: request['notes']?.toString() ?? '',
      templateFile: templateFile,
      templateFields: _stringList(template['templateFields']),
      importDryRunCommand:
          'dart run tools\\import_hinet_authenticated_export_row.dart '
          '--input $templateFile --dry-run',
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'rowStatus': rowStatus,
    'preferredSourceType': preferredSourceType,
    'fallbackSourceType': fallbackSourceType,
    'preferredSourceUrl': preferredSourceUrl,
    'fallbackSourceUrl': fallbackSourceUrl,
    'queryWindowJst': queryWindowJst,
    'targetOriginTimeJst': targetOriginTimeJst,
    'targetLatitude': targetLatitude,
    'targetLongitude': targetLongitude,
    'targetDepthKm': targetDepthKm,
    'targetMagnitude': targetMagnitude,
    'targetRegion': targetRegion,
    'notes': notes,
    'templateFile': templateFile,
    'templateFields': templateFields,
    'importDryRunCommand': importDryRunCommand,
    'requiredReviewFields': [
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
    ],
    'manualReviewRequired': true,
    'automaticClearance': false,
    'ledgerMutation': false,
    'blockerClearedByPacket': false,
  };
}

Map<String, Object?> _readMap(
  File file, {
  required String expectedSchema,
  required String missingError,
  required String schemaError,
  required List<String> errors,
  bool requirePassStatus = false,
}) {
  if (!file.existsSync()) {
    errors.add('$missingError:${file.path}');
    return <String, Object?>{};
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  if (data['schemaVersion'] != expectedSchema) {
    errors.add(schemaError);
  }
  if (requirePassStatus && data['status'] != 'pass') {
    errors.add('${schemaError}_not_pass');
  }
  return data;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((item) => item.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
