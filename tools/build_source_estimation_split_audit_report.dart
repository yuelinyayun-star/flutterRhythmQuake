import 'dart:convert';
import 'dart:io';

const _defaultSplitManifest =
    'test/fixtures/source_estimation/dataset_splits.json';
const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultQuietWindowPlan =
    'docs/data/source_estimation_quiet_window_capture_plan.json';
const _defaultSplitAssignmentPlan =
    'docs/data/source_estimation_split_assignment_plan.json';
const _defaultOutput = '.dart_tool/source_estimation_split_audit/report.json';
const _defaultMarkdown =
    'docs/baselines/source_estimation_split_audit.generated.md';

void main(List<String> args) {
  final splitManifestPath = _argument(args, '--split') ?? _defaultSplitManifest;
  final fixtureDirectoryPath =
      _argument(args, '--fixtures') ?? _defaultFixtureDirectory;
  final quietWindowPlanPath =
      _argument(args, '--quiet-window-plan') ?? _defaultQuietWindowPlan;
  final splitAssignmentPlanPath =
      _argument(args, '--split-assignment-plan') ?? _defaultSplitAssignmentPlan;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final splitManifest = _SplitManifest.read(File(splitManifestPath));
  final fixtures = _FixtureInventory.read(Directory(fixtureDirectoryPath));
  final quietWindowPlan = _QuietWindowCapturePlan.readOptional(
    File(quietWindowPlanPath),
  );
  final splitAssignmentPlan = _SplitAssignmentPlan.readOptional(
    File(splitAssignmentPlanPath),
  );
  final audit = _SplitAudit.fromInventory(
    splitManifest: splitManifest,
    inventory: fixtures,
    quietWindowPlan: quietWindowPlan,
    splitAssignmentPlan: splitAssignmentPlan,
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(audit.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(audit.toMarkdown());

  stdout.writeln('wrote source-estimation split audit');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

class _SplitManifest {
  final File file;
  final int schemaVersion;
  final String datasetId;
  final String frozenAt;
  final String splitPolicy;
  final Map<String, List<String>> splits;

  const _SplitManifest({
    required this.file,
    required this.schemaVersion,
    required this.datasetId,
    required this.frozenAt,
    required this.splitPolicy,
    required this.splits,
  });

  factory _SplitManifest.read(File file) {
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final rawSplits = _map(data['splits']);
    return _SplitManifest(
      file: file,
      schemaVersion: _int(data['schemaVersion']) ?? -1,
      datasetId: data['datasetId']?.toString() ?? '',
      frozenAt: data['frozenAt']?.toString() ?? '',
      splitPolicy: data['splitPolicy']?.toString() ?? '',
      splits: {
        for (final entry in rawSplits.entries)
          entry.key: _list(
            entry.value,
          ).map((value) => value.toString()).toList(growable: false),
      },
    );
  }

  Set<String> get splitCaseFiles => {
    for (final files in splits.values) ...files,
  };
}

class _FixtureInventory {
  final Directory directory;
  final List<_CaseFixture> cases;

  const _FixtureInventory({required this.directory, required this.cases});

  factory _FixtureInventory.read(Directory directory) {
    final cases = <_CaseFixture>[];
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.json'))
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map) continue;
        final data = decoded.cast<String, Object?>();
        final caseId = data['caseId']?.toString();
        final caseType = data['caseType']?.toString();
        if (caseId == null || caseType == null) continue;
        cases.add(_CaseFixture.fromJson(file, data));
      } on FormatException {
        continue;
      }
    }
    return _FixtureInventory(directory: directory, cases: cases);
  }
}

class _QuietWindowCapturePlan {
  static const _defaultRequiredLayerFamilies = [
    'jma',
    'acmap',
    'vcmap',
    'dcmap',
  ];

  final File file;
  final String schemaVersion;
  final int targetIndependentQuietWindowCount;
  final int plannedCaptureCount;
  final int minimumDurationSeconds;
  final String captureScript;
  final List<String> requiredLayerFamilies;
  final List<String> layers;

