import 'dart:convert';
import 'dart:io';

const _defaultReadinessReport =
    '.dart_tool/source_estimation_split_assignment_readiness/report.json';
const _defaultDecisionPath =
    'docs/data/hinet_truth_quality_review_decisions.json';
const _defaultOutput = '.dart_tool/hinet_truth_quality_review/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_truth_quality_review.generated.md';

void main(List<String> args) {
  final readinessPath =
      _argument(args, '--readiness') ?? _defaultReadinessReport;
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _HinetTruthQualityReviewReport.build(
    readinessReport: File(readinessPath),
    decisionFile: File(decisionPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote Hi-net truth-quality review report');
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

class _HinetTruthQualityReviewReport {
  final String readinessReportPath;
  final String decisionPath;
  final String readinessStatus;
  final List<_HinetReviewCase> cases;
  final List<String> errors;
  final List<String> warnings;

  const _HinetTruthQualityReviewReport({
    required this.readinessReportPath,
    required this.decisionPath,
    required this.readinessStatus,
    required this.cases,
    required this.errors,
    required this.warnings,
  });

  factory _HinetTruthQualityReviewReport.build({
    required File readinessReport,
    required File decisionFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    var readinessStatus = 'missing';
    final cases = <_HinetReviewCase>[];
    final decisions = _HinetReviewDecisions.read(decisionFile, errors);

    if (!readinessReport.existsSync()) {
      errors.add('readiness_report_missing:${readinessReport.path}');
    } else {
      final readiness =
          jsonDecode(readinessReport.readAsStringSync())
              as Map<String, Object?>;
      readinessStatus = readiness['status']?.toString() ?? 'unknown';
      if (readinessStatus != 'pass') {
        errors.add('readiness_report_not_pass:$readinessStatus');
      }
      for (final rawCase in _list(readiness['cases'])) {
        final readinessCase = _map(rawCase);
        final hinetReviewConditions = _list(readinessCase['conditions'])
            .map((entry) => _map(entry))
            .where(
              (condition) => {
                'review_hinet_preliminary_truth_quality',
                'review_hinet_truth_quality',
              }.contains(condition['name']),
            )
            .toList(growable: false);
        if (hinetReviewConditions.isEmpty) continue;
        cases.add(
          _HinetReviewCase.fromReadinessCase(
            readinessCase,
            hinetReviewConditions,
            decisions.byCaseId[readinessCase['caseId']?.toString() ?? ''],
            errors,
          ),
        );
      }
    }

    final reviewCaseIds = cases.map((item) => item.caseId).toSet();
    for (final decisionCaseId in decisions.byCaseId.keys) {
      if (!reviewCaseIds.contains(decisionCaseId)) {
        warnings.add('hinet_review_decision_not_in_queue:$decisionCaseId');
      }
    }

    cases.sort((left, right) => left.caseId.compareTo(right.caseId));

    return _HinetTruthQualityReviewReport(
      readinessReportPath: readinessReport.path,
      decisionPath: decisionFile.path,
      readinessStatus: readinessStatus,
      cases: cases,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() {
    final reviewFlagCounts = <String, int>{};
    final blockingEvidenceTypeCounts = <String, int>{};
    for (final item in cases) {
      for (final flag in item.reviewFlags) {
        reviewFlagCounts[flag] = (reviewFlagCounts[flag] ?? 0) + 1;
      }
      for (final evidence in item.blockingEvidence) {
        blockingEvidenceTypeCounts[evidence.type] =
            (blockingEvidenceTypeCounts[evidence.type] ?? 0) + 1;
      }
    }
    return {
      'schemaVersion': 'hinet_truth_quality_review_v1',
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'status': errors.isEmpty ? 'pass' : 'fail',
      'readinessReportPath': readinessReportPath,
      'decisionPath': decisionPath,
      'readinessStatus': readinessStatus,
      'summary': {
        'hinetReviewCaseCount': cases.length,
        'decisionCaseCount': cases
            .where((item) => item.decisionStatus != 'missing_decision')
            .length,
        'pendingDecisionCount': cases
            .where((item) => item.decisionStatus == 'pending_manual_review')
            .length,
        'acceptedForConstrainedReferenceSplitCount': cases
            .where((item) => item.acceptedForConstrainedReferenceSplit)
            .length,
        'blockingEvidenceCaseCount': cases
            .where((item) => item.blockingEvidence.isNotEmpty)
            .length,
        'blockingEvidenceCount': cases.fold<int>(
          0,
          (total, item) => total + item.blockingEvidence.length,
        ),
        'captureDirectoryExistsCount': cases
            .where((item) => item.captureDirectoryExists)
            .length,
        'captureManifestExistsCount': cases
            .where((item) => item.captureManifestExists)
            .length,
        'captureProvenanceCompleteCount': cases
            .where((item) => item.captureProvenanceComplete)
            .length,
        'captureManifestFailureCount': cases
            .where((item) => !item.captureProvenanceComplete)
            .length,
        'referenceIsolatedCount': cases
            .where((item) => item.referenceIsolated)
            .length,
        'catalogTruthFlagMismatchCount': cases
            .where((item) => item.catalogTruthFlagMismatch)
            .length,
        'manualReviewReadyCount': cases
            .where((item) => item.manualReviewReady)
            .length,
        'reviewFlagCounts': reviewFlagCounts,
        'blockingEvidenceTypeCounts': blockingEvidenceTypeCounts,
      },
      'errors': errors,
      'warnings': warnings,
      'cases': cases.map((item) => item.toJson()).toList(),
    };
  }

  String toMarkdown() {
    final json = toJson();
    final summary = json['summary'] as Map<String, Object?>;
    final flagCounts = (summary['reviewFlagCounts'] as Map)
        .cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Truth-Quality Review')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Readiness report: `$readinessReportPath`')
      ..writeln('- Decision file: `$decisionPath`')
      ..writeln('- Readiness status: `$readinessStatus`')
      ..writeln('- Hi-net review cases: `${summary['hinetReviewCaseCount']}`')
      ..writeln('- Decision cases: `${summary['decisionCaseCount']}`')
      ..writeln('- Pending decisions: `${summary['pendingDecisionCount']}`')
      ..writeln(
        '- Accepted constrained references: '
        '`${summary['acceptedForConstrainedReferenceSplitCount']}`',
      )
      ..writeln(
        '- Blocking-evidence cases: '
        '`${summary['blockingEvidenceCaseCount']}`',
      )
      ..writeln(
        '- Blocking-evidence entries: `${summary['blockingEvidenceCount']}`',
      )
      ..writeln(
        '- Capture directories present: '
        '`${summary['captureDirectoryExistsCount']}`',
      )
      ..writeln(
        '- Capture manifests present: '
        '`${summary['captureManifestExistsCount']}`',
      )
      ..writeln(
        '- Capture provenance complete: '
        '`${summary['captureProvenanceCompleteCount']}`',
      )
      ..writeln(
        '- Capture manifest failures: '
        '`${summary['captureManifestFailureCount']}`',
      )
      ..writeln(
        '- Reference-isolated cases: `${summary['referenceIsolatedCount']}`',
      )
      ..writeln(
        '- Catalog truth flag mismatches: '
        '`${summary['catalogTruthFlagMismatchCount']}`',
      )
      ..writeln(
        '- Manual review ready cases: `${summary['manualReviewReadyCount']}`',
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
      ..writeln('## Review Flag Counts')
      ..writeln()
      ..writeln('| Flag | Count |')
      ..writeln('| --- | ---: |');
    for (final flag in flagCounts.keys.toList()..sort()) {
      buffer.writeln('| `$flag` | ${flagCounts[flag]} |');
    }
    final blockingEvidenceCounts =
        (summary['blockingEvidenceTypeCounts'] as Map).cast<String, Object?>();
    buffer
      ..writeln()
      ..writeln('## Blocking Evidence Counts')
      ..writeln()
      ..writeln('| Type | Count |')
      ..writeln('| --- | ---: |');
    for (final type in blockingEvidenceCounts.keys.toList()..sort()) {
      buffer.writeln('| `$type` | ${blockingEvidenceCounts[type]} |');
    }

    buffer
      ..writeln()
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Case | Requirement | Decision | Accepted | Blocking evidence | Truth source | Truth quality | Catalog flag | Capture | Capture complete | Isolated | Flags |',
      )
      ..writeln(
        '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
      );
    for (final item in cases) {
      buffer.writeln(
        '| `${item.caseId}` | `${item.requirements.join('`, `')}` | '
        '`${item.decisionStatus}` | '
        '${item.acceptedForConstrainedReferenceSplit ? 'yes' : 'no'} | '
        '`${item.blockingEvidence.map((evidence) => evidence.type).join('`, `')}` | '
        '`${item.truthSource}` | `${item.truthQuality}` | '
        '${item.catalogTruthVerified ? 'true' : 'false'} | '
        '${item.captureDirectoryExists ? 'yes' : 'no'} '
        '(${item.captureFileCount} files, '
        '${item.captureDownloadedGifCount}/${item.captureExpectedGifCount} GIFs, '
        '${item.captureFailedGifCount} failed) | '
        '${item.captureProvenanceComplete ? 'yes' : 'no'} | '
        '${item.referenceIsolated ? 'yes' : 'no'} | '
        '`${item.reviewFlags.join('`, `')}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln(
        '- Hi-net user-provided or automatic hypocenter labels stay '
        'reference-only until a manual truth-quality review links a revised '
        'Hi-net/JMA source or explicitly accepts the case for a constrained '
        'reference split.',
      )
      ..writeln(
        '- `catalogTruthVerified=true` on a Hi-net preliminary/user-provided '
        'source is treated as a review flag, not as final catalog evidence.',
      )
      ..writeln(
        '- Pending decisions in `docs/data/hinet_truth_quality_review_decisions.json` '
        'do not clear blockers. A case can clear Hi-net review only after an '
        'explicit accepted decision records reviewer/evidence metadata.',
      );
    return buffer.toString();
  }
}

class _HinetReviewDecisions {
  final Map<String, _HinetReviewDecision> byCaseId;

  const _HinetReviewDecisions({required this.byCaseId});

  factory _HinetReviewDecisions.read(File file, List<String> errors) {
    if (!file.existsSync()) {
      errors.add('hinet_review_decision_file_missing:${file.path}');
      return const _HinetReviewDecisions(byCaseId: {});
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (json['schemaVersion'] != 'hinet_truth_quality_review_decisions_v1') {
      errors.add('hinet_review_decision_schema_invalid');
    }
    final decisions = <String, _HinetReviewDecision>{};
    for (final rawCase in _list(json['cases'])) {
      final data = _map(rawCase);
      final caseId = data['caseId']?.toString() ?? '';
      if (caseId.isEmpty) {
        errors.add('hinet_review_decision_case_missing_case_id');
        continue;
      }
      if (decisions.containsKey(caseId)) {
        errors.add('hinet_review_decision_duplicate_case:$caseId');
        continue;
      }
      final decision = _HinetReviewDecision.fromJson(data);
      if (decision.acceptedForConstrainedReferenceSplit &&
          decision.decisionStatus != 'accepted_constrained_reference') {
        errors.add('hinet_review_decision_acceptance_status_mismatch:$caseId');
      }
      if (decision.acceptedForConstrainedReferenceSplit &&
          (decision.reviewer == null ||
              decision.reviewedAtUtc == null ||
              decision.evidence.isEmpty)) {
        errors.add('hinet_review_decision_acceptance_evidence_missing:$caseId');
      }
      if (decision.acceptedForConstrainedReferenceSplit &&
          decision.blockingEvidence.isNotEmpty) {
        errors.add('hinet_review_decision_has_blocking_evidence:$caseId');
      }
      for (final evidence in decision.blockingEvidence) {
        if (evidence.type.isEmpty) {
          errors.add('hinet_review_blocking_evidence_missing_type:$caseId');
        }
        if (evidence.checkedAtUtc == null ||
            DateTime.tryParse(evidence.checkedAtUtc!) == null) {
          errors.add('hinet_review_blocking_evidence_invalid_time:$caseId');
        }
        if (evidence.type == 'capture_repair_attempt') {
          if (evidence.url == null || evidence.url!.isEmpty) {
            errors.add(
              'hinet_review_capture_repair_evidence_missing_url:$caseId',
            );
          }
          if (evidence.result == null || evidence.result!.isEmpty) {
            errors.add(
              'hinet_review_capture_repair_evidence_missing_result:$caseId',
            );
          }
          if (evidence.affectedFile == null || evidence.affectedFile!.isEmpty) {
            errors.add(
              'hinet_review_capture_repair_evidence_missing_file:$caseId',
            );
          }
        }
      }
      decisions[caseId] = decision;
    }
    return _HinetReviewDecisions(byCaseId: decisions);
  }
}

class _HinetReviewDecision {
  final String decisionStatus;
  final bool acceptedForConstrainedReferenceSplit;
  final String? reviewedAtUtc;
  final String? reviewer;
  final List<String> evidence;
  final List<_BlockingEvidence> blockingEvidence;
  final List<String> requiredActions;

  const _HinetReviewDecision({
    required this.decisionStatus,
    required this.acceptedForConstrainedReferenceSplit,
    required this.reviewedAtUtc,
    required this.reviewer,
    required this.evidence,
    required this.blockingEvidence,
    required this.requiredActions,
  });

  factory _HinetReviewDecision.fromJson(Map<String, Object?> json) {
    return _HinetReviewDecision(
      decisionStatus: json['decisionStatus']?.toString() ?? 'missing_decision',
      acceptedForConstrainedReferenceSplit:
          json['acceptedForConstrainedReferenceSplit'] == true,
      reviewedAtUtc: json['reviewedAtUtc']?.toString(),
      reviewer: json['reviewer']?.toString(),
      evidence: _list(
        json['evidence'],
      ).map((entry) => entry.toString()).toList(growable: false),
      blockingEvidence: _list(json['blockingEvidence'])
          .map((entry) => _BlockingEvidence.fromJson(_map(entry)))
          .toList(growable: false),
      requiredActions: _list(
        json['requiredActions'],
      ).map((entry) => entry.toString()).toList(growable: false),
    );
  }
}

class _BlockingEvidence {
  final String type;
  final String? checkedAtUtc;
  final String? url;
  final String? result;
  final String? affectedFile;

  const _BlockingEvidence({
    required this.type,
    required this.checkedAtUtc,
    required this.url,
    required this.result,
    required this.affectedFile,
  });

  factory _BlockingEvidence.fromJson(Map<String, Object?> json) {
    return _BlockingEvidence(
      type: json['type']?.toString() ?? '',
      checkedAtUtc: json['checkedAtUtc']?.toString(),
      url: json['url']?.toString(),
      result: json['result']?.toString(),
      affectedFile: json['affectedFile']?.toString(),
    );
  }

  Map<String, Object?> toJson() => {
    'type': type,
    'checkedAtUtc': checkedAtUtc,
    'url': url,
    'result': result,
    'affectedFile': affectedFile,
  };
}

class _HinetReviewCase {
  final String caseId;
  final List<String> requirements;
  final String fixturePath;
  final String truthSource;
  final String truthQuality;
  final String decisionStatus;
  final bool acceptedForConstrainedReferenceSplit;
  final List<String> decisionRequiredActions;
  final List<_BlockingEvidence> blockingEvidence;
  final bool catalogTruthVerified;
  final bool includeInDetectionMetrics;
  final String splitStatus;
  final String? captureDirectory;
  final bool captureDirectoryExists;
  final int captureFileCount;
  final String? captureManifestPath;
  final bool captureManifestExists;
  final int? captureExpectedGifCount;
  final int? captureDownloadedGifCount;
  final int? captureFailedGifCount;
  final int? captureMissingFrameCount;
  final String? captureReceivedAtStatus;
  final bool captureProvenanceComplete;
  final bool referenceIsolated;
  final bool catalogTruthFlagMismatch;
  final bool manualReviewReady;
  final List<String> reviewFlags;

  const _HinetReviewCase({
    required this.caseId,
    required this.requirements,
    required this.fixturePath,
    required this.truthSource,
    required this.truthQuality,
    required this.decisionStatus,
    required this.acceptedForConstrainedReferenceSplit,
    required this.decisionRequiredActions,
    required this.blockingEvidence,
    required this.catalogTruthVerified,
    required this.includeInDetectionMetrics,
    required this.splitStatus,
    required this.captureDirectory,
    required this.captureDirectoryExists,
    required this.captureFileCount,
    required this.captureManifestPath,
    required this.captureManifestExists,
    required this.captureExpectedGifCount,
    required this.captureDownloadedGifCount,
    required this.captureFailedGifCount,
    required this.captureMissingFrameCount,
    required this.captureReceivedAtStatus,
    required this.captureProvenanceComplete,
    required this.referenceIsolated,
    required this.catalogTruthFlagMismatch,
    required this.manualReviewReady,
    required this.reviewFlags,
  });

  factory _HinetReviewCase.fromReadinessCase(
    Map<String, Object?> readinessCase,
    List<Map<String, Object?>> hinetReviewConditions,
    _HinetReviewDecision? decision,
    List<String> errors,
  ) {
    final fixturePath = readinessCase['fixturePath']?.toString() ?? '';
    final fixture = _readFixture(fixturePath, errors);
    final truth = _map(fixture?['truth']);
    final labels = _map(fixture?['eventLabels']);
    final classification = _map(fixture?['classification']);
    final splitStatus = fixture?['splitStatus']?.toString() ?? '';
    final captureDirectory = fixture?['captureDirectory']?.toString();
    final captureDir = captureDirectory == null
        ? null
        : Directory(captureDirectory);
    final captureDirectoryExists = captureDir?.existsSync() ?? false;
    final captureFileCount = captureDirectoryExists
        ? captureDir!.listSync(recursive: true).whereType<File>().length
        : 0;
    final captureProvenance = _CaptureProvenance.fromDirectory(captureDir);
    final truthSource = truth['source']?.toString() ?? '';
    final truthQuality = classification['truthQuality']?.toString() ?? '';
    final catalogTruthVerified = labels['catalogTruthVerified'] == true;
    final includeInDetectionMetrics =
        labels['includeInDetectionMetrics'] == true;
    final referenceIsolated =
        !includeInDetectionMetrics && splitStatus == 'unassigned_reference';
    final catalogTruthFlagMismatch =
        catalogTruthVerified && truthSource.toLowerCase().contains('hinet');
    final reviewFlags = <String>[
      if (decision == null) 'review_decision_missing',
      if (decision?.decisionStatus == 'pending_manual_review')
        'review_decision_pending',
      if (catalogTruthFlagMismatch) 'catalog_truth_verified_flag_mismatch',
      if (!referenceIsolated) 'not_isolated_from_frozen_metrics',
      if (!captureDirectoryExists) 'capture_directory_missing',
      if (!captureProvenance.manifestExists) 'capture_manifest_missing',
      if (captureProvenance.failedGifCount != null &&
          captureProvenance.failedGifCount! > 0)
        'capture_manifest_has_failed_gifs',
      if (captureProvenance.missingFrameCount != null &&
          captureProvenance.missingFrameCount! > 0)
        'capture_manifest_has_missing_frames',
      if (!captureProvenance.complete) 'capture_provenance_incomplete',
      if (!truthQuality.toLowerCase().contains('hinet'))
        'truth_quality_label_missing_hinet',
      if (truthSource == 'hinet_hypocenter_information')
        'hinet_information_without_user_provided_marker',
      if (truthQuality.toLowerCase().contains('preliminary')) 'preliminary',
      if (truthQuality == 'hinet_user_provided')
        'user_provided_not_preliminary',
    ];

    return _HinetReviewCase(
      caseId: readinessCase['caseId']?.toString() ?? '',
      requirements: hinetReviewConditions
          .map((condition) => condition['name'].toString())
          .toList(growable: false),
      fixturePath: fixturePath,
      truthSource: truthSource,
      truthQuality: truthQuality,
      decisionStatus: decision?.decisionStatus ?? 'missing_decision',
      acceptedForConstrainedReferenceSplit:
          decision?.acceptedForConstrainedReferenceSplit ?? false,
      decisionRequiredActions: decision?.requiredActions ?? const [],
      blockingEvidence: decision?.blockingEvidence ?? const [],
      catalogTruthVerified: catalogTruthVerified,
      includeInDetectionMetrics: includeInDetectionMetrics,
      splitStatus: splitStatus,
      captureDirectory: captureDirectory,
      captureDirectoryExists: captureDirectoryExists,
      captureFileCount: captureFileCount,
      captureManifestPath: captureProvenance.manifestPath,
      captureManifestExists: captureProvenance.manifestExists,
      captureExpectedGifCount: captureProvenance.expectedGifCount,
      captureDownloadedGifCount: captureProvenance.downloadedGifCount,
      captureFailedGifCount: captureProvenance.failedGifCount,
      captureMissingFrameCount: captureProvenance.missingFrameCount,
      captureReceivedAtStatus: captureProvenance.receivedAtStatus,
      captureProvenanceComplete: captureProvenance.complete,
      referenceIsolated: referenceIsolated,
      catalogTruthFlagMismatch: catalogTruthFlagMismatch,
      manualReviewReady: referenceIsolated && captureDirectoryExists,
      reviewFlags: reviewFlags,
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'requirements': requirements,
    'fixturePath': fixturePath,
    'truthSource': truthSource,
    'truthQuality': truthQuality,
    'decisionStatus': decisionStatus,
    'acceptedForConstrainedReferenceSplit':
        acceptedForConstrainedReferenceSplit,
    'decisionRequiredActions': decisionRequiredActions,
    'blockingEvidence': blockingEvidence
        .map((evidence) => evidence.toJson())
        .toList(growable: false),
    'catalogTruthVerified': catalogTruthVerified,
    'includeInDetectionMetrics': includeInDetectionMetrics,
    'splitStatus': splitStatus,
    'captureDirectory': captureDirectory,
    'captureDirectoryExists': captureDirectoryExists,
    'captureFileCount': captureFileCount,
    'captureManifestPath': captureManifestPath,
    'captureManifestExists': captureManifestExists,
    'captureExpectedGifCount': captureExpectedGifCount,
    'captureDownloadedGifCount': captureDownloadedGifCount,
    'captureFailedGifCount': captureFailedGifCount,
    'captureMissingFrameCount': captureMissingFrameCount,
    'captureReceivedAtStatus': captureReceivedAtStatus,
    'captureProvenanceComplete': captureProvenanceComplete,
    'referenceIsolated': referenceIsolated,
    'catalogTruthFlagMismatch': catalogTruthFlagMismatch,
    'manualReviewReady': manualReviewReady,
    'reviewFlags': reviewFlags,
  };
}

class _CaptureProvenance {
  final String? manifestPath;
  final bool manifestExists;
  final int? expectedGifCount;
  final int? downloadedGifCount;
  final int? failedGifCount;
  final int? missingFrameCount;
  final String? receivedAtStatus;

  const _CaptureProvenance({
    required this.manifestPath,
    required this.manifestExists,
    required this.expectedGifCount,
    required this.downloadedGifCount,
    required this.failedGifCount,
    required this.missingFrameCount,
    required this.receivedAtStatus,
  });

  bool get complete {
    if (!manifestExists) return false;
    final expected = expectedGifCount;
    final downloaded = downloadedGifCount;
    final failed = failedGifCount;
    final missing = missingFrameCount;
    if (failed != null && failed > 0) return false;
    if (missing != null && missing > 0) return false;
    if (expected != null && downloaded != null && downloaded < expected) {
      return false;
    }
    return true;
  }

  factory _CaptureProvenance.fromDirectory(Directory? directory) {
    if (directory == null || !directory.existsSync()) {
      return const _CaptureProvenance(
        manifestPath: null,
        manifestExists: false,
        expectedGifCount: null,
        downloadedGifCount: null,
        failedGifCount: null,
        missingFrameCount: null,
        receivedAtStatus: null,
      );
    }

    final captureManifest = File('${directory.path}/capture_manifest.json');
    final replayManifest = File('${directory.path}/manifest.json');
    final captureJson = _readJson(captureManifest);
    final replayJson = _readJson(replayManifest);
    final captureExists = captureJson != null;
    final replayExists = replayJson != null;
    final missingFrames = replayExists
        ? _list(replayJson['missingFrames']).length
        : null;
    return _CaptureProvenance(
      manifestPath: captureExists
          ? captureManifest.path
          : replayExists
          ? replayManifest.path
          : null,
      manifestExists: captureExists || replayExists,
      expectedGifCount: _intOrNull(captureJson?['expectedGifCount']),
      downloadedGifCount: _intOrNull(captureJson?['downloadedGifCount']),
      failedGifCount: _intOrNull(captureJson?['failedGifCount']),
      missingFrameCount: missingFrames,
      receivedAtStatus:
          captureJson?['receivedAtStatus']?.toString() ??
          _map(replayJson?['provenance'])['receivedAtStatus']?.toString(),
    );
  }
}

Map<String, Object?>? _readFixture(String path, List<String> errors) {
  if (path.isEmpty) {
    errors.add('hinet_review_fixture_path_missing');
    return null;
  }
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('hinet_review_fixture_missing:$path');
    return null;
  }
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (error) {
    errors.add('hinet_review_fixture_parse_failed:$path:$error');
    return null;
  }
}

Map<String, Object?>? _readJson(File file) {
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (_) {
    return null;
  }
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

List<Object?> _list(Object? value) {
  if (value is List) return value;
  return const [];
}
