import 'dart:convert';
import 'dart:io';

const _defaultAvailabilityReportPath =
    '.dart_tool/jma_catalog_availability_report/report.json';
const _defaultOutput = '.dart_tool/jma_final_catalog_review_packet/report.json';
const _defaultMarkdown =
    'docs/baselines/jma_final_catalog_review_packet.generated.md';

void main(List<String> args) {
  final availabilityReportPath =
      _argument(args, '--availability-report') ??
      _defaultAvailabilityReportPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ReviewPacketReport.build(
    availabilityReportFile: File(availabilityReportPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote JMA final catalog review packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildJmaFinalCatalogReviewPacketJson({
  String availabilityReportPath = _defaultAvailabilityReportPath,
}) {
  return _ReviewPacketReport.build(
    availabilityReportFile: File(availabilityReportPath),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ReviewPacketReport {
  final String availabilityReportPath;
  final _AvailabilitySnapshot? availability;
  final List<_ReviewPacket> packets;
  final List<String> errors;
  final List<String> warnings;

  const _ReviewPacketReport({
    required this.availabilityReportPath,
    required this.availability,
    required this.packets,
    required this.errors,
    required this.warnings,
  });

  factory _ReviewPacketReport.build({required File availabilityReportFile}) {
    final errors = <String>[];
    final warnings = <String>[];
    final report = _readMap(
      availabilityReportFile,
      expectedSchema: 'jma_catalog_availability_report_v1',
      missingError: 'jma_catalog_availability_report_missing',
      schemaError: 'unexpected_jma_catalog_availability_report_schema',
      errors: errors,
      requirePassStatus: true,
    );
    final availabilityJson = _map(report['availability']);
    final availability = availabilityJson.isEmpty
        ? null
        : _AvailabilitySnapshot.fromJson(availabilityJson);
    if (availability == null) {
      errors.add('jma_final_catalog_packet_availability_missing');
    }

    final packets = <_ReviewPacket>[];
    for (final rawBlocker in _list(report['blockers'])) {
      final blocker = _map(rawBlocker);
      if (blocker['linkedToVersionedCatalog'] == true) continue;
      packets.add(
        _ReviewPacket.fromBlocker(
          blocker,
          latestAvailableFinalCatalogYear:
              availability?.latestAvailableFinalCatalogYear,
        ),
      );
    }
    packets.sort((left, right) => left.caseId.compareTo(right.caseId));

    return _ReviewPacketReport(
      availabilityReportPath: availabilityReportFile.path,
      availability: availability,
      packets: packets,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'jma_final_catalog_review_packet_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'availabilityReportPath': availabilityReportPath,
    'availability': availability?.toJson(),
    'summary': {
      'packetCount': packets.length,
      'manualReviewRequiredCount': packets.length,
      'automaticClearanceCount': 0,
      'fixtureMutationCount': 0,
      'catalogTruthWriteCount': 0,
      'writeLinkAllowedCount': packets
          .where((packet) => packet.writeLinkAllowed)
          .length,
      'externalCatalogNotYetAvailableCount': packets
          .where(
            (packet) => packet.status == 'external_catalog_not_yet_available',
          )
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
      ..writeln('# JMA Final Catalog Review Packet')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Availability report: `$availabilityReportPath`')
      ..writeln(
        '- Latest available final catalog year: '
        '`${availability?.latestAvailableFinalCatalogYear ?? '--'}`',
      )
      ..writeln('- Packets: `${summary['packetCount']}`')
      ..writeln(
        '- Manual-review required: '
        '`${summary['manualReviewRequiredCount']}`',
      )
      ..writeln('- Automatic clearances: `0`')
      ..writeln('- Fixture mutations: `0`')
      ..writeln('- Catalog truth writes: `0`')
      ..writeln('- Write-link allowed: `${summary['writeLinkAllowedCount']}`')
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
        ..writeln('- Status: `${packet.status}`')
        ..writeln('- Origin JST: `${packet.originTimeJst}`')
        ..writeln('- Event year: `${packet.eventYear}`')
        ..writeln('- Fixture: `${packet.fixturePath}`')
        ..writeln('- Evidence: `${packet.evidence}`')
        ..writeln('- Dry-run link command:')
        ..writeln()
        ..writeln('```powershell')
        ..writeln(packet.dryRunLinkCommand)
        ..writeln('```')
        ..writeln()
        ..writeln('- Write-link allowed: `${packet.writeLinkAllowed}`')
        ..writeln(
          '- Decision: import only a versioned official JMA final catalog. '
          'Do not run `--write` until this packet allows it.',
        )
        ..writeln();
    }
    return buffer.toString();
  }
}

class _AvailabilitySnapshot {
  final String asOf;
  final String authority;
  final int latestAvailableFinalCatalogYear;
  final String latestAvailableFinalCatalogPeriodEnd;
  final Map<String, Object?> evidence;
  final List<String> sourceUrls;

  const _AvailabilitySnapshot({
    required this.asOf,
    required this.authority,
    required this.latestAvailableFinalCatalogYear,
    required this.latestAvailableFinalCatalogPeriodEnd,
    required this.evidence,
    required this.sourceUrls,
  });

  factory _AvailabilitySnapshot.fromJson(Map<String, Object?> json) =>
      _AvailabilitySnapshot(
        asOf: json['asOf']?.toString() ?? '',
        authority: json['authority']?.toString() ?? '',
        latestAvailableFinalCatalogYear:
            _asInt(json['latestAvailableFinalCatalogYear']) ?? 0,
        latestAvailableFinalCatalogPeriodEnd:
            json['latestAvailableFinalCatalogPeriodEnd']?.toString() ?? '',
        evidence: _map(json['latestAvailableFinalCatalogEvidence']),
        sourceUrls: _stringList(json['sourceUrls']),
      );

  Map<String, Object?> toJson() => {
    'asOf': asOf,
    'authority': authority,
    'latestAvailableFinalCatalogYear': latestAvailableFinalCatalogYear,
    'latestAvailableFinalCatalogPeriodEnd':
        latestAvailableFinalCatalogPeriodEnd,
    'latestAvailableFinalCatalogEvidence': evidence,
    'sourceUrls': sourceUrls,
  };
}

class _ReviewPacket {
  final String caseId;
  final String fixturePath;
  final String truthSource;
  final String? originTimeJst;
  final int? eventYear;
  final bool catalogTruthVerified;
  final bool linkedToVersionedCatalog;
  final bool coveredByAvailableCatalog;
  final String status;
  final String evidence;
  final int? latestAvailableFinalCatalogYear;
  final bool writeLinkAllowed;
  final String importCommand;
  final String dryRunLinkCommand;
  final String writeLinkCommand;

  const _ReviewPacket({
    required this.caseId,
    required this.fixturePath,
    required this.truthSource,
    required this.originTimeJst,
    required this.eventYear,
    required this.catalogTruthVerified,
    required this.linkedToVersionedCatalog,
    required this.coveredByAvailableCatalog,
    required this.status,
    required this.evidence,
    required this.latestAvailableFinalCatalogYear,
    required this.writeLinkAllowed,
    required this.importCommand,
    required this.dryRunLinkCommand,
    required this.writeLinkCommand,
  });

  factory _ReviewPacket.fromBlocker(
    Map<String, Object?> blocker, {
    required int? latestAvailableFinalCatalogYear,
  }) {
    final caseId = blocker['caseId']?.toString() ?? '';
    final fixturePath = blocker['fixturePath']?.toString() ?? '';
    final eventYear = _asInt(blocker['eventYear']);
    final coveredByAvailableCatalog =
        blocker['coveredByAvailableCatalog'] == true;
    final writeLinkAllowed =
        coveredByAvailableCatalog &&
        blocker['status'] == 'catalog_available_link_missing';
    final catalogPath = 'docs/data/jma_catalogs/<catalog>.json';

    return _ReviewPacket(
      caseId: caseId,
      fixturePath: fixturePath,
      truthSource: blocker['truthSource']?.toString() ?? '',
      originTimeJst: blocker['originTimeJst']?.toString(),
      eventYear: eventYear,
      catalogTruthVerified: blocker['catalogTruthVerified'] == true,
      linkedToVersionedCatalog: blocker['linkedToVersionedCatalog'] == true,
      coveredByAvailableCatalog: coveredByAvailableCatalog,
      status: blocker['status']?.toString() ?? '',
      evidence: blocker['evidence']?.toString() ?? '',
      latestAvailableFinalCatalogYear: latestAvailableFinalCatalogYear,
      writeLinkAllowed: writeLinkAllowed,
      importCommand:
          'dart run tools\\import_jma_hypocenter.dart '
          '--input <official-hypocenter-file> '
          '--output $catalogPath '
          '--catalog-id jma_final_$eventYear '
          '--revision <revision> '
          '--source-url <official-url>',
      dryRunLinkCommand:
          'dart run tools\\link_jma_catalog.dart '
          '--catalog $catalogPath --case $fixturePath',
      writeLinkCommand:
          'dart run tools\\link_jma_catalog.dart '
          '--catalog $catalogPath --case $fixturePath --write',
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'fixturePath': fixturePath,
    'truthSource': truthSource,
    'originTimeJst': originTimeJst,
    'eventYear': eventYear,
    'catalogTruthVerified': catalogTruthVerified,
    'linkedToVersionedCatalog': linkedToVersionedCatalog,
    'coveredByAvailableCatalog': coveredByAvailableCatalog,
    'status': status,
    'evidence': evidence,
    'latestAvailableFinalCatalogYear': latestAvailableFinalCatalogYear,
    'importCommand': importCommand,
    'dryRunLinkCommand': dryRunLinkCommand,
    'writeLinkCommand': writeLinkCommand,
    'writeLinkAllowed': writeLinkAllowed,
    'reviewFields': [
      'officialHypocenterFile',
      'catalogId',
      'revision',
      'sourceUrl',
      'reviewer',
      'checkedAtUtc',
    ],
    'manualReviewRequired': true,
    'automaticClearance': false,
    'fixtureMutation': false,
    'catalogTruthWrite': false,
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
