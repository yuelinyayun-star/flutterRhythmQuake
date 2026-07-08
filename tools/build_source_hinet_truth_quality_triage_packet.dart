import 'dart:convert';
import 'dart:io';

const _defaultMetricTriagePath =
    '.dart_tool/source_metric_readiness_triage/report.json';
const _defaultHinetQueuePath =
    '.dart_tool/hinet_truth_quality_review_queue/report.json';
const _defaultOutputPath =
    '.dart_tool/source_hinet_truth_quality_triage_packet/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_hinet_truth_quality_triage.generated.md';

const _expectedCaseIds = {
  '20260620_iwate_offshore_m34_ref',
};

void main(List<String> args) {
  final metricTriagePath =
      _argument(args, '--metric-triage') ?? _defaultMetricTriagePath;
  final hinetQueuePath =
      _argument(args, '--hinet-queue') ?? _defaultHinetQueuePath;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;

  final report = buildSourceHinetTruthQualityTriagePacketJson(
    metricTriagePath: metricTriagePath,
    hinetQueuePath: hinetQueuePath,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );

  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(report));

  stdout.writeln('wrote source Hi-net truth-quality triage packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report['status'] != 'pass') exitCode = 1;
}

Map<String, Object?> buildSourceHinetTruthQualityTriagePacketJson({
  String metricTriagePath = _defaultMetricTriagePath,
  String hinetQueuePath = _defaultHinetQueuePath,
}) {
  final errors = <String>[];
  final metricTriage = _readJsonFile(
    metricTriagePath,
    errors,
    expectedSchema: 'source_metric_readiness_triage_v1',
    missingError: 'source_metric_readiness_triage_missing',
  );
  final hinetQueue = _readJsonFile(
    hinetQueuePath,
    errors,
    expectedSchema: 'hinet_truth_quality_review_queue_v1',
    missingError: 'hinet_truth_quality_review_queue_missing',
  );

  final metricCases = _list(
    metricTriage['cases'],
  ).map(_map).where(_isHinetReviewBlocked).toList(growable: false);
  final queueCases = {
    for (final entry in _list(hinetQueue['cases']).map(_map))
      entry['caseId']?.toString() ?? '': entry,
  }..remove('');

  final packets =
      metricCases
          .map((metricCase) {
            final caseId = metricCase['caseId']?.toString() ?? '';
            return _packet(
              metricCase,
              queueCases[caseId] ?? const <String, Object?>{},
            );
          })
          .toList(growable: false)
        ..sort((left, right) {
          final priority = _intValue(
            left['priority'],
          )!.compareTo(_intValue(right['priority'])!);
          if (priority != 0) return priority;
          return left['caseId'].toString().compareTo(
            right['caseId'].toString(),
          );
        });

  final summary = _summary(packets);
  final validation = _validation(
    metricTriage: metricTriage,
    hinetQueue: hinetQueue,
    packets: packets,
    summary: summary,
    errors: errors,
  );
  final violations = _list(validation['violations']);

  return {
    'schemaVersion': 'source_hinet_truth_quality_triage_packet_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty && violations.isEmpty ? 'pass' : 'fail',
    'inputs': {
      'sourceMetricReadinessTriage': metricTriagePath,
      'hinetTruthQualityReviewQueue': hinetQueuePath,
    },
    'policy': const {
      'diagnosticOnly': true,
      'fixtureMutationAllowed': false,
      'assignsSplits': false,
      'changesMetricEligibility': false,
      'acceptsTruthQuality': false,
      'notes':
          'This packet only aligns source-estimation Hi-net blockers with the manual truth-quality review queue.',
    },
    'summary': summary,
    'errors': errors,
    'validation': validation,
    'packets': packets,
  };
}

bool _isHinetReviewBlocked(Map<String, Object?> entry) {
  final nextAction = entry['nextAction']?.toString();
  return nextAction == 'review_hinet_preliminary_truth_quality' ||
      nextAction == 'review_hinet_truth_quality';
}

