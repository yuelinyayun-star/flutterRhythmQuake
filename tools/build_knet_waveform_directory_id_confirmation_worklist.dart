import 'dart:convert';
import 'dart:io';

const _defaultReadinessReport =
    '.dart_tool/knet_gif_waveform_alignment_readiness/report.json';
const _defaultOutput =
    '.dart_tool/knet_waveform_directory_id_confirmation_worklist/report.json';
const _defaultMarkdown =
    'docs/baselines/knet_waveform_directory_id_confirmation_worklist.generated.md';

void main(List<String> args) {
  final readinessReportPath =
      _argument(args, '--readiness-report') ?? _defaultReadinessReport;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ConfirmationWorklist.build(
    readinessReportFile: File(readinessReportPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote K-NET/GIF directory-id confirmation worklist');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ConfirmationWorklist {
  final String readinessReportPath;
  final List<_WorklistItem> items;
  final List<String> errors;
  final List<String> warnings;

  const _ConfirmationWorklist({
    required this.readinessReportPath,
    required this.items,
    required this.errors,
    required this.warnings,
  });

  factory _ConfirmationWorklist.build({required File readinessReportFile}) {
    final errors = <String>[];
    final warnings = <String>[];
    final items = <_WorklistItem>[];

    if (!readinessReportFile.existsSync()) {
      errors.add(
        'knet_gif_waveform_alignment_readiness_report_missing:${readinessReportFile.path}',
      );
    } else {
      final report =
          jsonDecode(readinessReportFile.readAsStringSync())
              as Map<String, Object?>;
      final captureCases =
          (report['captureCases'] as List<Object?>? ?? const [])
              .cast<Map<String, Object?>>();
      for (final rawCase in captureCases) {
        final caseItem = _WorklistItem.fromCaptureCase(rawCase);
        if (caseItem != null) {
          items.add(caseItem);
        }
      }
    }

    items.sort((left, right) {
      final readinessCompare = left.readiness.compareTo(right.readiness);
      if (readinessCompare != 0) return readinessCompare;
      final distanceCompare = left.matchDistanceKm.compareTo(
        right.matchDistanceKm,
      );
      if (distanceCompare != 0) return distanceCompare;
      final timeCompare = left.originTimeJst.compareTo(right.originTimeJst);
      if (timeCompare != 0) return timeCompare;
      return left.caseId.compareTo(right.caseId);
    });

    return _ConfirmationWorklist(
      readinessReportPath: readinessReportFile.path,
      items: items,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 'knet_waveform_directory_id_confirmation_worklist_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'readinessReportPath': readinessReportPath,
      'summary': {
        'itemCount': items.length,
        'directoryIdUnconfirmedCount': items
            .where(
              (item) => item.readiness == 'candidate_directory_id_unconfirmed',
            )
            .length,
        'captureOnlyCount': 0,
      },
      'errors': errors,
      'warnings': warnings,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# K-NET GIF/Waveform Directory ID Confirmation Worklist')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Readiness report: `$readinessReportPath`')
      ..writeln('- Items: `${summary['itemCount']}`')
      ..writeln(
        '- Directory id unconfirmed: '
        '`${summary['directoryIdUnconfirmedCount']}`',
      )
      ..writeln('- Capture-only: `0`')
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
      ..writeln('## Items')
      ..writeln()
      ..writeln(
        '| Priority | Case | Origin JST | Region | Candidate event | Directory id | Distance km | Time delta s | Next action |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | ---: | ---: | --- |');
    for (final item in items) {
      buffer.writeln(
        '| `${item.priority}` | `${item.caseId}` | `${item.originTimeJst}` | '
        '`${item.region}` | `${item.matchedWaveformEventId}` | '
        '`${item.matchedNiedDirectoryId}` | ${item.matchDistanceKm.toStringAsFixed(1)} | '
        '${item.matchTimeDeltaSeconds} | `${item.nextAction}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- This worklist is diagnostic-only and does not change source estimation or frozen metrics.',
      )
      ..writeln(
        '- The `candidate_directory_id_unconfirmed` rows are the immediate confirmation targets; `capture_only_needs_waveform_candidate` rows remain queued for later seeding.',
      );
    return buffer.toString();
  }
}

class _WorklistItem {
  final String caseId;
  final String originTimeJst;
  final String region;
  final String matchedWaveformEventId;
  final String matchedNiedDirectoryId;
  final int matchTimeDeltaSeconds;
  final double matchDistanceKm;
  final String readiness;
  final String nextAction;

  const _WorklistItem({
    required this.caseId,
    required this.originTimeJst,
    required this.region,
    required this.matchedWaveformEventId,
    required this.matchedNiedDirectoryId,
    required this.matchTimeDeltaSeconds,
    required this.matchDistanceKm,
    required this.readiness,
    required this.nextAction,
  });

  int get priority => readiness == 'candidate_directory_id_unconfirmed' ? 0 : 1;

  static _WorklistItem? fromCaptureCase(Map<String, Object?> captureCase) {
    final readiness = captureCase['readiness']?.toString();
    if (readiness == null) return null;
    if (readiness != 'candidate_directory_id_unconfirmed') {
      return null;
    }
    final caseId = captureCase['caseId']?.toString() ?? '';
    final originTimeJst = captureCase['originTimeJst']?.toString() ?? '';
    final region = captureCase['region']?.toString() ?? '';
    final matchedWaveformEventId =
        captureCase['matchedWaveformEventId']?.toString() ?? '';
    final matchedNiedDirectoryId =
        captureCase['matchedNiedDirectoryId']?.toString() ?? '';
    final matchTimeDeltaSeconds =
        _int(captureCase['matchTimeDeltaSeconds']) ?? 0;
    final matchDistanceKm = _double(captureCase['matchDistanceKm']) ?? 0.0;
    final nextAction = captureCase['nextAction']?.toString() ?? '';
    if (caseId.isEmpty || originTimeJst.isEmpty) return null;
    return _WorklistItem(
      caseId: caseId,
      originTimeJst: originTimeJst,
      region: region,
      matchedWaveformEventId: matchedWaveformEventId,
      matchedNiedDirectoryId: matchedNiedDirectoryId,
      matchTimeDeltaSeconds: matchTimeDeltaSeconds,
      matchDistanceKm: matchDistanceKm,
      readiness: readiness,
      nextAction: nextAction,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'priority': priority,
      'caseId': caseId,
      'originTimeJst': originTimeJst,
      'region': region,
      'matchedWaveformEventId': matchedWaveformEventId,
      'matchedNiedDirectoryId': matchedNiedDirectoryId,
      'matchTimeDeltaSeconds': matchTimeDeltaSeconds,
      'matchDistanceKm': matchDistanceKm,
      'readiness': readiness,
      'nextAction': nextAction,
    };
  }
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