  const _QuietWindowCapturePlan({
    required this.file,
    required this.schemaVersion,
    required this.targetIndependentQuietWindowCount,
    required this.plannedCaptureCount,
    required this.minimumDurationSeconds,
    required this.captureScript,
    required this.requiredLayerFamilies,
    required this.layers,
  });

  factory _QuietWindowCapturePlan.readOptional(File file) {
    if (!file.existsSync()) {
      return _QuietWindowCapturePlan(
        file: file,
        schemaVersion: 'missing',
        targetIndependentQuietWindowCount: 2,
        plannedCaptureCount: 0,
        minimumDurationSeconds: 0,
        captureScript: '',
        requiredLayerFamilies: const [],
        layers: const [],
      );
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final requiredLayerFamilies = _list(
      data['requiredLayerFamilies'],
    ).map((entry) => entry.toString()).toList(growable: false);
    final layers = _list(
      data['layers'],
    ).map((entry) => entry.toString()).toList(growable: false)..sort();
    return _QuietWindowCapturePlan(
      file: file,
      schemaVersion: data['schemaVersion']?.toString() ?? '',
      targetIndependentQuietWindowCount:
          _int(data['targetIndependentQuietWindowCount']) ?? 2,
      plannedCaptureCount: _list(data['plannedCaptures']).length,
      minimumDurationSeconds: _int(data['minimumDurationSeconds']) ?? 0,
      captureScript: data['captureScript']?.toString() ?? '',
      requiredLayerFamilies: requiredLayerFamilies.isEmpty
          ? _defaultRequiredLayerFamilies
          : requiredLayerFamilies,
      layers: layers,
    );
  }

  List<String> get missingRequiredLayers {
    final layerSet = layers.toSet();
    final missing = <String>[];
    for (final family in requiredLayerFamilies) {
      for (final suffix in const ['s', 'b']) {
        final layer = '${family}_$suffix';
        if (!layerSet.contains(layer)) missing.add(layer);
      }
    }
    return missing;
  }

  bool get hasRequiredLayers => missingRequiredLayers.isEmpty;

  Map<String, Object?> toJson({required int currentQuietWindowCount}) {
    final remaining =
        targetIndependentQuietWindowCount - currentQuietWindowCount;
    return {
      'path': file.path,
      'schemaVersion': schemaVersion,
      'targetIndependentQuietWindowCount': targetIndependentQuietWindowCount,
      'currentIndependentQuietWindowCount': currentQuietWindowCount,
      'remainingIndependentQuietWindowCount': remaining > 0 ? remaining : 0,
      'plannedCaptureCount': plannedCaptureCount,
      'minimumDurationSeconds': minimumDurationSeconds,
      'captureScript': captureScript,
      'requiredLayerFamilies': requiredLayerFamilies,
      'layers': layers,
      'layerCount': layers.length,
      'missingRequiredLayers': missingRequiredLayers,
      'hasRequiredLayers': hasRequiredLayers,
    };
  }
}

class _SplitAssignmentPlan {
  final File file;
  final String schemaVersion;
  final Map<String, _SplitAssignmentPlanCase> casesById;

  const _SplitAssignmentPlan({
    required this.file,
    required this.schemaVersion,
    required this.casesById,
  });

  factory _SplitAssignmentPlan.readOptional(File file) {
    if (!file.existsSync()) {
      return _SplitAssignmentPlan(
        file: file,
        schemaVersion: 'missing',
        casesById: const {},
      );
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final cases = <String, _SplitAssignmentPlanCase>{};
    for (final rawCase in _list(data['cases'])) {
      final item = _SplitAssignmentPlanCase.fromJson(_map(rawCase));
      if (item.caseId.isNotEmpty) {
        cases[item.caseId] = item;
      }
    }
    return _SplitAssignmentPlan(
      file: file,
      schemaVersion: data['schemaVersion']?.toString() ?? '',
      casesById: Map.unmodifiable(cases),
    );
  }

  bool contains(String caseId) => casesById.containsKey(caseId);

  Map<String, Object?> toJson({
    required int unassignedReferenceEventCount,
    required int plannedUnassignedReferenceEventCount,
  }) => {
    'path': file.path,
    'schemaVersion': schemaVersion,
    'caseCount': casesById.length,
    'unassignedReferenceEventCount': unassignedReferenceEventCount,
    'plannedUnassignedReferenceEventCount':
        plannedUnassignedReferenceEventCount,
    'unplannedUnassignedReferenceEventCount':
        unassignedReferenceEventCount - plannedUnassignedReferenceEventCount,
    'cases': casesById.values.map((entry) => entry.toJson()).toList(),
  };
}

class _SplitAssignmentPlanCase {
  final String caseId;
  final String currentStatus;
  final String plannedUse;
  final List<String> requiredBeforeFrozenSplit;

