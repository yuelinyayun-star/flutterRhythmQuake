import 'dart:convert';
import 'dart:io';

const _defaultManifestPath = 'docs/data/jma_reference_event_candidates.json';
const _defaultAssociationReportPath =
    '.dart_tool/jma_reference_capture_association/report.json';
const _defaultOutput =
    '.dart_tool/jma_reference_capture_review_packet/report.json';
const _defaultMarkdown =
    'docs/baselines/jma_reference_capture_review_packet.generated.md';

void main(List<String> args) {
  final manifestPath = _argument(args, '--manifest') ?? _defaultManifestPath;
  final associationPath =
      _argument(args, '--association') ?? _defaultAssociationReportPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ReviewPacketReport.build(
    manifestFile: File(manifestPath),
    associationReportFile: File(associationPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote JMA reference capture review packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildJmaReferenceCaptureReviewPacketJson({
  String manifestPath = _defaultManifestPath,
  String associationReportPath = _defaultAssociationReportPath,
}) {
  return _ReviewPacketReport.build(
    manifestFile: File(manifestPath),
    associationReportFile: File(associationReportPath),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ReviewPacketReport {
  final String manifestPath;
  final String associationReportPath;
  final List<_ReviewPacket> packets;
  final List<String> errors;
  final List<String> warnings;

  const _ReviewPacketReport({
    required this.manifestPath,
    required this.associationReportPath,
    required this.packets,
    required this.errors,
    required this.warnings,
  });

  factory _ReviewPacketReport.build({
    required File manifestFile,
    required File associationReportFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final manifest = _readMap(
      manifestFile,
      expectedDatasetId: 'jma_reference_event_candidates_v1',
      missingError: 'jma_reference_candidate_manifest_missing',
      schemaError: 'unexpected_jma_reference_candidate_dataset_id',
      errors: errors,
    );
    final association = _readMap(
      associationReportFile,
      expectedSchema: 'jma_reference_capture_association_v1',
      missingError: 'jma_reference_capture_association_missing',
      schemaError: 'unexpected_jma_reference_capture_association_schema',
      errors: errors,
      requirePassStatus: true,
    );

    final eventById = <String, Map<String, Object?>>{
      for (final rawEvent in _list(manifest['events']))
        _map(rawEvent)['eventId'].toString(): _map(rawEvent),
    };
    final packets = <_ReviewPacket>[];
    for (final rawCase in _list(association['cases'])) {
      final associationCase = _map(rawCase);
      final eventId = associationCase['eventId']?.toString() ?? '';
      final event = eventById[eventId];
      if (event == null) {
        errors.add('jma_reference_capture_packet_missing_event:$eventId');
        continue;
      }
      if (associationCase['status'] != 'pending_capture_association') {
        continue;
      }
      if (associationCase['captureDirectory'] != null) {
        continue;
      }
      packets.add(_ReviewPacket.fromParts(event, associationCase));
    }
    packets.sort((left, right) => left.eventId.compareTo(right.eventId));

    return _ReviewPacketReport(
      manifestPath: manifestFile.path,
      associationReportPath: associationReportFile.path,
      packets: packets,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'jma_reference_capture_review_packet_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'manifestPath': manifestPath,
    'associationReportPath': associationReportPath,
    'summary': {
      'packetCount': packets.length,
      'manualReviewRequiredCount': packets.length,
      'automaticClearanceCount': 0,
      'manifestMutationCount': 0,
      'captureAssociationClearedByPacketCount': 0,
      'finalCatalogTruthCount': 0,
      'localCandidateMatchCount': packets.fold<int>(
        0,
        (total, packet) =>
            total +
            packet.localCaptureCandidates.length +
            packet.localFixtureCandidates.length,
      ),
    },
    'errors': errors,
    'warnings': warnings,
    'packets': packets.map((packet) => packet.toJson()).toList(),
  };

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# JMA Reference Capture Review Packet')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Manifest: `$manifestPath`')
      ..writeln('- Association report: `$associationReportPath`')
      ..writeln('- Packets: `${summary['packetCount']}`')
      ..writeln(
        '- Manual-review required: '
        '`${summary['manualReviewRequiredCount']}`',
      )
      ..writeln('- Automatic clearances: `0`')
      ..writeln('- Manifest mutations: `0`')
      ..writeln('- Final catalog truth labels: `0`')
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
        ..writeln('### `${packet.eventId}`')
        ..writeln()
        ..writeln('- Status: `${packet.status}`')
        ..writeln('- Origin JST: `${packet.originTimeJst}`')
        ..writeln('- Region: `${packet.region}`')
        ..writeln(
          '- Latitude/longitude: `${packet.latitude}, ${packet.longitude}`',
        )
        ..writeln('- Depth/M: `${packet.depthKm} km / M${packet.magnitude}`')
        ..writeln('- Max shindo: `${packet.maxShindo}`')
        ..writeln(
          '- Existing local captures: `${packet.localCaptureCandidates.join('`, `')}`',
        )
        ..writeln(
          '- Existing local fixtures: `${packet.localFixtureCandidates.join('`, `')}`',
        )
        ..writeln('- Review target: `${packet.associationTargetPath}`')
        ..writeln('- Validation command:')
        ..writeln()
        ..writeln('```powershell')
        ..writeln(packet.validationCommand)
        ..writeln('```')
        ..writeln()
        ..writeln('- Import dry-run command:')
        ..writeln()
        ..writeln('```powershell')
        ..writeln(packet.dryRunCommand)
        ..writeln('```')
        ..writeln()
        ..writeln(
          '- Decision: associate only a real local replay/capture package. '
          'Keep this event reference-only until final-catalog linking clears.',
        )
        ..writeln();
    }
    return buffer.toString();
  }
}

class _ReviewPacket {
  final String eventId;
  final String status;
  final String originTimeJst;
  final String region;
  final String regionJapanese;
  final double? latitude;
  final double? longitude;
  final double? depthKm;
  final double? magnitude;
  final int? maxShindo;
  final String truthQuality;
  final List<String> eventLabels;
  final String notes;
  final List<String> localCaptureCandidates;
  final List<String> localFixtureCandidates;
  final String associationTargetPath;
  final String validationCommand;
  final String dryRunCommand;

  const _ReviewPacket({
    required this.eventId,
    required this.status,
    required this.originTimeJst,
    required this.region,
    required this.regionJapanese,
    required this.latitude,
    required this.longitude,
    required this.depthKm,
    required this.magnitude,
    required this.maxShindo,
    required this.truthQuality,
    required this.eventLabels,
    required this.notes,
    required this.localCaptureCandidates,
    required this.localFixtureCandidates,
    required this.associationTargetPath,
    required this.validationCommand,
    required this.dryRunCommand,
  });

  factory _ReviewPacket.fromParts(
    Map<String, Object?> event,
    Map<String, Object?> associationCase,
  ) {
    return _ReviewPacket(
      eventId: event['eventId']?.toString() ?? '',
      status: associationCase['status']?.toString() ?? '',
      originTimeJst: event['originTimeJst']?.toString() ?? '',
      region: event['region']?.toString() ?? '',
      regionJapanese: event['regionJapanese']?.toString() ?? '',
      latitude: _asDouble(event['latitude']),
      longitude: _asDouble(event['longitude']),
      depthKm: _asDouble(event['depthKm']),
      magnitude: _asDouble(event['magnitude']),
      maxShindo: _asInt(event['maxShindo']),
      truthQuality: event['truthQuality']?.toString() ?? '',
      eventLabels: _stringList(event['eventLabels']),
      notes: event['notes']?.toString() ?? '',
      localCaptureCandidates: _stringList(
        associationCase['localCaptureCandidates'],
      ),
      localFixtureCandidates: _stringList(
        associationCase['localFixtureCandidates'],
      ),
      associationTargetPath: 'docs/data/jma_reference_event_candidates.json',
      validationCommand:
          'powershell -NoProfile -ExecutionPolicy Bypass -File '
          'tools\\validate_jma_reference_capture_association.ps1',
      dryRunCommand:
          'dart run tools\\import_jma_reference_capture_package.dart '
          '--input <reviewed-capture-association.json> --dry-run',
    );
  }

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'status': status,
    'originTimeJst': originTimeJst,
    'region': region,
    'regionJapanese': regionJapanese,
    'latitude': latitude,
    'longitude': longitude,
    'depthKm': depthKm,
    'magnitude': magnitude,
    'maxShindo': maxShindo,
    'truthQuality': truthQuality,
    'eventLabels': eventLabels,
    'notes': notes,
    'localCaptureCandidates': localCaptureCandidates,
    'localFixtureCandidates': localFixtureCandidates,
    'associationTargetPath': associationTargetPath,
    'requiredLocalFiles': [
      'manifest.json or replay_manifest.json',
      'frame data / raw GIFs as recorded by the package manifest',
    ],
    'acceptedLocalRoots': [
      'tmp/captures',
      'test/fixtures/source_estimation',
      'replay',
    ],
    'reviewFields': [
      'reviewer',
      'reviewedAtUtc',
      'captureDirectory',
      'manifestPath',
      'packageSource',
      'associationReason',
    ],
    'validationCommand': validationCommand,
    'dryRunCommand': dryRunCommand,
    'manualReviewRequired': true,
    'automaticClearance': false,
    'manifestMutation': false,
    'captureAssociationClearedByPacket': false,
    'finalCatalogTruth': false,
  };
}

Map<String, Object?> _readMap(
  File file, {
  String? expectedSchema,
  String? expectedDatasetId,
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
  if (expectedSchema != null && data['schemaVersion'] != expectedSchema) {
    errors.add(schemaError);
  }
  if (expectedDatasetId != null && data['datasetId'] != expectedDatasetId) {
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
