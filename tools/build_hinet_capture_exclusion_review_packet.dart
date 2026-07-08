import 'dart:convert';
import 'dart:io';

const _defaultReviewPath =
    '.dart_tool/hinet_capture_provenance_review/report.json';
const _defaultTemplateReportPath =
    '.dart_tool/hinet_capture_exclusion_templates/report.json';
const _defaultOutput =
    '.dart_tool/hinet_capture_exclusion_review_packet/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_capture_exclusion_review_packet.generated.md';

void main(List<String> args) {
  final reviewPath = _argument(args, '--review') ?? _defaultReviewPath;
  final templateReportPath =
      _argument(args, '--templates') ?? _defaultTemplateReportPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ReviewPacketReport.build(
    reviewFile: File(reviewPath),
    templateReportFile: File(templateReportPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote Hi-net capture exclusion review packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildHinetCaptureExclusionReviewPacketJson({
  String reviewPath = _defaultReviewPath,
  String templateReportPath = _defaultTemplateReportPath,
}) {
  return _ReviewPacketReport.build(
    reviewFile: File(reviewPath),
    templateReportFile: File(templateReportPath),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ReviewPacketReport {
  final String reviewPath;
  final String templateReportPath;
  final List<_ReviewPacket> packets;
  final List<String> errors;
  final List<String> warnings;

  const _ReviewPacketReport({
    required this.reviewPath,
    required this.templateReportPath,
    required this.packets,
    required this.errors,
    required this.warnings,
  });

  factory _ReviewPacketReport.build({
    required File reviewFile,
    required File templateReportFile,
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
    final templateReport = _readMap(
      templateReportFile,
      expectedSchema: 'hinet_capture_exclusion_templates_v1',
      missingError: 'capture_exclusion_template_report_missing',
      schemaError: 'unexpected_capture_exclusion_template_schema',
      errors: errors,
    );
    final templatesByCaseId = <String, Map<String, Object?>>{
      for (final rawTemplate in _list(templateReport['templates']))
        _map(rawTemplate)['caseId'].toString(): _map(rawTemplate),
    };

    final packets = <_ReviewPacket>[];
    for (final rawCase in _list(review['cases'])) {
      final item = _map(rawCase);
      if (item['readyAfterExclusion'] == true) continue;
      if (item['decisionStatus'] != 'pending_capture_repair_or_exclusion') {
        continue;
      }
      final caseId = item['caseId']?.toString() ?? '';
      final template = templatesByCaseId[caseId];
      if (template == null) {
        errors.add('capture_exclusion_review_packet_missing_template:$caseId');
        continue;
      }
      packets.add(_ReviewPacket.fromCase(item, template));
    }
    packets.sort((left, right) => left.caseId.compareTo(right.caseId));
    return _ReviewPacketReport(
      reviewPath: reviewFile.path,
      templateReportPath: templateReportFile.path,
      packets: packets,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'hinet_capture_exclusion_review_packet_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'reviewPath': reviewPath,
    'templateReportPath': templateReportPath,
    'summary': {
      'packetCount': packets.length,
      'manualReviewRequiredCount': packets.length,
      'automaticClearanceCount': 0,
      'ledgerMutationCount': 0,
      'readyAfterExclusionCount': 0,
      'missingGifArchiveCopyCount': packets
          .where((packet) => packet.affectedFiles.isNotEmpty)
          .length,
    },
    'errors': errors,
    'warnings': warnings,
    'packets': packets.map((packet) => packet.toJson()).toList(),
  };

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Capture Exclusion Review Packet')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Capture review: `$reviewPath`')
      ..writeln('- Exclusion templates: `$templateReportPath`')
      ..writeln('- Packets: `${summary['packetCount']}`')
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
      ..writeln('## Packets')
      ..writeln();
    for (final packet in packets) {
      buffer
        ..writeln('### `${packet.caseId}`')
        ..writeln()
        ..writeln('- Decision status: `${packet.decisionStatus}`')
        ..writeln('- Capture directory: `${packet.captureDirectory}`')
        ..writeln('- Expected GIFs: `${packet.captureExpectedGifCount}`')
        ..writeln('- Downloaded GIFs: `${packet.captureDownloadedGifCount}`')
        ..writeln('- Failed GIFs: `${packet.captureFailedGifCount}`')
        ..writeln('- Missing frames: `${packet.captureMissingFrameCount}`')
        ..writeln('- Affected files: `${packet.affectedFiles.join('`, `')}`')
        ..writeln(
          '- Suggested excluded files: '
          '`${packet.suggestedExcludedFiles.join('`, `')}`',
        )
        ..writeln('- Template file: `${packet.templateFile}`')
        ..writeln('- Import dry-run:')
        ..writeln()
        ..writeln('```powershell')
        ..writeln(packet.importDryRunCommand)
        ..writeln('```')
        ..writeln()
        ..writeln(
          '- Decision: repair the missing GIF first, or approve exclusion only '
          'after explicit reviewer sign-off.',
        )
        ..writeln();
    }
    return buffer.toString();
  }
}

class _ReviewPacket {
  final String caseId;
  final String decisionStatus;
  final String captureDirectory;
  final int captureExpectedGifCount;
  final int captureDownloadedGifCount;
  final int captureFailedGifCount;
  final int captureMissingFrameCount;
  final List<String> affectedFiles;
  final List<String> suggestedExcludedFiles;
  final List<Map<String, Object?>> blockingEvidence;
  final String templateFile;
  final String importDryRunCommand;

  const _ReviewPacket({
    required this.caseId,
    required this.decisionStatus,
    required this.captureDirectory,
    required this.captureExpectedGifCount,
    required this.captureDownloadedGifCount,
    required this.captureFailedGifCount,
    required this.captureMissingFrameCount,
    required this.affectedFiles,
    required this.suggestedExcludedFiles,
    required this.blockingEvidence,
    required this.templateFile,
    required this.importDryRunCommand,
  });

  factory _ReviewPacket.fromCase(
    Map<String, Object?> reviewCase,
    Map<String, Object?> template,
  ) {
    final caseId = reviewCase['caseId']?.toString() ?? '';
    final templateFile = template['outputFile']?.toString() ?? '';
    return _ReviewPacket(
      caseId: caseId,
      decisionStatus:
          reviewCase['decisionStatus']?.toString() ?? 'missing_decision',
      captureDirectory: reviewCase['captureDirectory']?.toString() ?? '',
      captureExpectedGifCount:
          _asInt(reviewCase['captureExpectedGifCount']) ?? 0,
      captureDownloadedGifCount:
          _asInt(reviewCase['captureDownloadedGifCount']) ?? 0,
      captureFailedGifCount: _asInt(reviewCase['captureFailedGifCount']) ?? 0,
      captureMissingFrameCount:
          _asInt(reviewCase['captureMissingFrameCount']) ?? 0,
      affectedFiles: _stringList(template['affectedFiles']),
      suggestedExcludedFiles: _stringList(template['suggestedExcludedFiles']),
      blockingEvidence: _list(
        reviewCase['blockingEvidence'],
      ).map((entry) => _map(entry)).toList(growable: false),
      templateFile: templateFile,
      importDryRunCommand:
          'dart run tools\\import_hinet_capture_exclusion_decision.dart '
          '--input $templateFile --dry-run',
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'decisionStatus': decisionStatus,
    'captureDirectory': captureDirectory,
    'captureExpectedGifCount': captureExpectedGifCount,
    'captureDownloadedGifCount': captureDownloadedGifCount,
    'captureFailedGifCount': captureFailedGifCount,
    'captureMissingFrameCount': captureMissingFrameCount,
    'affectedFiles': affectedFiles,
    'suggestedExcludedFiles': suggestedExcludedFiles,
    'blockingEvidence': blockingEvidence,
    'templateFile': templateFile,
    'importDryRunCommand': importDryRunCommand,
    'requiredReviewFields': ['reviewedAtUtc', 'reviewer', 'exclusionReason'],
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

List<String> _stringList(Object? value) =>
    _list(value).map((item) => item.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