  const _SplitAssignmentPlanCase({
    required this.caseId,
    required this.currentStatus,
    required this.plannedUse,
    required this.requiredBeforeFrozenSplit,
  });

  factory _SplitAssignmentPlanCase.fromJson(Map<String, Object?> json) {
    return _SplitAssignmentPlanCase(
      caseId: json['caseId']?.toString() ?? '',
      currentStatus: json['currentStatus']?.toString() ?? '',
      plannedUse: json['plannedUse']?.toString() ?? '',
      requiredBeforeFrozenSplit: _list(
        json['requiredBeforeFrozenSplit'],
      ).map((entry) => entry.toString()).toList(growable: false),
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'currentStatus': currentStatus,
    'plannedUse': plannedUse,
    'requiredBeforeFrozenSplit': requiredBeforeFrozenSplit,
  };
}

class _CaseFixture {
  final String fileName;
  final String caseId;
  final String caseType;
  final String splitStatus;
  final bool includeInDetectionMetrics;
  final bool catalogEvent;
  final bool catalogTruthVerified;
  final String truthSource;
  final String region;

  const _CaseFixture({
    required this.fileName,
    required this.caseId,
    required this.caseType,
    required this.splitStatus,
    required this.includeInDetectionMetrics,
    required this.catalogEvent,
    required this.catalogTruthVerified,
    required this.truthSource,
    required this.region,
  });

