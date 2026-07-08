import 'dart:convert';
import 'dart:io';

const _defaultBlockerQueuePath =
    '.dart_tool/source_estimation_split_blocker_queue/report.json';
const _defaultAttemptsPath =
    'docs/data/source_estimation_external_input_attempts.json';
const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultOutput =
    '.dart_tool/final_catalog_or_hinet_revision_review_packet/report.json';
const _defaultMarkdown =
    'docs/baselines/final_catalog_or_hinet_revision_review_packet.generated.md';

void main(List<String> args) {
  final blockerQueuePath =
      _argument(args, '--blocker-queue') ?? _defaultBlockerQueuePath;
  final attemptsPath = _argument(args, '--attempts') ?? _defaultAttemptsPath;
  final fixtureDirectory =
      _argument(args, '--fixture-directory') ?? _defaultFixtureDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _ReviewPacketReport.build(
    blockerQueueFile: File(blockerQueuePath),
    attemptsFile: File(attemptsPath),
    fixtureDirectory: Directory(fixtureDirectory),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote final catalog or Hi-net revision review packet');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildFinalCatalogOrHinetRevisionReviewPacketJson({
  String blockerQueuePath = _defaultBlockerQueuePath,
  String attemptsPath = _defaultAttemptsPath,
  String fixtureDirectory = _defaultFixtureDirectory,
}) {
  return _ReviewPacketReport.build(
    blockerQueueFile: File(blockerQueuePath),
    attemptsFile: File(attemptsPath),
    fixtureDirectory: Directory(fixtureDirectory),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _ReviewPacketReport {
  final String blockerQueuePath;
  final String attemptsPath;
  final String fixtureDirectoryPath;
  final List<_ReviewPacket> packets;
  final List<String> errors;
  final List<String> warnings;

  const _ReviewPacketReport({
    required this.blockerQueuePath,
    required this.attemptsPath,
    required this.fixtureDirectoryPath,
    required this.packets,
    required this.errors,
    required this.warnings,
  });

  factory _ReviewPacketReport.build({
    required File blockerQueueFile,
    required File attemptsFile,
    required Directory fixtureDirectory,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final fixtures = _fixtureIndex(fixtureDirectory, warnings);
    final attemptsByCase = _attemptIndex(attemptsFile, errors, warnings);
    final packets = <_ReviewPacket>[];

    final queue = _readMap(
      blockerQueueFile,
      expectedSchema: 'source_estimation_split_blocker_queue_v1',
      missingError: 'split_blocker_queue_missing',
      schemaError: 'unexpected_split_blocker_queue_schema',
      errors: errors,
      requirePassStatus: true,
    );
    for (final rawBlocker in _list(queue['blockers'])) {
      final blocker = _map(rawBlocker);
      if (blocker['nextAction'] != 'link_final_catalog_or_hinet_revision') {
        continue;
      }
      final caseId = blocker['caseId']?.toString() ?? '';
      packets.add(
        _ReviewPacket.fromBlocker(
          blocker,
          fixture: fixtures[caseId],
          attempts: attemptsByCase[caseId] ?? const [],
        ),
      );
    }
    packets.sort((left, right) => left.caseId.compareTo(right.caseId));

    return _ReviewPacketReport(
      blockerQueuePath: blockerQueueFile.path,
      attemptsPath: attemptsFile.path,
      fixtureDirectoryPath: fixtureDirectory.path,
      packets: packets,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final negativeAttemptOnlyCount = packets.fold<int>(
      0,
      (count, packet) => count + packet.negativeAttemptOnlyCount,
    );
    return {
      'schemaVersion': 'final_catalog_or_hinet_revision_review_packet_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'blockerQueuePath': blockerQueuePath,
      'attemptsPath': attemptsPath,
      'fixtureDirectory': fixtureDirectoryPath,
      'summary': {
        'packetCount': packets.length,
        'manualReviewRequiredCount': packets.length,
        'automaticClearanceCount': 0,
        'fixtureMutationCount': 0,
        'splitManifestMutationCount': 0,
        'truthPromotionCount': 0,
        'negativeAttemptOnlyCount': negativeAttemptOnlyCount,
        'resolutionAllowedByPacketCount': 0,
      },
      'errors': errors,
      'warnings': warnings,
      'packets': packets.map((packet) => packet.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Final Catalog Or Hi-net Revision Review Packet')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Split blocker queue: `$blockerQueuePath`')
      ..writeln('- Attempts: `$attemptsPath`')
      ..writeln('- Packets: `${summary['packetCount']}`')
      ..writeln(
        '- Manual-review required: '
        '`${summary['manualReviewRequiredCount']}`',
      )
      ..writeln('- Automatic clearances: `0`')
      ..writeln('- Fixture mutations: `0`')
      ..writeln('- Split manifest mutations: `0`')
      ..writeln('- Truth promotions: `0`')
      ..writeln('- Negative attempts: `${summary['negativeAttemptOnlyCount']}`')
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
        ..writeln('- Planned use: `${packet.plannedUse}`')
        ..writeln('- Split status: `${packet.splitStatus}`')
        ..writeln('- Fixture: `${packet.fixturePath}`')
        ..writeln('- Truth source: `${packet.truthSource}`')
        ..writeln('- Origin JST: `${packet.originTimeJst ?? '--'}`')
        ..writeln('- Negative attempts: `${packet.negativeAttemptOnlyCount}`')
        ..writeln('- Required paths:')
        ..writeln('  - versioned JMA final catalog row')
        ..writeln('  - authenticated revised Hi-net/JMA source row')
        ..writeln()
        ..writeln('```powershell')
        ..writeln(packet.validationCommand)
        ..writeln('```')
        ..writeln()
        ..writeln(
          '- Decision: this packet is intake guidance only. It does not '
          'promote the EQuake reference text to truth and does not assign a '
          'split.',
        )
        ..writeln();
    }
    return buffer.toString();
  }
}

class _ReviewPacket {
  final String caseId;
  final String plannedUse;
  final String splitStatus;
  final List<Map<String, Object?>> pendingConditions;
  final String fixturePath;
  final String truthSource;
  final String? originTimeJst;
  final bool catalogTruthVerified;
  final String truthQuality;
  final List<_Attempt> attempts;
  final String validationCommand;

  const _ReviewPacket({
    required this.caseId,
    required this.plannedUse,
    required this.splitStatus,
    required this.pendingConditions,
    required this.fixturePath,
    required this.truthSource,
    required this.originTimeJst,
    required this.catalogTruthVerified,
    required this.truthQuality,
    required this.attempts,
    required this.validationCommand,
  });

  factory _ReviewPacket.fromBlocker(
    Map<String, Object?> blocker, {
    required _FixtureSnapshot? fixture,
    required List<_Attempt> attempts,
  }) {
    final caseId = blocker['caseId']?.toString() ?? '';
    final fixturePath =
        fixture?.path ??
        'test/fixtures/source_estimation/<fixture-for-$caseId>.json';
    return _ReviewPacket(
      caseId: caseId,
      plannedUse: blocker['plannedUse']?.toString() ?? '',
      splitStatus: blocker['splitStatus']?.toString() ?? '',
      pendingConditions: _list(
        blocker['pendingConditions'],
      ).map((condition) => _map(condition)).toList(growable: false),
      fixturePath: fixturePath,
      truthSource: fixture?.truthSource ?? 'unknown',
      originTimeJst: fixture?.originTimeJst,
      catalogTruthVerified: fixture?.catalogTruthVerified ?? false,
      truthQuality: fixture?.truthQuality ?? 'unknown',
      attempts: attempts,
      validationCommand:
          'powershell -NoProfile -ExecutionPolicy Bypass -File '
          'tools\\validate_source_estimation_split_blocker_queue.ps1',
    );
  }

  int get negativeAttemptOnlyCount => attempts
      .where((attempt) => attempt.evidenceStrength == 'negative_attempt_only')
      .length;

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'plannedUse': plannedUse,
    'splitStatus': splitStatus,
    'pendingConditions': pendingConditions,
    'fixturePath': fixturePath,
    'truthSource': truthSource,
    'originTimeJst': originTimeJst,
    'catalogTruthVerified': catalogTruthVerified,
    'truthQuality': truthQuality,
    'requiredResolutionPaths': [
      {
        'path': 'versioned_jma_final_catalog_row',
        'acceptance':
            'import official JMA final catalog, dry-run link fixture, then '
            'review before any --write',
      },
      {
        'path': 'authenticated_revised_hinet_or_jma_source_row',
        'acceptance':
            'obtain an authenticated event-level revised source row and '
            'record an explicit reviewed decision before split assignment',
      },
    ],
    'negativeAttempts': attempts.map((attempt) => attempt.toJson()).toList(),
    'negativeAttemptOnlyCount': negativeAttemptOnlyCount,
    'validationCommand': validationCommand,
    'reviewFields': [
      'reviewer',
      'checkedAtUtc',
      'selectedResolutionPath',
      'sourceUrl',
      'sourceVersionOrPageDate',
      'rawEventRowText',
      'dryRunResult',
    ],
    'manualReviewRequired': true,
    'automaticClearance': false,
    'fixtureMutation': false,
    'splitManifestMutation': false,
    'truthPromotion': false,
    'resolutionAllowedByPacket': false,
    'notes': [
      'EQuake source-estimation text remains reference-only.',
      'Negative attempts do not clear this blocker.',
      'Do not assign this event to a frozen split until the blocker queue no '
          'longer lists link_final_catalog_or_hinet_revision.',
    ],
  };
}

class _FixtureSnapshot {
  final String path;
  final String caseId;
  final String truthSource;
  final String? originTimeJst;
  final bool catalogTruthVerified;
  final String truthQuality;

  const _FixtureSnapshot({
    required this.path,
    required this.caseId,
    required this.truthSource,
    required this.originTimeJst,
    required this.catalogTruthVerified,
    required this.truthQuality,
  });

  factory _FixtureSnapshot.fromJson(String path, Map<String, Object?> json) {
    final truth = _map(json['truth']);
    final labels = _map(json['eventLabels']);
    final classification = _map(json['classification']);
    return _FixtureSnapshot(
      path: path.replaceAll('\\', '/'),
      caseId: json['caseId']?.toString() ?? '',
      truthSource: truth['source']?.toString() ?? 'unknown',
      originTimeJst: truth['originTimeJst']?.toString(),
      catalogTruthVerified: labels['catalogTruthVerified'] == true,
      truthQuality: classification['truthQuality']?.toString() ?? 'unknown',
    );
  }
}

class _Attempt {
  final String attemptId;
  final String method;
  final String target;
  final String result;
  final String evidenceStrength;
  final bool automaticClearance;
  final String notes;

  const _Attempt({
    required this.attemptId,
    required this.method,
    required this.target,
    required this.result,
    required this.evidenceStrength,
    required this.automaticClearance,
    required this.notes,
  });

  factory _Attempt.fromJson(Map<String, Object?> json) => _Attempt(
    attemptId: json['attemptId']?.toString() ?? '',
    method: json['method']?.toString() ?? '',
    target: json['target']?.toString() ?? '',
    result: json['result']?.toString() ?? '',
    evidenceStrength: json['evidenceStrength']?.toString() ?? '',
    automaticClearance: json['automaticClearance'] == true,
    notes: json['notes']?.toString() ?? '',
  );

  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'method': method,
    'target': target,
    'result': result,
    'evidenceStrength': evidenceStrength,
    'automaticClearance': automaticClearance,
    'notes': notes,
  };
}

Map<String, _FixtureSnapshot> _fixtureIndex(
  Directory directory,
  List<String> warnings,
) {
  final result = <String, _FixtureSnapshot>{};
  if (!directory.existsSync()) {
    warnings.add('fixture_directory_missing:${directory.path}');
    return result;
  }
  for (final entity in directory.listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    try {
      final decoded =
          jsonDecode(entity.readAsStringSync()) as Map<String, Object?>;
      final snapshot = _FixtureSnapshot.fromJson(entity.path, decoded);
      if (snapshot.caseId.isNotEmpty) {
        result[snapshot.caseId] = snapshot;
      }
    } catch (_) {
      // Non-fixture JSON files in the directory are ignored.
    }
  }
  return result;
}

Map<String, List<_Attempt>> _attemptIndex(
  File attemptsFile,
  List<String> errors,
  List<String> warnings,
) {
  final result = <String, List<_Attempt>>{};
  if (!attemptsFile.existsSync()) {
    warnings.add('external_input_attempts_missing:${attemptsFile.path}');
    return result;
  }
  final decoded =
      jsonDecode(attemptsFile.readAsStringSync()) as Map<String, Object?>;
  if (decoded['schemaVersion'] !=
      'source_estimation_external_input_attempts_v1') {
    errors.add('unexpected_external_input_attempts_schema');
  }
  for (final rawAttempt in _list(decoded['attempts'])) {
    final attempt = _map(rawAttempt);
    if (attempt['inputType'] != 'final_catalog_or_hinet_revision') continue;
    final caseId = attempt['caseId']?.toString() ?? '';
    result.putIfAbsent(caseId, () => []).add(_Attempt.fromJson(attempt));
  }
  for (final attempts in result.values) {
    attempts.sort((left, right) => left.attemptId.compareTo(right.attemptId));
  }
  return result;
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

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
