import 'dart:convert';
import 'dart:io';

const _defaultReadinessReport =
    '.dart_tool/source_estimation_split_assignment_readiness/report.json';
const _defaultOutput =
    '.dart_tool/source_estimation_split_blocker_queue/report.json';
const _defaultMarkdown =
    'docs/baselines/source_estimation_split_blocker_queue.generated.md';

void main(List<String> args) {
  final inputPath = _argument(args, '--input') ?? _defaultReadinessReport;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _BlockerQueueReport.build(File(inputPath));

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-estimation split blocker queue report');
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

class _BlockerQueueReport {
  final String readinessReportPath;
  final String readinessStatus;
  final List<_BlockerCase> blockers;
  final List<_BlockerCase> completed;
  final List<String> errors;
  final List<String> warnings;

  const _BlockerQueueReport({
    required this.readinessReportPath,
    required this.readinessStatus,
    required this.blockers,
    required this.completed,
    required this.errors,
    required this.warnings,
  });

  factory _BlockerQueueReport.build(File readinessReport) {
    final errors = <String>[];
    final warnings = <String>[];
    if (!readinessReport.existsSync()) {
      errors.add('readiness_report_missing:${readinessReport.path}');
      return _BlockerQueueReport(
        readinessReportPath: readinessReport.path,
        readinessStatus: 'missing',
        blockers: const [],
        completed: const [],
        errors: errors,
        warnings: warnings,
      );
    }

    final decoded =
        jsonDecode(readinessReport.readAsStringSync()) as Map<String, Object?>;
    final status = decoded['status']?.toString() ?? 'unknown';
    if (status != 'pass') {
      errors.add('readiness_report_not_pass:$status');
    }

    final blockers = <_BlockerCase>[];
    final completed = <_BlockerCase>[];
    for (final rawCase in _list(decoded['cases'])) {
      final item = _BlockerCase.fromJson(_map(rawCase));
      if (item.nextAction == 'split_assignment_complete') {
        completed.add(item);
      } else {
        blockers.add(item);
      }
    }
    blockers.sort(_compareBlockers);
    completed.sort((left, right) => left.caseId.compareTo(right.caseId));

    if (blockers.any((entry) => entry.readyForManualSplitAssignment)) {
      warnings.add('manual_ready_cases_still_unassigned');
    }
    if (blockers.any((entry) => entry.readyForFrozenSplit)) {
      warnings.add('ready_cases_still_blocked');
    }

    return _BlockerQueueReport(
      readinessReportPath: readinessReport.path,
      readinessStatus: status,
      blockers: blockers,
      completed: completed,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final byAction = <String, int>{};
    for (final blocker in blockers) {
      byAction[blocker.nextAction] = (byAction[blocker.nextAction] ?? 0) + 1;
    }
    return {
      'schemaVersion': 'source_estimation_split_blocker_queue_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'readinessReportPath': readinessReportPath,
      'readinessStatus': readinessStatus,
      'summary': {
        'blockedCaseCount': blockers.length,
        'completedSplitAssignmentCount': completed.length,
        'readyForManualSplitAssignmentCount': blockers
            .where((entry) => entry.readyForManualSplitAssignment)
            .length,
        'readyForFrozenSplitButBlockedCount': blockers
            .where((entry) => entry.readyForFrozenSplit)
            .length,
        'nextActionCounts': byAction,
      },
      'errors': errors,
      'warnings': warnings,
      'actionGuidance': {
        for (final action in byAction.keys.toList()..sort())
          action: _guidance(action),
      },
      'completedSplitAssignments': completed
          .map((entry) => entry.toJson())
          .toList(),
      'blockers': blockers.map((entry) => entry.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = json['summary'] as Map<String, Object?>;
    final nextActionCounts = (summary['nextActionCounts'] as Map)
        .cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Source Estimation Split Blocker Queue')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Readiness report: `$readinessReportPath`')
      ..writeln('- Readiness status: `$readinessStatus`')
      ..writeln('- Blocked cases: `${summary['blockedCaseCount']}`')
      ..writeln(
        '- Completed split assignments: '
        '`${summary['completedSplitAssignmentCount']}`',
      )
      ..writeln(
        '- Manual-ready blocked cases: '
        '`${summary['readyForManualSplitAssignmentCount']}`',
      )
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
      ..writeln('## Next Action Counts')
      ..writeln()
      ..writeln('| Next action | Count | Guidance |')
      ..writeln('| --- | ---: | --- |');
    for (final action in nextActionCounts.keys.toList()..sort()) {
      buffer.writeln(
        '| `$action` | ${nextActionCounts[action]} | ${_guidance(action)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Blocked Cases')
      ..writeln()
      ..writeln(
        '| Case | Planned use | Split | Next action | Pending conditions | Guidance |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final blocker in blockers) {
      buffer.writeln(
        '| `${blocker.caseId}` | `${blocker.plannedUse}` | '
        '`${blocker.splitStatus}` | `${blocker.nextAction}` | '
        '`${blocker.pendingConditionNames.join('`, `')}` | '
        '${_guidance(blocker.nextAction)} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Completed Split Assignments')
      ..writeln()
      ..writeln('| Case | Split | Constraints |')
      ..writeln('| --- | --- | --- |');
    for (final item in completed) {
      buffer.writeln(
        '| `${item.caseId}` | `${item.splitStatus}` | '
        '`${item.manualSplitConstraints.join('`, `')}` |',
      );
    }
    return buffer.toString();
  }
}

class _BlockerCase {
  final String caseId;
  final String plannedUse;
  final String splitStatus;
  final bool readyForFrozenSplit;
  final bool readyForManualSplitAssignment;
  final String nextAction;
  final List<String> manualSplitConstraints;
  final List<_Condition> conditions;

  const _BlockerCase({
    required this.caseId,
    required this.plannedUse,
    required this.splitStatus,
    required this.readyForFrozenSplit,
    required this.readyForManualSplitAssignment,
    required this.nextAction,
    required this.manualSplitConstraints,
    required this.conditions,
  });

  factory _BlockerCase.fromJson(Map<String, Object?> json) {
    final recommendation = _map(json['manualSplitRecommendation']);
    return _BlockerCase(
      caseId: json['caseId']?.toString() ?? '',
      plannedUse: json['plannedUse']?.toString() ?? '',
      splitStatus: json['splitStatus']?.toString() ?? '',
      readyForFrozenSplit: json['readyForFrozenSplit'] == true,
      readyForManualSplitAssignment:
          json['readyForManualSplitAssignment'] == true,
      nextAction: json['nextAction']?.toString() ?? '',
      manualSplitConstraints: _list(
        recommendation['constraints'],
      ).map((entry) => entry.toString()).toList(growable: false),
      conditions: _list(json['conditions'])
          .map((entry) => _Condition.fromJson(_map(entry)))
          .toList(growable: false),
    );
  }

  List<String> get pendingConditionNames => [
    for (final condition in conditions)
      if (condition.status != 'complete') condition.name,
  ];

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'plannedUse': plannedUse,
    'splitStatus': splitStatus,
    'readyForFrozenSplit': readyForFrozenSplit,
    'readyForManualSplitAssignment': readyForManualSplitAssignment,
    'nextAction': nextAction,
    'manualSplitConstraints': manualSplitConstraints,
    'pendingConditions': [
      for (final condition in conditions)
        if (condition.status != 'complete') condition.toJson(),
    ],
  };
}

class _Condition {
  final String name;
  final String status;
  final String reason;

  const _Condition({
    required this.name,
    required this.status,
    required this.reason,
  });

  factory _Condition.fromJson(Map<String, Object?> json) => _Condition(
    name: json['name']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    reason: json['reason']?.toString() ?? '',
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'status': status,
    'reason': reason,
  };
}

int _compareBlockers(_BlockerCase left, _BlockerCase right) {
  final action = _actionPriority(
    left.nextAction,
  ).compareTo(_actionPriority(right.nextAction));
  if (action != 0) return action;
  return left.caseId.compareTo(right.caseId);
}

int _actionPriority(String action) {
  switch (action) {
    case 'review_jma_catalog_link':
      return 10;
    case 'review_hinet_preliminary_truth_quality':
    case 'review_hinet_truth_quality':
      return 20;
    case 'link_final_catalog_or_hinet_revision':
      return 30;
    case 'review_source_trigger_threshold_effect':
      return 40;
    case 'keep_candidate_region_false_recovery_diagnostic_only':
      return 45;
    case 'assign_event_level_split':
      return 50;
    default:
      return 90;
  }
}

String _guidance(String action) {
  switch (action) {
    case 'review_jma_catalog_link':
      return 'Link a versioned JMA final catalog record before split assignment.';
    case 'review_hinet_preliminary_truth_quality':
    case 'review_hinet_truth_quality':
      return 'Manually review Hi-net preliminary truth quality before assignment.';
    case 'link_final_catalog_or_hinet_revision':
      return 'Link a final catalog or revised Hi-net source before assignment.';
    case 'review_source_trigger_threshold_effect':
      return 'Review trigger-threshold effects and capture provenance first.';
    case 'keep_candidate_region_false_recovery_diagnostic_only':
      return 'Keep the false-recovery guard diagnostic-only until an explicit split gate approves promotion.';
    case 'assign_event_level_split':
      return 'Assign an event-level split only after all non-split blockers pass.';
    default:
      return 'Inspect the readiness report for the required evidence.';
  }
}

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};
