import 'dart:convert';
import 'dart:io';

const _defaultMetricTriagePath =
    '.dart_tool/source_metric_readiness_triage/report.json';
const _defaultJmaReviewPacketPath =
    '.dart_tool/jma_final_catalog_review_packet/report.json';
const _defaultOutputPath =
    '.dart_tool/source_jma_catalog_link_triage_packet/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_jma_catalog_link_triage.generated.md';

const _expectedCaseIds = {
  '20260622_kushiro_offshore_m30_jma',
  '20260624_fukushima_aizu_m32_jma_eq5',
  '20260625_iwate_offshore_m32_jma',
};

void main(List<String> args) {
  final metricTriagePath =
      _argument(args, '--metric-triage') ?? _defaultMetricTriagePath;
  final jmaReviewPacketPath =
      _argument(args, '--jma-review-packet') ?? _defaultJmaReviewPacketPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceJmaCatalogLinkTriagePacketJson(
    metricTriagePath: metricTriagePath,
    jmaReviewPacketPath: jmaReviewPacketPath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source JMA catalog-link triage packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceJmaCatalogLinkTriagePacketJson({
  String metricTriagePath = _defaultMetricTriagePath,
  String jmaReviewPacketPath = _defaultJmaReviewPacketPath,
}) {
  final errors = <String>[];
  final metricTriage = _readJsonFile(
    metricTriagePath,
    errors,
    expectedSchema: 'source_metric_readiness_triage_v1',
    missingError: 'source_metric_readiness_triage_missing',
  );
  final jmaReviewPacket = _readJsonFile(
    jmaReviewPacketPath,
    errors,
    expectedSchema: 'jma_final_catalog_review_packet_v1',
    missingError: 'jma_final_catalog_review_packet_missing',
  );

  final metricCases = _list(
    metricTriage['cases'],
  ).map(_map).where(_isJmaCatalogLinkBlocked).toList(growable: false);
  final reviewPackets = {
    for (final packet in _list(jmaReviewPacket['packets']).map(_map))
      packet['caseId']?.toString() ?? '': packet,
  }..remove('');

  final packets =
      metricCases
          .map((metricCase) {
            final caseId = metricCase['caseId']?.toString() ?? '';
            final reviewPacket =
                reviewPackets[caseId] ?? const <String, Object?>{};
            return _packet(metricCase, reviewPacket);
          })
          .toList(growable: false)
        ..sort(
          (left, right) =>
              left['caseId'].toString().compareTo(right['caseId'].toString()),
        );

  final summary = _summary(packets, jmaReviewPacket);
  final validation = _validation(
    metricTriage: metricTriage,
    jmaReviewPacket: jmaReviewPacket,
    packets: packets,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_jma_catalog_link_triage_packet_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'sourceMetricReadinessTriage': metricTriagePath,
      'jmaFinalCatalogReviewPacket': jmaReviewPacketPath,
    },
    'policy': const {
      'diagnosticOnly': true,
      'fixtureMutationAllowed': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'promotesCatalogTruth': false,
      'notes':
          'This packet only focuses JMA catalog-link blockers for source-estimation diagnostic-ready cases.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'packets': packets,
  };
}

bool _isJmaCatalogLinkBlocked(Map<String, Object?> entry) {
  return entry['triageTier'] == 'diagnostic_ready_blocked' &&
      entry['nextAction'] == 'review_jma_catalog_link';
}

Map<String, Object?> _packet(
  Map<String, Object?> metricCase,
  Map<String, Object?> reviewPacket,
) {
  final caseId = metricCase['caseId']?.toString() ?? '';
  final reviewStatus = reviewPacket['status']?.toString() ?? 'missing';
  final writeLinkAllowed = reviewPacket['writeLinkAllowed'] == true;
  return {
    'caseId': caseId,
    'plannedUse': metricCase['plannedUse'],
    'triageTier': metricCase['triageTier'],
    'splitStatus': metricCase['splitStatus'],
    'captureStatus': metricCase['captureStatus'],
    'catalogOrReviewStatus': metricCase['catalogOrReviewStatus'],
    'truthSource': metricCase['truthSource'],
    'metricBlockingReason': metricCase['metricBlockingReason'],
    'fixturePath': reviewPacket['fixturePath'],
    'originTimeJst': reviewPacket['originTimeJst'],
    'eventYear': reviewPacket['eventYear'],
    'latestAvailableFinalCatalogYear':
        reviewPacket['latestAvailableFinalCatalogYear'],
    'catalogPacketStatus': reviewStatus,
    'catalogEvidence': reviewPacket['evidence'],
    'coveredByAvailableCatalog':
        reviewPacket['coveredByAvailableCatalog'] == true,
    'linkedToVersionedCatalog':
        reviewPacket['linkedToVersionedCatalog'] == true,
    'writeLinkAllowed': writeLinkAllowed,
    'manualReviewRequired': true,
    'splitAssignmentAllowed': false,
    'metricPromotionAllowed': false,
    'fixtureMutationAllowed': false,
    'dryRunLinkCommand': reviewPacket['dryRunLinkCommand'],
    'writeLinkCommand': reviewPacket['writeLinkCommand'],
    'decision': writeLinkAllowed
        ? 'manual_review_required_before_write_link'
        : 'external_catalog_not_yet_available_keep_diagnostic_only',
  };
}

Map<String, Object?> _summary(
  List<Map<String, Object?>> packets,
  Map<String, Object?> jmaReviewPacket,
) {
  final availability = _map(jmaReviewPacket['availability']);
  return {
    'packetCount': packets.length,
    'expectedPacketCount': _expectedCaseIds.length,
    'latestAvailableFinalCatalogYear':
        availability['latestAvailableFinalCatalogYear'],
    'targetEventYear': _singleValue(packets.map((entry) => entry['eventYear'])),
    'externalCatalogNotYetAvailableCount': packets
        .where(
          (entry) =>
              entry['catalogPacketStatus'] ==
              'external_catalog_not_yet_available',
        )
        .length,
    'manualReviewRequiredCount': packets
        .where((entry) => entry['manualReviewRequired'] == true)
        .length,
    'writeLinkAllowedCount': packets
        .where((entry) => entry['writeLinkAllowed'] == true)
        .length,
    'metricPromotionAllowedCount': packets
        .where((entry) => entry['metricPromotionAllowed'] == true)
        .length,
    'splitAssignmentAllowedCount': packets
        .where((entry) => entry['splitAssignmentAllowed'] == true)
        .length,
    'fixtureMutationAllowedCount': packets
        .where((entry) => entry['fixtureMutationAllowed'] == true)
        .length,
    'missingReviewPacketCount': packets
        .where((entry) => entry['catalogPacketStatus'] == 'missing')
        .length,
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> metricTriage,
  required Map<String, Object?> jmaReviewPacket,
  required List<Map<String, Object?>> packets,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (metricTriage['status'] != 'pass') {
    violations.add('source_metric_readiness_triage_not_pass');
  }
  if (jmaReviewPacket['status'] != 'pass') {
    violations.add('jma_final_catalog_review_packet_not_pass');
  }

  final actualCaseIds = packets
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (actualCaseIds.length != _expectedCaseIds.length ||
      !actualCaseIds.containsAll(_expectedCaseIds)) {
    violations.add('unexpected_jma_catalog_link_case_set');
  }
  if (_intValue(summary['packetCount']) != 3) {
    violations.add('unexpected_packet_count');
  }
  if (_intValue(summary['latestAvailableFinalCatalogYear']) != 2023) {
    violations.add('latest_available_final_catalog_year_changed');
  }
  if (_intValue(summary['targetEventYear']) != 2026) {
    violations.add('target_event_year_changed');
  }
  if (_intValue(summary['externalCatalogNotYetAvailableCount']) != 3) {
    violations.add('jma_external_catalog_availability_changed');
  }
  if (_intValue(summary['writeLinkAllowedCount']) != 0) {
    violations.add('write_link_allowed_without_review');
  }
  if (_intValue(summary['metricPromotionAllowedCount']) != 0) {
    violations.add('metric_promotion_allowed');
  }
  if (_intValue(summary['splitAssignmentAllowedCount']) != 0) {
    violations.add('split_assignment_allowed');
  }
  if (_intValue(summary['fixtureMutationAllowedCount']) != 0) {
    violations.add('fixture_mutation_allowed');
  }
  if (_intValue(summary['missingReviewPacketCount']) != 0) {
    violations.add('missing_jma_review_packet');
  }

  for (final packet in packets) {
    final caseId = packet['caseId'];
    if (packet['triageTier'] != 'diagnostic_ready_blocked') {
      violations.add('$caseId:not_diagnostic_ready_blocked');
    }
    if (packet['metricBlockingReason'] != 'review_jma_catalog_link') {
      violations.add('$caseId:not_jma_catalog_link_blocked');
    }
    if (packet['catalogPacketStatus'] != 'external_catalog_not_yet_available') {
      violations.add('$caseId:unexpected_catalog_packet_status');
    }
    if (packet['dryRunLinkCommand']?.toString().contains('--write') == true) {
      violations.add('$caseId:dry_run_command_contains_write');
    }
  }

  return {
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'violations': violations,
  };
}

String _markdown(Map<String, Object?> report) {
  final summary = _map(report['summary']);
  final validation = _map(report['validation']);
  final buffer = StringBuffer()
    ..writeln('# Source JMA Catalog-Link Triage Packet')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Packets: `${summary['packetCount']}`')
    ..writeln(
      '- Latest available final catalog year: '
      '`${summary['latestAvailableFinalCatalogYear']}`',
    )
    ..writeln('- Target event year: `${summary['targetEventYear']}`')
    ..writeln(
      '- External catalog not yet available: '
      '`${summary['externalCatalogNotYetAvailableCount']}`',
    )
    ..writeln(
      '- Manual-review required: '
      '`${summary['manualReviewRequiredCount']}`',
    )
    ..writeln('- Write-link allowed: `${summary['writeLinkAllowedCount']}`')
    ..writeln(
      '- Metric promotion allowed: '
      '`${summary['metricPromotionAllowedCount']}`',
    )
    ..writeln(
      '- Split assignment allowed: '
      '`${summary['splitAssignmentAllowedCount']}`',
    )
    ..writeln()
    ..writeln('## Packets')
    ..writeln()
    ..writeln(
      '| Case | Planned use | Origin JST | Catalog status | Evidence | Decision |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- |');

  for (final rawPacket in _list(report['packets'])) {
    final packet = _map(rawPacket);
    buffer.writeln(
      '| `${packet['caseId']}` | `${packet['plannedUse']}` | '
      '`${packet['originTimeJst']}` | '
      '`${packet['catalogPacketStatus']}` | '
      '`${packet['catalogEvidence']}` | `${packet['decision']}` |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Manual Link Commands')
    ..writeln();

  for (final rawPacket in _list(report['packets'])) {
    final packet = _map(rawPacket);
    buffer
      ..writeln('### `${packet['caseId']}`')
      ..writeln()
      ..writeln('- Dry-run link command:')
      ..writeln()
      ..writeln('```powershell')
      ..writeln(packet['dryRunLinkCommand'])
      ..writeln('```')
      ..writeln()
      ..writeln('- Write-link allowed: `${packet['writeLinkAllowed']}`')
      ..writeln();
  }

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Keep all three cases diagnostic-only until a versioned JMA final catalog or equivalent reviewed source is linked.',
    )
    ..writeln(
      '- Do not mutate fixtures, assign splits, or promote catalog truth from this packet.',
    )
    ..writeln(
      '- JMA source/intensity text supplied during capture remains reference metadata, not final catalog truth.',
    )
    ..writeln()
    ..writeln('## Validation')
    ..writeln()
    ..writeln('- Status: `${validation['status']}`.');
  final violations = _list(validation['violations']);
  if (violations.isEmpty) {
    buffer.writeln('- Violations: none.');
  } else {
    buffer.writeln('- Violations: ${_codeList(violations)}.');
  }
  buffer.writeln();
  return buffer.toString();
}

Map<String, Object?> _readJsonFile(
  String path,
  List<String> errors, {
  required String expectedSchema,
  required String missingError,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('$missingError:$path');
    return <String, Object?>{};
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  if (data['schemaVersion'] != expectedSchema) {
    errors.add('unexpected_schema:$path');
  }
  return data;
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

Object? _singleValue(Iterable<Object?> values) {
  final unique = values.where((value) => value != null).toSet();
  if (unique.length == 1) return unique.single;
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _codeList(List<Object?> values) =>
    values.map((value) => '`$value`').join(', ');

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