Map<String, Object?> _packet(
  Map<String, Object?> metricCase,
  Map<String, Object?> queueCase,
) {
  final queueNextAction = queueCase['nextAction']?.toString() ?? 'missing';
  return {
    'caseId': metricCase['caseId'],
    'plannedUse': metricCase['plannedUse'],
    'triageTier': metricCase['triageTier'],
    'splitStatus': metricCase['splitStatus'],
    'captureStatus': metricCase['captureStatus'],
    'metricNextAction': metricCase['nextAction'],
    'metricBlockingReason': metricCase['metricBlockingReason'],
    'truthSource': metricCase['truthSource'],
    'catalogTruthVerified': metricCase['catalogTruthVerified'] == true,
    'queueNextAction': queueNextAction,
    'priority': _intValue(queueCase['priority']) ?? 99,
    'truthQuality': queueCase['truthQuality'],
    'decisionStatus': queueCase['decisionStatus'],
    'captureProvenanceComplete': queueCase['captureProvenanceComplete'] == true,
    'catalogTruthFlagMismatch': queueCase['catalogTruthFlagMismatch'] == true,
    'requiredEvidence': _stringList(queueCase['requiredEvidence']),
    'manualReviewRequired': true,
    'splitAssignmentAllowed': false,
    'metricPromotionAllowed': false,
    'fixtureMutationAllowed': false,
    'truthQualityAcceptanceAllowed': false,
    'decision': _decision(queueNextAction),
  };
}

String _decision(String queueNextAction) {
  switch (queueNextAction) {
    case 'collect_external_hinet_or_jma_revised_evidence':
      return 'collect_revised_hinet_or_jma_evidence_before_review';
    case 'resolve_catalog_truth_flag_mismatch':
      return 'resolve_catalog_truth_flag_mismatch_before_review';
    case 'repair_capture_before_review':
      return 'repair_or_exclude_capture_before_review';
    default:
      return 'queue_mapping_missing';
  }
}

Map<String, Object?> _summary(List<Map<String, Object?>> packets) {
  return {
    'packetCount': packets.length,
    'expectedPacketCount': _expectedCaseIds.length,
    'diagnosticReadyBlockedCount': packets
        .where((entry) => entry['triageTier'] == 'diagnostic_ready_blocked')
        .length,
    'metadataOnlyOrIncompleteCount': packets
        .where((entry) => entry['triageTier'] == 'metadata_only_or_incomplete')
        .length,
    'priorityExternalEvidenceReviewCount': packets
        .where(
          (entry) =>
              entry['queueNextAction'] ==
              'collect_external_hinet_or_jma_revised_evidence',
        )
        .length,
    'catalogFlagMismatchBlockedCount': packets
        .where(
          (entry) =>
              entry['queueNextAction'] == 'resolve_catalog_truth_flag_mismatch',
        )
        .length,
    'captureRepairBlockedCount': packets
        .where(
          (entry) => entry['queueNextAction'] == 'repair_capture_before_review',
        )
        .length,
    'manualReviewRequiredCount': packets
        .where((entry) => entry['manualReviewRequired'] == true)
        .length,
    'truthQualityAcceptanceAllowedCount': packets
        .where((entry) => entry['truthQualityAcceptanceAllowed'] == true)
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
    'queueMappingMissingCount': packets
        .where((entry) => entry['queueNextAction'] == 'missing')
        .length,
    'queueNextActionCounts': _counts(
      packets.map((entry) => entry['queueNextAction']),
    ),
  };
}

