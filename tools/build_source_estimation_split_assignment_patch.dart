import 'dart:convert';
import 'dart:io';

const _defaultSplitManifest =
    'test/fixtures/source_estimation/dataset_splits.json';
const _defaultPlanPath =
    'docs/data/source_estimation_split_assignment_plan.json';
const _defaultFixtureDirectory = 'test/fixtures/source_estimation';
const _defaultOutputPath =
    '.dart_tool/source_estimation_split_assignment_patch/report.json';
const _defaultMarkdownPath =
    'docs/baselines/source_estimation_split_assignment_patch.generated.md';
const _validSplits = {'train', 'validation', 'test'};

void main(List<String> args) {
  final splitManifestPath = _argument(args, '--split') ?? _defaultSplitManifest;
  final planPath = _argument(args, '--plan') ?? _defaultPlanPath;
  final fixtureDirectory =
      _argument(args, '--fixture-directory') ?? _defaultFixtureDirectory;
  final outputPath = _argument(args, '--output') ?? _defaultOutputPath;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdownPath;
  final apply = args.contains('--apply');

  final report = _PatchReport.build(
    splitManifestFile: File(splitManifestPath),
    planFile: File(planPath),
    fixtureDirectory: Directory(fixtureDirectory),
    applyRequested: apply,
  );

  if (apply && report.errors.isEmpty) {
    report.apply();
  }

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-estimation split assignment patch report');
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

class _PatchReport {
  final File splitManifestFile;
  final File planFile;
  final Directory fixtureDirectory;
  final bool applyRequested;
  final Map<String, Object?> splitManifest;
  final List<_Proposal> proposals;
  final List<String> errors;
  final List<String> warnings;

  const _PatchReport({
    required this.splitManifestFile,
    required this.planFile,
    required this.fixtureDirectory,
    required this.applyRequested,
    required this.splitManifest,
    required this.proposals,
    required this.errors,
    required this.warnings,
  });

  factory _PatchReport.build({
    required File splitManifestFile,
    required File planFile,
    required Directory fixtureDirectory,
    required bool applyRequested,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    if (!splitManifestFile.existsSync()) {
      errors.add('split_manifest_missing:${splitManifestFile.path}');
      return _empty(
        splitManifestFile: splitManifestFile,
        planFile: planFile,
        fixtureDirectory: fixtureDirectory,
        applyRequested: applyRequested,
        errors: errors,
        warnings: warnings,
      );
    }
    if (!planFile.existsSync()) {
      errors.add('split_assignment_plan_missing:${planFile.path}');
      return _empty(
        splitManifestFile: splitManifestFile,
        planFile: planFile,
        fixtureDirectory: fixtureDirectory,
        applyRequested: applyRequested,
        errors: errors,
        warnings: warnings,
      );
    }

    final splitManifest =
        jsonDecode(splitManifestFile.readAsStringSync())
            as Map<String, Object?>;
    final plan =
        jsonDecode(planFile.readAsStringSync()) as Map<String, Object?>;
    final fixtures = _readFixtures(fixtureDirectory, errors);
    final splitByFile = _splitByFile(splitManifest);
    final proposals = <_Proposal>[];
    for (final rawCase in _list(plan['cases'])) {
      final planCase = _map(rawCase);
      final recommendation = _map(planCase['manualSplitRecommendation']);
      if (recommendation.isEmpty) continue;
      final caseId = planCase['caseId']?.toString() ?? '';
      final suggestedSplit = recommendation['suggestedSplit']?.toString() ?? '';
      final fixture = fixtures[caseId];
      final violations = <String>[];
      if (caseId.isEmpty) violations.add('missing_case_id');
      if (!_validSplits.contains(suggestedSplit)) {
        violations.add('invalid_suggested_split:$suggestedSplit');
      }
      if (fixture == null) {
        violations.add('fixture_missing:$caseId');
      }
      if (suggestedSplit == 'test' &&
          _strings(
            recommendation['constraints'],
          ).contains('do_not_use_for_final_test_claims')) {
        violations.add('test_split_conflicts_with_final_claim_constraint');
      }

      final existingSplit = fixture == null ? null : splitByFile[fixture.name];
      if (existingSplit != null && existingSplit != suggestedSplit) {
        violations.add('fixture_already_in_other_split:$existingSplit');
      }

      final status = violations.isNotEmpty
          ? 'blocked'
          : existingSplit == suggestedSplit
          ? 'already_applied'
          : 'ready_to_apply';
      proposals.add(
        _Proposal(
          caseId: caseId,
          fixtureFileName: fixture?.name,
          fixturePath: fixture?.file.path,
          suggestedSplit: suggestedSplit,
          proposedFixtureSplitStatus: '${suggestedSplit}_reference',
          reason: recommendation['reason']?.toString() ?? '',
          constraints: _strings(recommendation['constraints']),
          existingSplit: existingSplit,
          status: status,
          violations: violations,
        ),
      );
    }

    for (final proposal in proposals) {
      if (proposal.status == 'blocked') {
        warnings.add('blocked_split_recommendation:${proposal.caseId}');
      }
    }

    return _PatchReport(
      splitManifestFile: splitManifestFile,
      planFile: planFile,
      fixtureDirectory: fixtureDirectory,
      applyRequested: applyRequested,
      splitManifest: splitManifest,
      proposals: proposals,
      errors: errors,
      warnings: warnings,
    );
  }

  static _PatchReport _empty({
    required File splitManifestFile,
    required File planFile,
    required Directory fixtureDirectory,
    required bool applyRequested,
    required List<String> errors,
    required List<String> warnings,
  }) {
    return _PatchReport(
      splitManifestFile: splitManifestFile,
      planFile: planFile,
      fixtureDirectory: fixtureDirectory,
      applyRequested: applyRequested,
      splitManifest: const {},
      proposals: const [],
      errors: errors,
      warnings: warnings,
    );
  }

  bool get passed => errors.isEmpty;

  void apply() {
    final splitManifestCopy =
        jsonDecode(jsonEncode(splitManifest)) as Map<String, Object?>;
    final rawSplits = _map(splitManifestCopy['splits']);
    for (final proposal in proposals.where(
      (proposal) => proposal.status == 'ready_to_apply',
    )) {
      final fixtureFileName = proposal.fixtureFileName;
      final fixturePath = proposal.fixturePath;
      if (fixtureFileName == null || fixturePath == null) continue;
      final splitEntries = _list(
        rawSplits[proposal.suggestedSplit],
      ).map((entry) => entry.toString()).toList();
      if (!splitEntries.contains(fixtureFileName)) {
        splitEntries.add(fixtureFileName);
      }
      rawSplits[proposal.suggestedSplit] = splitEntries;

      final fixtureFile = File(fixturePath);
      final fixture =
          jsonDecode(fixtureFile.readAsStringSync()) as Map<String, Object?>;
      fixture['splitStatus'] = proposal.proposedFixtureSplitStatus;
      fixtureFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(fixture)}\n',
      );
    }
    splitManifestCopy['splits'] = rawSplits;
    splitManifestFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(splitManifestCopy)}\n',
    );
  }

  Map<String, Object?> toJson() {
    final statusCounts = <String, int>{};
    for (final proposal in proposals) {
      statusCounts[proposal.status] = (statusCounts[proposal.status] ?? 0) + 1;
    }
    return {
      'schemaVersion': 'source_estimation_split_assignment_patch_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': passed ? 'pass' : 'fail',
      'applyRequested': applyRequested,
      'splitManifestPath': splitManifestFile.path,
      'planPath': planFile.path,
      'fixtureDirectory': fixtureDirectory.path,
      'summary': {
        'proposalCount': proposals.length,
        'readyToApplyCount': proposals
            .where((proposal) => proposal.status == 'ready_to_apply')
            .length,
        'alreadyAppliedCount': proposals
            .where((proposal) => proposal.status == 'already_applied')
            .length,
        'blockedCount': proposals
            .where((proposal) => proposal.status == 'blocked')
            .length,
        'statusCounts': statusCounts,
      },
      'errors': errors,
      'warnings': warnings,
      'proposals': proposals.map((proposal) => proposal.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = json['summary'] as Map<String, Object?>;
    final buffer = StringBuffer()
      ..writeln('# Source Estimation Split Assignment Patch')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Apply requested: `$applyRequested`')
      ..writeln('- Split manifest: `${splitManifestFile.path}`')
      ..writeln('- Plan: `${planFile.path}`')
      ..writeln('- Proposals: `${summary['proposalCount']}`')
      ..writeln('- Ready to apply: `${summary['readyToApplyCount']}`')
      ..writeln('- Already applied: `${summary['alreadyAppliedCount']}`')
      ..writeln('- Blocked: `${summary['blockedCount']}`')
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
      ..writeln('## Proposals')
      ..writeln()
      ..writeln(
        '| Case | Status | Suggested split | Fixture splitStatus | Reason | Actions |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- |');
    for (final proposal in proposals) {
      buffer.writeln(
        '| `${proposal.caseId}` | `${proposal.status}` | '
        '`${proposal.suggestedSplit}` | '
        '`${proposal.proposedFixtureSplitStatus}` | `${proposal.reason}` | '
        '`${proposal.actions.join('`, `')}` |',
      );
    }
    return buffer.toString();
  }
}

class _Proposal {
  final String caseId;
  final String? fixtureFileName;
  final String? fixturePath;
  final String suggestedSplit;
  final String proposedFixtureSplitStatus;
  final String reason;
  final List<String> constraints;
  final String? existingSplit;
  final String status;
  final List<String> violations;

  const _Proposal({
    required this.caseId,
    required this.fixtureFileName,
    required this.fixturePath,
    required this.suggestedSplit,
    required this.proposedFixtureSplitStatus,
    required this.reason,
    required this.constraints,
    required this.existingSplit,
    required this.status,
    required this.violations,
  });

  List<String> get actions {
    if (status != 'ready_to_apply') return const [];
    return const [
      'add_fixture_to_split_manifest',
      'update_fixture_split_status',
    ];
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'fixtureFileName': fixtureFileName,
    'fixturePath': fixturePath,
    'suggestedSplit': suggestedSplit,
    'proposedFixtureSplitStatus': proposedFixtureSplitStatus,
    'reason': reason,
    'constraints': constraints,
    'existingSplit': existingSplit,
    'status': status,
    'violations': violations,
    'actions': actions,
  };
}

class _FixtureEntry {
  final File file;
  final String name;

  const _FixtureEntry({required this.file, required this.name});
}

Map<String, _FixtureEntry> _readFixtures(
  Directory directory,
  List<String> errors,
) {
  final result = <String, _FixtureEntry>{};
  if (!directory.existsSync()) {
    errors.add('fixture_directory_missing:${directory.path}');
    return result;
  }
  for (final file in directory.listSync().whereType<File>()) {
    if (!file.path.toLowerCase().endsWith('.json')) continue;
    final name = file.uri.pathSegments.last;
    if (name == 'dataset_splits.json') continue;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final caseId = json['caseId']?.toString();
      if (caseId == null || caseId.isEmpty) continue;
      result[caseId] = _FixtureEntry(file: file, name: name);
    } catch (_) {
      continue;
    }
  }
  return result;
}

Map<String, String> _splitByFile(Map<String, Object?> splitManifest) {
  final result = <String, String>{};
  for (final entry in _map(splitManifest['splits']).entries) {
    for (final rawFile in _list(entry.value)) {
      result[rawFile.toString()] = entry.key;
    }
  }
  return result;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _list(Object? value) {
  if (value is List) return value.cast<Object?>();
  return const [];
}

List<String> _strings(Object? value) =>
    _list(value).map((entry) => entry.toString()).toList(growable: false);