  factory _CaseFixture.fromJson(File file, Map<String, Object?> json) {
    final labels = _map(json['eventLabels']);
    final truth = _map(json['truth']);
    final classification = _map(json['classification']);
    return _CaseFixture(
      fileName: file.uri.pathSegments.last,
      caseId: json['caseId']?.toString() ?? '',
      caseType: json['caseType']?.toString() ?? '',
      splitStatus: json['splitStatus']?.toString() ?? 'unspecified',
      includeInDetectionMetrics: labels['includeInDetectionMetrics'] == true,
      catalogEvent: labels['catalogEvent'] == true,
      catalogTruthVerified: labels['catalogTruthVerified'] == true,
      truthSource: truth['source']?.toString() ?? '',
      region: classification['region']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson({required String split}) => {
    'fileName': fileName,
    'caseId': caseId,
    'caseType': caseType,
    'split': split,
    'splitStatus': splitStatus,
    'includeInDetectionMetrics': includeInDetectionMetrics,
    'catalogEvent': catalogEvent,
    'catalogTruthVerified': catalogTruthVerified,
    'truthSource': truthSource,
    'region': region,
  };
}

class _SplitAudit {
  final _SplitManifest splitManifest;
  final _QuietWindowCapturePlan quietWindowPlan;
  final _SplitAssignmentPlan splitAssignmentPlan;
  final List<_AuditedCase> cases;
  final List<String> errors;
  final List<String> warnings;

  const _SplitAudit({
    required this.splitManifest,
    required this.quietWindowPlan,
    required this.splitAssignmentPlan,
    required this.cases,
    required this.errors,
    required this.warnings,
  });

  factory _SplitAudit.fromInventory({
    required _SplitManifest splitManifest,
    required _FixtureInventory inventory,
    required _QuietWindowCapturePlan quietWindowPlan,
    required _SplitAssignmentPlan splitAssignmentPlan,
  }) {
    final splitByFile = <String, String>{};
    final errors = <String>[];
    for (final entry in splitManifest.splits.entries) {
      for (final fileName in entry.value) {
        final previous = splitByFile[fileName];
        if (previous != null) {
          errors.add(
            'case_file_in_multiple_splits:$fileName:$previous:${entry.key}',
          );
        } else {
          splitByFile[fileName] = entry.key;
        }
      }
    }

    final byFile = {
      for (final fixture in inventory.cases) fixture.fileName: fixture,
    };
    for (final fileName in splitManifest.splitCaseFiles) {
      if (!byFile.containsKey(fileName)) {
        errors.add('split_case_file_missing:$fileName');
      }
    }

    final auditedCases = <_AuditedCase>[];
    for (final fixture in inventory.cases) {
      final split = splitByFile[fixture.fileName] ?? 'unassigned';
      auditedCases.add(_AuditedCase(fixture: fixture, split: split));
    }
    auditedCases.sort((left, right) {
      final splitCompare = left.split.compareTo(right.split);
      if (splitCompare != 0) return splitCompare;
      return left.fixture.caseId.compareTo(right.fixture.caseId);
    });

    final caseIdToSplit = <String, String>{};
    for (final entry in auditedCases) {
      final previous = caseIdToSplit[entry.fixture.caseId];
      if (previous != null) {
        errors.add('case_id_in_multiple_files:${entry.fixture.caseId}');
      } else {
        caseIdToSplit[entry.fixture.caseId] = entry.split;
      }
      if (entry.split == 'unassigned' &&
          entry.fixture.includeInDetectionMetrics) {
        errors.add(
          'unassigned_case_in_detection_metrics:${entry.fixture.caseId}',
        );
      }
      if (entry.split != 'unassigned' &&
          entry.fixture.splitStatus == 'unassigned_reference') {
        errors.add('frozen_case_marked_unassigned:${entry.fixture.caseId}');
      }
      if (entry.fixture.caseType == 'noise' &&
          entry.fixture.includeInDetectionMetrics) {
        errors.add(
          'noise_case_in_detection_denominator:${entry.fixture.caseId}',
        );
      }
    }

    final warnings = <String>[];
    final unassignedEvents = auditedCases
        .where(
          (entry) =>
              entry.split == 'unassigned' && entry.fixture.caseType == 'event',
        )
        .length;
    final unspecifiedUnassignedEvents = auditedCases
        .where(
          (entry) =>
              entry.split == 'unassigned' &&
              entry.fixture.caseType == 'event' &&
              entry.fixture.splitStatus == 'unspecified',
        )
        .length;
    final noiseCount = auditedCases
        .where((entry) => entry.fixture.caseType == 'noise')
        .length;
    final splitNoiseCount = auditedCases
        .where(
          (entry) =>
              entry.split != 'unassigned' && entry.fixture.caseType == 'noise',
        )
        .length;
    if (unassignedEvents > 0) {
      warnings.add('unassigned_reference_event_count:$unassignedEvents');
    }
    if (splitAssignmentPlan.schemaVersion == 'missing') {
      warnings.add('split_assignment_plan_missing');
    }
    final unplannedUnassignedEventCount = auditedCases
        .where(
          (entry) =>
              entry.split == 'unassigned' &&
              entry.fixture.caseType == 'event' &&
              !splitAssignmentPlan.contains(entry.fixture.caseId),
        )
        .length;
    if (unplannedUnassignedEventCount > 0) {
      warnings.add(
        'unassigned_reference_without_assignment_plan:'
        '$unplannedUnassignedEventCount',
      );
    }
    if (unspecifiedUnassignedEvents > 0) {
      warnings.add(
        'unassigned_event_without_split_status:$unspecifiedUnassignedEvents',
      );
    }
    if (noiseCount < 2) {
      warnings.add('independent_quiet_window_count_below_2:$noiseCount');
    }
    if (quietWindowPlan.schemaVersion == 'missing') {
      warnings.add('quiet_window_capture_plan_missing');
    } else if (!quietWindowPlan.hasRequiredLayers) {
      warnings.add(
        'quiet_window_capture_plan_missing_required_layers:'
        '${quietWindowPlan.missingRequiredLayers.join(',')}',
      );
    }
    final remainingQuietWindowCount =
        quietWindowPlan.targetIndependentQuietWindowCount - noiseCount;
    if (remainingQuietWindowCount > quietWindowPlan.plannedCaptureCount) {
      warnings.add(
        'quiet_window_capture_plan_insufficient:'
        '${quietWindowPlan.plannedCaptureCount}<$remainingQuietWindowCount',
      );
    }
    if (splitNoiseCount < 1) {
      warnings.add('no_noise_case_in_frozen_split');
    }

    return _SplitAudit(
      splitManifest: splitManifest,
      quietWindowPlan: quietWindowPlan,
      splitAssignmentPlan: splitAssignmentPlan,
      cases: List.unmodifiable(auditedCases),
      errors: errors,
      warnings: warnings,
    );
  }

  bool get passed => errors.isEmpty;

  Map<String, Object?> toJson() => {
    'schemaVersion': 'source_estimation_split_audit_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': passed ? 'pass' : 'fail',
    'splitManifest': {
      'path': splitManifest.file.path,
      'datasetId': splitManifest.datasetId,
      'frozenAt': splitManifest.frozenAt,
      'splitPolicy': splitManifest.splitPolicy,
      'splits': splitManifest.splits,
    },
    'summary': _summary(),
    'quietWindowCapturePlan': quietWindowPlan.toJson(
      currentQuietWindowCount: _noiseCount,
    ),
    'splitAssignmentPlan': splitAssignmentPlan.toJson(
      unassignedReferenceEventCount: _unassignedReferenceEventCount,
      plannedUnassignedReferenceEventCount:
          _plannedUnassignedReferenceEventCount,
    ),
    'errors': errors,
    'warnings': warnings,
    'cases': cases.map((entry) => entry.toJson()).toList(growable: false),
  };

  Map<String, Object?> _summary() {
    final bySplit = <String, int>{};
    final byType = <String, int>{};
    var detectionDenominator = 0;
    var unassignedReferenceEvents = 0;
    for (final entry in cases) {
      bySplit.update(entry.split, (value) => value + 1, ifAbsent: () => 1);
      byType.update(
        entry.fixture.caseType,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (entry.fixture.includeInDetectionMetrics) detectionDenominator++;
      if (entry.split == 'unassigned' && entry.fixture.caseType == 'event') {
        unassignedReferenceEvents++;
      }
    }
    return {
      'caseCount': cases.length,
      'bySplit': bySplit,
      'byCaseType': byType,
      'detectionMetricCaseCount': detectionDenominator,
      'unassignedReferenceEventCount': unassignedReferenceEvents,
      'explicitUnassignedReferenceEventCount': cases
          .where(
            (entry) =>
                entry.split == 'unassigned' &&
                entry.fixture.caseType == 'event' &&
                entry.fixture.splitStatus == 'unassigned_reference',
          )
          .length,
      'unspecifiedUnassignedEventCount': cases
          .where(
            (entry) =>
                entry.split == 'unassigned' &&
                entry.fixture.caseType == 'event' &&
                entry.fixture.splitStatus == 'unspecified',
          )
          .length,
      'quietWindowTargetCount':
          quietWindowPlan.targetIndependentQuietWindowCount,
      'quietWindowRemainingCount': _remainingQuietWindowCount,
      'quietWindowPlannedCaptureCount': quietWindowPlan.plannedCaptureCount,
      'quietWindowLayerCount': quietWindowPlan.layers.length,
      'splitAssignmentPlanCaseCount': splitAssignmentPlan.casesById.length,
      'plannedUnassignedReferenceEventCount':
          _plannedUnassignedReferenceEventCount,
      'unplannedUnassignedReferenceEventCount':
          _unassignedReferenceEventCount -
          _plannedUnassignedReferenceEventCount,
    };
  }

  int get _unassignedReferenceEventCount => cases
      .where(
        (entry) =>
            entry.split == 'unassigned' && entry.fixture.caseType == 'event',
      )
      .length;

  int get _plannedUnassignedReferenceEventCount => cases
      .where(
        (entry) =>
            entry.split == 'unassigned' &&
            entry.fixture.caseType == 'event' &&
            splitAssignmentPlan.contains(entry.fixture.caseId),
      )
      .length;

  int get _noiseCount =>
      cases.where((entry) => entry.fixture.caseType == 'noise').length;

  int get _remainingQuietWindowCount {
    final remaining =
        quietWindowPlan.targetIndependentQuietWindowCount - _noiseCount;
    return remaining > 0 ? remaining : 0;
  }

  String toMarkdown() {
    final summary = _summary();
    final buffer = StringBuffer()
      ..writeln('# Source Estimation Split Audit')
      ..writeln()
      ..writeln('- Status: `${passed ? 'pass' : 'fail'}`')
      ..writeln('- Dataset: `${splitManifest.datasetId}`')
      ..writeln('- Frozen at: `${splitManifest.frozenAt}`')
      ..writeln('- Split manifest: `${splitManifest.file.path}`')
      ..writeln('- Case count: `${summary['caseCount']}`')
      ..writeln(
        '- Detection metric denominator cases: `${summary['detectionMetricCaseCount']}`',
      )
      ..writeln(
        '- Unassigned reference events: `${summary['unassignedReferenceEventCount']}`',
      )
      ..writeln(
        '- Explicit unassigned references: `${summary['explicitUnassignedReferenceEventCount']}`',
      )
      ..writeln(
        '- Legacy unspecified unassigned events: `${summary['unspecifiedUnassignedEventCount']}`',
      )
      ..writeln(
        '- Quiet-window target/current/remaining: '
        '`${summary['quietWindowTargetCount']}/$_noiseCount/${summary['quietWindowRemainingCount']}`',
      )
      ..writeln(
        '- Quiet-window planned captures: `${summary['quietWindowPlannedCaptureCount']}`',
      )
      ..writeln('- Quiet-window plan: `${quietWindowPlan.file.path}`')
      ..writeln(
        '- Quiet-window required layers: '
        '`${quietWindowPlan.layers.length}` '
        '(${quietWindowPlan.layers.map((layer) => '`$layer`').join(', ')})',
      )
      ..writeln(
        '- Split assignment planned/unplanned: '
        '`${summary['plannedUnassignedReferenceEventCount']}/${summary['unplannedUnassignedReferenceEventCount']}`',
      )
      ..writeln('- Split assignment plan: `${splitAssignmentPlan.file.path}`')
      ..writeln()
      ..writeln('## Validation')
      ..writeln()
      ..writeln(
        '- Errors: ${errors.isEmpty ? 'none' : errors.map((e) => '`$e`').join(', ')}',
      )
      ..writeln(
        '- Warnings: ${warnings.isEmpty ? 'none' : warnings.map((e) => '`$e`').join(', ')}',
      )
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Split | Case | Type | Metrics | Split status | Truth | Region |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
    for (final entry in cases) {
      final fixture = entry.fixture;
      buffer.writeln(
        '| `${_cell(entry.split)}` | `${_cell(fixture.caseId)}` | '
        '`${_cell(fixture.caseType)}` | '
        '${fixture.includeInDetectionMetrics ? 'yes' : 'no'} | '
        '`${_cell(fixture.splitStatus)}` | '
        '`${_cell(fixture.truthSource)}` | `${_cell(fixture.region)}` |',
      );
    }
    return buffer.toString();
  }
}

class _AuditedCase {
  final _CaseFixture fixture;
  final String split;

  const _AuditedCase({required this.fixture, required this.split});

  Map<String, Object?> toJson() => fixture.toJson(split: split);
}

String? _argument(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) return args[i + 1];
    if (arg.startsWith('$name=')) return arg.substring(name.length + 1);
  }
  return null;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _cell(String value) {
  return value.replaceAll('|', r'\|').replaceAll(RegExp(r'[\r\n]+'), ' ');
}