Map<String, Object?> _validation({
  required Map<String, Object?> metricTriage,
  required Map<String, Object?> hinetQueue,
  required List<Map<String, Object?>> packets,
  required Map<String, Object?> summary,
  required List<String> errors,
}) {
  final violations = <String>[];
  if (metricTriage['status'] != 'pass') {
    violations.add('source_metric_readiness_triage_not_pass');
  }
  if (hinetQueue['status'] != 'pass') {
    violations.add('hinet_truth_quality_review_queue_not_pass');
  }

  final actualCaseIds = packets
      .map((entry) => entry['caseId']?.toString() ?? '')
      .where((caseId) => caseId.isNotEmpty)
      .toSet();
  if (actualCaseIds.length != _expectedCaseIds.length ||
      !actualCaseIds.containsAll(_expectedCaseIds)) {
    violations.add('unexpected_hinet_truth_quality_case_set');
  }
  if (_intValue(summary['packetCount']) != 1) {
    violations.add('unexpected_packet_count');
  }
  if (_intValue(summary['diagnosticReadyBlockedCount']) != 0) {
    violations.add('diagnostic_ready_blocked_count_changed');
  }
  if (_intValue(summary['metadataOnlyOrIncompleteCount']) != 1) {
    violations.add('metadata_incomplete_count_changed');
  }
  if (_intValue(summary['priorityExternalEvidenceReviewCount']) != 0) {
    violations.add('priority_external_evidence_count_changed');
  }
  if (_intValue(summary['catalogFlagMismatchBlockedCount']) != 0) {
    violations.add('catalog_flag_mismatch_count_changed');
  }
  if (_intValue(summary['captureRepairBlockedCount']) != 1) {
    violations.add('capture_repair_count_changed');
  }
  if (_intValue(summary['truthQualityAcceptanceAllowedCount']) != 0) {
    violations.add('truth_quality_acceptance_allowed');
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
  if (_intValue(summary['queueMappingMissingCount']) != 0) {
    violations.add('hinet_queue_mapping_missing');
  }

  for (final packet in packets) {
    final caseId = packet['caseId'];
    if (packet['manualReviewRequired'] != true) {
      violations.add('$caseId:manual_review_not_required');
    }
    if (!_list(
      packet['requiredEvidence'],
    ).contains('reviewer_and_review_timestamp')) {
      violations.add('$caseId:missing_reviewer_timestamp_evidence');
    }
    if (packet['queueNextAction'] ==
            'collect_external_hinet_or_jma_revised_evidence' &&
        packet['catalogTruthFlagMismatch'] == true) {
      violations.add('$caseId:priority_case_has_catalog_flag_mismatch');
    }
    if (packet['queueNextAction'] ==
            'collect_external_hinet_or_jma_revised_evidence' &&
        packet['captureProvenanceComplete'] != true) {
      violations.add('$caseId:priority_case_capture_incomplete');
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
    ..writeln('# Source Hi-net Truth-Quality Triage Packet')
    ..writeln()
    ..writeln('- Status: `${report['status']}`')
    ..writeln('- Packets: `${summary['packetCount']}`')
    ..writeln(
      '- Diagnostic-ready blocked: '
      '`${summary['diagnosticReadyBlockedCount']}`',
    )
    ..writeln(
      '- Metadata-only/incomplete: '
      '`${summary['metadataOnlyOrIncompleteCount']}`',
    )
    ..writeln(
      '- Priority external-evidence reviews: '
      '`${summary['priorityExternalEvidenceReviewCount']}`',
    )
    ..writeln(
      '- Catalog-flag-mismatch blocked: '
      '`${summary['catalogFlagMismatchBlockedCount']}`',
    )
    ..writeln(
      '- Capture-repair blocked: `${summary['captureRepairBlockedCount']}`',
    )
    ..writeln(
      '- Truth-quality acceptance allowed: '
      '`${summary['truthQualityAcceptanceAllowedCount']}`',
    )
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
      '| Priority | Case | Triage | Planned use | Queue action | Required evidence | Decision |',
    )
    ..writeln('| ---: | --- | --- | --- | --- | --- | --- |');

  for (final rawPacket in _list(report['packets'])) {
    final packet = _map(rawPacket);
    buffer.writeln(
      '| ${packet['priority']} | `${packet['caseId']}` | '
      '`${packet['triageTier']}` | `${packet['plannedUse']}` | '
      '`${packet['queueNextAction']}` | '
      '`${_stringList(packet['requiredEvidence']).join('`, `')}` | '
      '`${packet['decision']}` |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Decision')
    ..writeln()
    ..writeln(
      '- Keep all Hi-net-blocked cases out of metric-bearing validation until manual truth-quality evidence is reviewed.',
    )
    ..writeln(
      '- Work priority 1 first: collect revised Hi-net or JMA evidence for the three complete, non-mismatch preliminary cases.',
    )
    ..writeln(
      '- Resolve catalog-truth flag mismatches before reviewing the three user-provided Hi-net cases.',
    )
    ..writeln(
      '- Repair or explicitly exclude the incomplete Iwate M3.4 capture before truth-quality review.',
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

Map<String, int> _counts(Iterable<Object?> values) {
  final counts = <String, int>{};
  for (final value in values) {
    final key = value?.toString() ?? '';
    if (key.isEmpty) continue;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _codeList(List<Object?> values) =>
    values.map((value) => '`$value`').join(', ');

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _stringList(Object? value) =>
    _list(value).map((entry) => entry.toString()).toList(growable: false);

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
