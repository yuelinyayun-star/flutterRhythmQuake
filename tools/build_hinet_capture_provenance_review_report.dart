import 'dart:convert';
import 'dart:io';

const _defaultTruthReviewPath =
    '.dart_tool/hinet_truth_quality_review/report.json';
const _defaultDecisionPath =
    'docs/data/hinet_capture_provenance_review_decisions.json';
const _defaultOutput = '.dart_tool/hinet_capture_provenance_review/report.json';
const _defaultMarkdown =
    'docs/baselines/hinet_capture_provenance_review.generated.md';

void main(List<String> args) {
  final truthReviewPath =
      _argument(args, '--truth-review') ?? _defaultTruthReviewPath;
  final decisionPath = _argument(args, '--decisions') ?? _defaultDecisionPath;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final report = _CaptureProvenanceReviewReport.build(
    truthReviewFile: File(truthReviewPath),
    decisionFile: File(decisionPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote Hi-net capture provenance review report');
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');

  if (report.errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, Object?> buildHinetCaptureProvenanceReviewJson({
  String truthReviewPath = _defaultTruthReviewPath,
  String decisionPath = _defaultDecisionPath,
}) {
  return _CaptureProvenanceReviewReport.build(
    truthReviewFile: File(truthReviewPath),
    decisionFile: File(decisionPath),
  ).toJson();
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

class _CaptureProvenanceReviewReport {
  final String truthReviewPath;
  final String decisionPath;
  final List<_CaptureProvenanceCase> cases;
  final List<String> errors;
  final List<String> warnings;

  const _CaptureProvenanceReviewReport({
    required this.truthReviewPath,
    required this.decisionPath,
    required this.cases,
    required this.errors,
    required this.warnings,
  });

  factory _CaptureProvenanceReviewReport.build({
    required File truthReviewFile,
    required File decisionFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final decisions = _CaptureReviewDecisions.read(decisionFile, errors);
    final cases = <_CaptureProvenanceCase>[];

    if (!truthReviewFile.existsSync()) {
      errors.add('hinet_truth_quality_review_missing:${truthReviewFile.path}');
    } else {
      final truthReview =
          jsonDecode(truthReviewFile.readAsStringSync())
              as Map<String, Object?>;
      if (truthReview['schemaVersion'] != 'hinet_truth_quality_review_v1') {
        errors.add('unexpected_hinet_truth_quality_review_schema');
      }
      if (truthReview['status'] != 'pass') {
        errors.add('hinet_truth_quality_review_not_pass');
      }
      for (final rawCase in _list(truthReview['cases'])) {
        final reviewCase = _map(rawCase);
        final captureComplete = reviewCase['captureProvenanceComplete'] == true;
        final failedCount = _asInt(reviewCase['captureFailedGifCount']) ?? 0;
        final missingCount =
            _asInt(reviewCase['captureMissingFrameCount']) ?? 0;
        if (captureComplete && failedCount == 0 && missingCount == 0) continue;
        final caseId = reviewCase['caseId']?.toString() ?? '';
        cases.add(
          _CaptureProvenanceCase.fromReviewCase(
            reviewCase,
            decisions.byCaseId[caseId],
            errors,
          ),
        );
      }
    }

    final caseIds = cases.map((item) => item.caseId).toSet();
    for (final entry in decisions.byCaseId.entries) {
      final decisionCaseId = entry.key;
      if (entry.value.decisionStatus == 'capture_frame_repaired') {
        continue;
      }
      if (!caseIds.contains(decisionCaseId)) {
        warnings.add(
          'capture_review_decision_not_in_incomplete_queue:$decisionCaseId',
        );
      }
    }

    cases.sort((left, right) => left.caseId.compareTo(right.caseId));
    return _CaptureProvenanceReviewReport(
      truthReviewPath: truthReviewFile.path,
      decisionPath: decisionFile.path,
      cases: cases,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'hinet_capture_provenance_review_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'truthReviewPath': truthReviewPath,
    'decisionPath': decisionPath,
    'summary': {
      'caseCount': cases.length,
      'pendingRepairOrExclusionCount': cases
          .where(
            (item) =>
                item.decisionStatus == 'pending_capture_repair_or_exclusion',
          )
          .length,
      'exclusionApprovedCount': cases
          .where((item) => item.exclusionApproved)
          .length,
      'readyAfterExclusionCount': cases
          .where((item) => item.readyAfterExclusion)
          .length,
      'unresolvedCaptureIssueCount': cases
          .where((item) => !item.readyAfterExclusion)
          .length,
      'failedGifCount': cases.fold<int>(
        0,
        (total, item) => total + item.captureFailedGifCount,
      ),
      'missingFrameCount': cases.fold<int>(
        0,
        (total, item) => total + item.captureMissingFrameCount,
      ),
      'blockingEvidenceCount': cases.fold<int>(
        0,
        (total, item) => total + item.blockingEvidence.length,
      ),
    },
    'errors': errors,
    'warnings': warnings,
    'cases': cases.map((item) => item.toJson()).toList(),
  };

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final buffer = StringBuffer()
      ..writeln('# Hi-net Capture Provenance Review')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Truth review: `$truthReviewPath`')
      ..writeln('- Decision file: `$decisionPath`')
      ..writeln('- Cases: `${summary['caseCount']}`')
      ..writeln(
        '- Pending repair/exclusion: '
        '`${summary['pendingRepairOrExclusionCount']}`',
      )
      ..writeln('- Exclusion approved: `${summary['exclusionApprovedCount']}`')
      ..writeln(
        '- Ready after exclusion: `${summary['readyAfterExclusionCount']}`',
      )
      ..writeln(
        '- Unresolved capture issues: '
        '`${summary['unresolvedCaptureIssueCount']}`',
      )
      ..writeln('- Failed GIFs: `${summary['failedGifCount']}`')
      ..writeln('- Missing frames: `${summary['missingFrameCount']}`')
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
      ..writeln('## Cases')
      ..writeln()
      ..writeln(
        '| Case | Decision | Capture | Failed | Missing | Exclusion | Ready | Blocking evidence |',
      )
      ..writeln('| --- | --- | --- | ---: | ---: | --- | --- | --- |');
    for (final item in cases) {
      buffer.writeln(
        '| `${item.caseId}` | `${item.decisionStatus}` | '
        '`${item.captureDirectory}` | ${item.captureFailedGifCount} | '
        '${item.captureMissingFrameCount} | '
        '${item.exclusionApproved ? 'yes' : 'no'} | '
        '${item.readyAfterExclusion ? 'yes' : 'no'} | '
        '`${item.blockingEvidence.map((entry) => entry['type']).join('`, `')}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Decision')
      ..writeln()
      ..writeln('- This report does not repair or exclude files automatically.')
      ..writeln(
        '- A capture-incomplete Hi-net case remains blocked until the missing '
        'frame is repaired or a reviewer explicitly approves exclusion in the '
        'decision file.',
      );
    return buffer.toString();
  }
}

class _CaptureProvenanceCase {
  final String caseId;
  final String captureDirectory;
  final int captureExpectedGifCount;
  final int captureDownloadedGifCount;
  final int captureFailedGifCount;
  final int captureMissingFrameCount;
  final bool captureProvenanceComplete;
  final List<Map<String, Object?>> blockingEvidence;
  final String decisionStatus;
  final bool exclusionApproved;
  final List<String> excludedFiles;
  final bool readyAfterExclusion;

  const _CaptureProvenanceCase({
    required this.caseId,
    required this.captureDirectory,
    required this.captureExpectedGifCount,
    required this.captureDownloadedGifCount,
    required this.captureFailedGifCount,
    required this.captureMissingFrameCount,
    required this.captureProvenanceComplete,
    required this.blockingEvidence,
    required this.decisionStatus,
    required this.exclusionApproved,
    required this.excludedFiles,
    required this.readyAfterExclusion,
  });

  factory _CaptureProvenanceCase.fromReviewCase(
    Map<String, Object?> reviewCase,
    _CaptureReviewDecision? decision,
    List<String> errors,
  ) {
    final caseId = reviewCase['caseId']?.toString() ?? '';
    if (decision == null) {
      errors.add('capture_review_decision_missing:$caseId');
    } else if (decision.exclusionApproved) {
      if (decision.reviewedAtUtc == null ||
          DateTime.tryParse(decision.reviewedAtUtc!) == null) {
        errors.add('capture_exclusion_invalid_review_time:$caseId');
      }
      if (decision.reviewer == null || decision.reviewer!.trim().isEmpty) {
        errors.add('capture_exclusion_missing_reviewer:$caseId');
      }
      if (decision.excludedFiles.isEmpty) {
        errors.add('capture_exclusion_missing_files:$caseId');
      }
      if (decision.exclusionReason == null ||
          decision.exclusionReason!.trim().isEmpty) {
        errors.add('capture_exclusion_missing_reason:$caseId');
      }
    }
    final failedCount = _asInt(reviewCase['captureFailedGifCount']) ?? 0;
    final missingCount = _asInt(reviewCase['captureMissingFrameCount']) ?? 0;
    final excludedFiles = decision?.excludedFiles ?? const <String>[];
    final readyAfterExclusion =
        decision?.exclusionApproved == true &&
        failedCount + missingCount > 0 &&
        excludedFiles.length >= failedCount + missingCount;
    return _CaptureProvenanceCase(
      caseId: caseId,
      captureDirectory: reviewCase['captureDirectory']?.toString() ?? '',
      captureExpectedGifCount:
          _asInt(reviewCase['captureExpectedGifCount']) ?? 0,
      captureDownloadedGifCount:
          _asInt(reviewCase['captureDownloadedGifCount']) ?? 0,
      captureFailedGifCount: failedCount,
      captureMissingFrameCount: missingCount,
      captureProvenanceComplete:
          reviewCase['captureProvenanceComplete'] == true,
      blockingEvidence: _list(
        reviewCase['blockingEvidence'],
      ).map((entry) => _map(entry)).toList(growable: false),
      decisionStatus: decision?.decisionStatus ?? 'missing_decision',
      exclusionApproved: decision?.exclusionApproved ?? false,
      excludedFiles: excludedFiles,
      readyAfterExclusion: readyAfterExclusion,
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'captureDirectory': captureDirectory,
    'captureExpectedGifCount': captureExpectedGifCount,
    'captureDownloadedGifCount': captureDownloadedGifCount,
    'captureFailedGifCount': captureFailedGifCount,
    'captureMissingFrameCount': captureMissingFrameCount,
    'captureProvenanceComplete': captureProvenanceComplete,
    'blockingEvidence': blockingEvidence,
    'decisionStatus': decisionStatus,
    'exclusionApproved': exclusionApproved,
    'excludedFiles': excludedFiles,
    'readyAfterExclusion': readyAfterExclusion,
  };
}

class _CaptureReviewDecisions {
  final Map<String, _CaptureReviewDecision> byCaseId;

  const _CaptureReviewDecisions(this.byCaseId);

  static _CaptureReviewDecisions read(File file, List<String> errors) {
    if (!file.existsSync()) {
      errors.add('capture_review_decision_file_missing:${file.path}');
      return const _CaptureReviewDecisions({});
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    if (data['schemaVersion'] !=
        'hinet_capture_provenance_review_decisions_v1') {
      errors.add('unexpected_capture_review_decision_schema');
    }
    final decisions = <String, _CaptureReviewDecision>{};
    for (final rawCase in _list(data['cases'])) {
      final item = _map(rawCase);
      final caseId = item['caseId']?.toString() ?? '';
      if (caseId.isEmpty) {
        errors.add('capture_review_decision_missing_case_id');
        continue;
      }
      decisions[caseId] = _CaptureReviewDecision.fromJson(item);
    }
    return _CaptureReviewDecisions(decisions);
  }
}

class _CaptureReviewDecision {
  final String decisionStatus;
  final String? reviewedAtUtc;
  final String? reviewer;
  final bool exclusionApproved;
  final List<String> excludedFiles;
  final String? exclusionReason;

  const _CaptureReviewDecision({
    required this.decisionStatus,
    required this.reviewedAtUtc,
    required this.reviewer,
    required this.exclusionApproved,
    required this.excludedFiles,
    required this.exclusionReason,
  });

  factory _CaptureReviewDecision.fromJson(Map<String, Object?> json) =>
      _CaptureReviewDecision(
        decisionStatus:
            json['decisionStatus']?.toString() ?? 'missing_decision',
        reviewedAtUtc: json['reviewedAtUtc']?.toString(),
        reviewer: json['reviewer']?.toString(),
        exclusionApproved: json['exclusionApproved'] == true,
        excludedFiles: _list(
          json['excludedFiles'],
        ).map((entry) => entry.toString()).toList(growable: false),
        exclusionReason: json['exclusionReason']?.toString(),
      );
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
