import 'dart:convert';
import 'dart:io';

const _defaultCaseId = 'noto_m27_20260621_jma_eq5';
const _defaultFixture =
    'test/fixtures/source_estimation/noto_m27_20260621_jma_eq5.json';
const _defaultOutput = '.dart_tool/source_trigger_threshold_review/report.json';
const _defaultMarkdown =
    'docs/baselines/source_trigger_threshold_review.generated.md';
const _defaultP0Benchmark =
    '.dart_tool/source_estimation_benchmark/source_estimation_p0.json';
const _defaultLiveQuietBenchmark =
    '.dart_tool/source_estimation_benchmark/quiet_20260625_233535_jst_live.json';

void main(List<String> args) {
  final caseId = _argument(args, '--case-id') ?? _defaultCaseId;
  final fixturePath = _argument(args, '--fixture') ?? _defaultFixture;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;
  final p0BenchmarkPath =
      _argument(args, '--p0-benchmark') ?? _defaultP0Benchmark;
  final liveQuietBenchmarkPath =
      _argument(args, '--live-quiet-benchmark') ?? _defaultLiveQuietBenchmark;

  final report = _SourceTriggerThresholdReviewReport.build(
    caseId: caseId,
    fixtureFile: File(fixturePath),
    p0BenchmarkFile: File(p0BenchmarkPath),
    liveQuietBenchmarkFile: File(liveQuietBenchmarkPath),
  );

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(report.toMarkdown());

  stdout.writeln('wrote source-trigger threshold review report');
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

class _SourceTriggerThresholdReviewReport {
  const _SourceTriggerThresholdReviewReport({
    required this.caseId,
    required this.fixturePath,
    required this.caseReview,
    required this.quietWindowValidation,
    required this.errors,
    required this.warnings,
  });

  final String caseId;
  final String fixturePath;
  final _SourceTriggerThresholdReviewCase? caseReview;
  final _QuietWindowValidation quietWindowValidation;
  final List<String> errors;
  final List<String> warnings;

  factory _SourceTriggerThresholdReviewReport.build({
    required String caseId,
    required File fixtureFile,
    required File p0BenchmarkFile,
    required File liveQuietBenchmarkFile,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final quietWindowValidation = _QuietWindowValidation.build(
      p0BenchmarkFile: p0BenchmarkFile,
      liveQuietBenchmarkFile: liveQuietBenchmarkFile,
      errors: errors,
    );
    final caseReview = _SourceTriggerThresholdReviewCase.fromFixture(
      caseId: caseId,
      fixtureFile: fixtureFile,
      quietWindowValidationPassed: quietWindowValidation.passed,
      errors: errors,
      warnings: warnings,
    );

    return _SourceTriggerThresholdReviewReport(
      caseId: caseId,
      fixturePath: fixtureFile.path,
      caseReview: caseReview,
      quietWindowValidation: quietWindowValidation,
      errors: errors,
      warnings: warnings,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 'source_trigger_threshold_review_v2',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'status': errors.isEmpty ? 'pass' : 'fail',
    'caseId': caseId,
    'fixturePath': fixturePath,
    'summary': {
      'reviewCaseCount': caseReview == null ? 0 : 1,
      'captureProvenanceLocallyCompleteCount':
          caseReview?.captureProvenanceLocallyComplete == true ? 1 : 0,
      'historicalFetchCaptureCount':
          caseReview?.receivedAtStatus == 'unavailable_historical_fetch'
          ? 1
          : 0,
      'sourceTriggerMissedEventCount':
          caseReview?.sourceTriggerMissedEvent == true ? 1 : 0,
      'quietWindowCount': quietWindowValidation.quietWindows.length,
      'quietWindowPassedCount': quietWindowValidation.passedCount,
      'quietWindowDecodedFrameCount': quietWindowValidation.decodedFrameCount,
      'quietWindowCandidateFrameCount':
          quietWindowValidation.candidateFrameCount,
      'quietWindowConfirmedFrameCount':
          quietWindowValidation.confirmedFrameCount,
      'quietWindowFalseEstimateFrameCount':
          quietWindowValidation.falseEstimateFrameCount,
      'thresholdReviewClearedCount': caseReview?.thresholdReviewCleared == true
          ? 1
          : 0,
      'noiseWindowValidationRequiredCount':
          caseReview?.noiseWindowValidationRequired == true ? 1 : 0,
      'physicalFusionProductionEnabledCount':
          caseReview?.physicalFusionProductionEnabled == true ? 1 : 0,
    },
    'errors': errors,
    'warnings': warnings,
    'quietWindowValidation': quietWindowValidation.toJson(),
    'case': caseReview?.toJson(),
  };

  String toMarkdown() {
    final json = toJson();
    final summary = (json['summary'] as Map).cast<String, Object?>();
    final item = caseReview;
    final buffer = StringBuffer()
      ..writeln('# Source Trigger Threshold Review')
      ..writeln()
      ..writeln('- Status: `${json['status']}`')
      ..writeln('- Case: `$caseId`')
      ..writeln('- Fixture: `$fixturePath`')
      ..writeln(
        '- Capture provenance locally complete: '
        '`${summary['captureProvenanceLocallyCompleteCount']}`',
      )
      ..writeln(
        '- Historical-fetch captures: '
        '`${summary['historicalFetchCaptureCount']}`',
      )
      ..writeln(
        '- Source trigger missed events: '
        '`${summary['sourceTriggerMissedEventCount']}`',
      )
      ..writeln(
        '- Quiet-window pass/total: '
        '`${summary['quietWindowPassedCount']}/${summary['quietWindowCount']}`',
      )
      ..writeln(
        '- Quiet-window decoded frames: '
        '`${summary['quietWindowDecodedFrameCount']}`',
      )
      ..writeln(
        '- Quiet-window candidate/confirmed frames: '
        '`${summary['quietWindowCandidateFrameCount']}/'
        '${summary['quietWindowConfirmedFrameCount']}`',
      )
      ..writeln(
        '- Quiet-window false estimate frames: '
        '`${summary['quietWindowFalseEstimateFrameCount']}`',
      )
      ..writeln(
        '- Threshold review cleared: '
        '`${summary['thresholdReviewClearedCount']}`',
      )
      ..writeln(
        '- Noise-window validation required: '
        '`${summary['noiseWindowValidationRequiredCount']}`',
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
      ..writeln('## Quiet Windows')
      ..writeln()
      ..writeln(
        '| Case | Artifact | Frames | Candidate | Confirmed | False estimates | Pass |',
      )
      ..writeln('| --- | --- | ---: | ---: | ---: | ---: | --- |');
    for (final quiet in quietWindowValidation.quietWindows) {
      buffer.writeln(
        '| `${quiet.caseId}` | `${quiet.artifactPath}` | '
        '${quiet.decodedFrameCount} | ${quiet.candidateFrameCount} | '
        '${quiet.confirmedFrameCount} | ${quiet.falseEstimateFrameCount} | '
        '${quiet.passed ? 'yes' : 'no'} |',
      );
    }

    if (item != null) {
      buffer
        ..writeln()
        ..writeln('## Event Evidence')
        ..writeln()
        ..writeln('| Field | Value |')
        ..writeln('| --- | --- |')
        ..writeln('| Capture directory | `${item.captureDirectory}` |')
        ..writeln(
          '| Capture directory source | `${item.captureDirectorySource}` |',
        )
        ..writeln('| Expected GIFs | `${item.expectedGifCount}` |')
        ..writeln('| Downloaded GIFs | `${item.downloadedGifCount}` |')
        ..writeln('| Failed GIFs | `${item.failedGifCount}` |')
        ..writeln('| Received-at status | `${item.receivedAtStatus}` |')
        ..writeln('| Triggered frames | `${item.triggeredFrameCount}` |')
        ..writeln(
          '| Source trigger missed event | `${item.sourceTriggerMissedEvent}` |',
        )
        ..writeln(
          '| JMA-only first delay | `${item.jmaOnlyFirstDelaySeconds}` |',
        )
        ..writeln(
          '| JMA-only first error km | `${_fmt(item.jmaOnlyFirstErrorKm)}` |',
        )
        ..writeln(
          '| Physical first error km | `${_fmt(item.physicalFirstErrorKm)}` |',
        )
        ..writeln(
          '| Physical first-error delta km | `${_fmt(item.physicalFirstErrorDeltaKm)}` |',
        )
        ..writeln(
          '| Threshold review cleared | `${item.thresholdReviewCleared}` |',
        )
        ..writeln('| Next split action | `${item.nextAction}` |')
        ..writeln()
        ..writeln('## Decision')
        ..writeln()
        ..writeln(
          '- The Noto capture is locally complete and uses the legacy '
          '`capture.directory` field correctly.',
        )
        ..writeln(
          '- The capture was obtained by historical fetch, so it does not '
          'prove live receive timing.',
        )
        ..writeln(
          quietWindowValidation.passed
              ? '- Independent quiet-window replay now shows zero source-trigger '
                    'candidate/confirmed frames and zero source-estimate frames.'
              : '- Source-trigger threshold review remains pending because '
                    'quiet-window replay evidence is incomplete or failed.',
        )
        ..writeln(
          item.thresholdReviewCleared
              ? '- The source-trigger threshold blocker is cleared for this '
                    'case; the next action is manual event-level split review.'
              : '- The source-trigger threshold blocker remains pending.',
        )
        ..writeln(
          '- Experimental physical fusion worsens the early estimate on this '
          'case and remains non-production.',
        );
    }

    return buffer.toString();
  }
}

class _QuietWindowValidation {
  const _QuietWindowValidation({required this.quietWindows});

  final List<_QuietWindowEvidence> quietWindows;

  bool get passed =>
      quietWindows.length >= 2 && quietWindows.every((item) => item.passed);

  int get passedCount => quietWindows.where((item) => item.passed).length;

  int get decodedFrameCount =>
      quietWindows.fold(0, (sum, item) => sum + item.decodedFrameCount);

  int get candidateFrameCount =>
      quietWindows.fold(0, (sum, item) => sum + item.candidateFrameCount);

  int get confirmedFrameCount =>
      quietWindows.fold(0, (sum, item) => sum + item.confirmedFrameCount);

  int get falseEstimateFrameCount =>
      quietWindows.fold(0, (sum, item) => sum + item.falseEstimateFrameCount);

  factory _QuietWindowValidation.build({
    required File p0BenchmarkFile,
    required File liveQuietBenchmarkFile,
    required List<String> errors,
  }) {
    final quietWindows = <_QuietWindowEvidence>[];
    final p0Report = _readJson(p0BenchmarkFile, errors, 'p0_benchmark_report');
    final p0Cases = _list(
      p0Report['cases'],
    ).map((entry) => _map(entry)).toList(growable: false);
    final p0Quiet = p0Cases
        .where((entry) => entry['caseId'] == '20260614_quiet_175544')
        .firstOrNull;
    if (p0Quiet == null) {
      errors.add('quiet_window_case_missing:20260614_quiet_175544');
    } else {
      quietWindows.add(
        _QuietWindowEvidence.fromBenchmarkCase(
          p0Quiet,
          artifactPath: p0BenchmarkFile.path,
        ),
      );
    }

    final liveReport = _readJson(
      liveQuietBenchmarkFile,
      errors,
      'live_quiet_benchmark_report',
    );
    if (liveReport.isNotEmpty) {
      quietWindows.add(
        _QuietWindowEvidence.fromSingleBenchmark(
          liveReport,
          artifactPath: liveQuietBenchmarkFile.path,
        ),
      );
    }

    final ids = quietWindows.map((item) => item.caseId).toSet();
    if (ids.length != quietWindows.length) {
      errors.add('quiet_window_cases_not_independent_duplicate_ids');
    }
    if (quietWindows.length < 2) {
      errors.add('quiet_window_validation_requires_two_windows');
    }
    for (final quiet in quietWindows) {
      if (!quiet.passed) {
        errors.add('quiet_window_validation_failed:${quiet.caseId}');
      }
    }

    return _QuietWindowValidation(quietWindows: quietWindows);
  }

  Map<String, Object?> toJson() => {
    'passed': passed,
    'quietWindowCount': quietWindows.length,
    'passedCount': passedCount,
    'decodedFrameCount': decodedFrameCount,
    'candidateFrameCount': candidateFrameCount,
    'confirmedFrameCount': confirmedFrameCount,
    'falseEstimateFrameCount': falseEstimateFrameCount,
    'quietWindows': quietWindows.map((item) => item.toJson()).toList(),
  };
}

class _QuietWindowEvidence {
  const _QuietWindowEvidence({
    required this.caseId,
    required this.artifactPath,
    required this.decodedFrameCount,
    required this.candidateFrameCount,
    required this.confirmedFrameCount,
    required this.falseEstimateFrameCount,
    required this.passed,
  });

  final String caseId;
  final String artifactPath;
  final int decodedFrameCount;
  final int candidateFrameCount;
  final int confirmedFrameCount;
  final int falseEstimateFrameCount;
  final bool passed;

  factory _QuietWindowEvidence.fromBenchmarkCase(
    Map<String, Object?> json, {
    required String artifactPath,
  }) {
    return _QuietWindowEvidence.fromFields(
      caseId: json['caseId']?.toString() ?? '',
      artifactPath: artifactPath,
      decodedFrameCount: _intValue(json['decodedFrameCount']),
      detectionSummary: _map(json['detectionSummary']),
      summaries: _map(json['summaries']),
    );
  }

  factory _QuietWindowEvidence.fromSingleBenchmark(
    Map<String, Object?> json, {
    required String artifactPath,
  }) {
    final replayCase = _map(json['case']);
    return _QuietWindowEvidence.fromFields(
      caseId: replayCase['caseId']?.toString() ?? '',
      artifactPath: artifactPath,
      decodedFrameCount: _intValue(json['decodedFrameCount']),
      detectionSummary: _map(json['detectionSummary']),
      summaries: _map(json['summaries']),
    );
  }

  factory _QuietWindowEvidence.fromFields({
    required String caseId,
    required String artifactPath,
    required int decodedFrameCount,
    required Map<String, Object?> detectionSummary,
    required Map<String, Object?> summaries,
  }) {
    final candidateFrameCount = _intValue(
      detectionSummary['falseCandidateFrameCount'] ??
          detectionSummary['candidateFrameCount'],
    );
    final confirmedFrameCount = _intValue(
      detectionSummary['falseConfirmedFrameCount'] ??
          detectionSummary['confirmedFrameCount'],
    );
    var falseEstimateFrameCount = 0;
    for (final summary in summaries.values) {
      falseEstimateFrameCount += _intValue(
        _map(summary)['falseEstimateFrameCount'],
      );
    }
    return _QuietWindowEvidence(
      caseId: caseId,
      artifactPath: artifactPath,
      decodedFrameCount: decodedFrameCount,
      candidateFrameCount: candidateFrameCount,
      confirmedFrameCount: confirmedFrameCount,
      falseEstimateFrameCount: falseEstimateFrameCount,
      passed:
          caseId.isNotEmpty &&
          decodedFrameCount > 0 &&
          candidateFrameCount == 0 &&
          confirmedFrameCount == 0 &&
          falseEstimateFrameCount == 0,
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'artifactPath': artifactPath,
    'decodedFrameCount': decodedFrameCount,
    'candidateFrameCount': candidateFrameCount,
    'confirmedFrameCount': confirmedFrameCount,
    'falseEstimateFrameCount': falseEstimateFrameCount,
    'passed': passed,
  };
}

class _SourceTriggerThresholdReviewCase {
  const _SourceTriggerThresholdReviewCase({
    required this.caseId,
    required this.fixturePath,
    required this.splitStatus,
    required this.nextAction,
    required this.pendingConditions,
    required this.captureDirectory,
    required this.captureDirectorySource,
    required this.captureDirectoryExists,
    required this.captureManifestExists,
    required this.captureProvenanceLocallyComplete,
    required this.receivedAtStatus,
    required this.expectedGifCount,
    required this.downloadedGifCount,
    required this.failedGifCount,
    required this.captureInProgress,
    required this.manifestRecordCount,
    required this.gainReportPath,
    required this.sourceTriggerMissedEvent,
    required this.triggeredFrameCount,
    required this.frameCount,
    required this.decodedFrameCount,
    required this.jmaOnlyFirstDelaySeconds,
    required this.jmaOnlyFirstErrorKm,
    required this.physicalFirstErrorKm,
    required this.physicalFirstErrorDeltaKm,
    required this.physicalFusionProductionEnabled,
    required this.noiseWindowValidationRequired,
    required this.thresholdReviewCleared,
    required this.limitations,
  });

  final String caseId;
  final String fixturePath;
  final String splitStatus;
  final String nextAction;
  final List<String> pendingConditions;
  final String captureDirectory;
  final String captureDirectorySource;
  final bool captureDirectoryExists;
  final bool captureManifestExists;
  final bool captureProvenanceLocallyComplete;
  final String receivedAtStatus;
  final int expectedGifCount;
  final int downloadedGifCount;
  final int failedGifCount;
  final bool captureInProgress;
  final int manifestRecordCount;
  final String gainReportPath;
  final bool sourceTriggerMissedEvent;
  final int triggeredFrameCount;
  final int frameCount;
  final int decodedFrameCount;
  final double? jmaOnlyFirstDelaySeconds;
  final double? jmaOnlyFirstErrorKm;
  final double? physicalFirstErrorKm;
  final double? physicalFirstErrorDeltaKm;
  final bool physicalFusionProductionEnabled;
  final bool noiseWindowValidationRequired;
  final bool thresholdReviewCleared;
  final List<String> limitations;

  factory _SourceTriggerThresholdReviewCase.fromFixture({
    required String caseId,
    required File fixtureFile,
    required bool quietWindowValidationPassed,
    required List<String> errors,
    required List<String> warnings,
  }) {
    final fixture = _readJson(fixtureFile, errors, 'fixture');
    final fixtureCapture = _map(fixture['capture']);
    final captureDirectory =
        fixture['captureDirectory']?.toString() ??
        fixtureCapture['directory']?.toString() ??
        '';
    final captureDirectorySource = fixture['captureDirectory'] == null
        ? 'legacy_capture_directory'
        : 'captureDirectory';
    final captureDir = Directory(
      _resolvePath(Directory.current, captureDirectory),
    );
    final manifestFile = File(
      '${captureDir.path}${Platform.pathSeparator}capture_manifest.json',
    );
    final manifest = _readJson(manifestFile, errors, 'capture_manifest');
    final gainReportFile = File(
      '${captureDir.path}${Platform.pathSeparator}multilayer_gain_report.json',
    );
    final gainReport = _readJson(
      gainReportFile,
      errors,
      'multilayer_gain_report',
    );

    final expectedGifCount = _intValue(manifest['expectedGifCount']);
    final downloadedGifCount = _intValue(manifest['downloadedGifCount']);
    final failedGifCount = _intValue(manifest['failedGifCount']);
    final captureInProgress = manifest['captureInProgress'] == true;
    final receivedAtStatus = manifest['receivedAtStatus']?.toString() ?? '';
    final captureProvenanceLocallyComplete =
        captureDir.existsSync() &&
        manifestFile.existsSync() &&
        expectedGifCount > 0 &&
        expectedGifCount == downloadedGifCount &&
        failedGifCount == 0 &&
        !captureInProgress;

    if (!captureProvenanceLocallyComplete) {
      errors.add('capture_provenance_not_locally_complete');
    }
    if (receivedAtStatus == 'unavailable_historical_fetch') {
      warnings.add('capture_received_at_unavailable_historical_fetch');
    }

    final policy = _map(gainReport['policy']);
    final methods = _map(gainReport['methods']);
    final jmaOnly = _map(methods['jmaOnly']);
    final physical = _map(methods['jmaPhysical']);
    final delta = _map(gainReport['deltaPhysicalMinusJma']);
    final limitations = _list(
      gainReport['limitations'],
    ).map((entry) => entry.toString()).toList(growable: false);
    final physicalFusionProductionEnabled = policy['productionEnabled'] == true;
    final sourceTriggerMissedEvent =
        gainReport['sourceTriggerMissedEvent'] == true;
    final triggeredFrameCount = _intValue(gainReport['triggeredFrameCount']);
    final thresholdReviewCleared =
        !sourceTriggerMissedEvent &&
        triggeredFrameCount > 0 &&
        quietWindowValidationPassed;
    final noiseWindowValidationRequired = !quietWindowValidationPassed;

    final splitStatus = fixture['splitStatus']?.toString() ?? '';
    final splitAssignmentComplete = splitStatus != 'unassigned_reference';

    return _SourceTriggerThresholdReviewCase(
      caseId: fixture['caseId']?.toString() ?? caseId,
      fixturePath: fixtureFile.path,
      splitStatus: splitStatus,
      nextAction: splitAssignmentComplete
          ? 'split_assignment_complete'
          : thresholdReviewCleared
          ? 'assign_event_level_split'
          : 'review_source_trigger_threshold_effect',
      pendingConditions: [
        if (!thresholdReviewCleared) 'review_source_trigger_threshold_effect',
        if (!splitAssignmentComplete) 'assign_event_level_split',
      ],
      captureDirectory: captureDirectory,
      captureDirectorySource: captureDirectorySource,
      captureDirectoryExists: captureDir.existsSync(),
      captureManifestExists: manifestFile.existsSync(),
      captureProvenanceLocallyComplete: captureProvenanceLocallyComplete,
      receivedAtStatus: receivedAtStatus,
      expectedGifCount: expectedGifCount,
      downloadedGifCount: downloadedGifCount,
      failedGifCount: failedGifCount,
      captureInProgress: captureInProgress,
      manifestRecordCount: _list(manifest['records']).length,
      gainReportPath: gainReportFile.path,
      sourceTriggerMissedEvent: sourceTriggerMissedEvent,
      triggeredFrameCount: triggeredFrameCount,
      frameCount: _intValue(gainReport['frameCount']),
      decodedFrameCount: _intValue(gainReport['decodedFrameCount']),
      jmaOnlyFirstDelaySeconds: _doubleValue(
        jmaOnly['firstEstimateDelaySeconds'],
      ),
      jmaOnlyFirstErrorKm: _doubleValue(jmaOnly['firstEstimateErrorKm']),
      physicalFirstErrorKm: _doubleValue(physical['firstEstimateErrorKm']),
      physicalFirstErrorDeltaKm: _doubleValue(delta['firstEstimateErrorKm']),
      physicalFusionProductionEnabled: physicalFusionProductionEnabled,
      noiseWindowValidationRequired: noiseWindowValidationRequired,
      thresholdReviewCleared: thresholdReviewCleared,
      limitations: limitations,
    );
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'fixturePath': fixturePath,
    'splitStatus': splitStatus,
    'nextAction': nextAction,
    'pendingConditions': pendingConditions,
    'captureDirectory': captureDirectory,
    'captureDirectorySource': captureDirectorySource,
    'captureDirectoryExists': captureDirectoryExists,
    'captureManifestExists': captureManifestExists,
    'captureProvenanceLocallyComplete': captureProvenanceLocallyComplete,
    'receivedAtStatus': receivedAtStatus,
    'expectedGifCount': expectedGifCount,
    'downloadedGifCount': downloadedGifCount,
    'failedGifCount': failedGifCount,
    'captureInProgress': captureInProgress,
    'manifestRecordCount': manifestRecordCount,
    'gainReportPath': gainReportPath,
    'sourceTriggerMissedEvent': sourceTriggerMissedEvent,
    'triggeredFrameCount': triggeredFrameCount,
    'frameCount': frameCount,
    'decodedFrameCount': decodedFrameCount,
    'jmaOnlyFirstDelaySeconds': jmaOnlyFirstDelaySeconds,
    'jmaOnlyFirstErrorKm': jmaOnlyFirstErrorKm,
    'physicalFirstErrorKm': physicalFirstErrorKm,
    'physicalFirstErrorDeltaKm': physicalFirstErrorDeltaKm,
    'physicalFusionProductionEnabled': physicalFusionProductionEnabled,
    'noiseWindowValidationRequired': noiseWindowValidationRequired,
    'thresholdReviewCleared': thresholdReviewCleared,
    'limitations': limitations,
  };
}

Map<String, Object?> _readJson(File file, List<String> errors, String label) {
  if (!file.existsSync()) {
    errors.add('${label}_missing:${file.path}');
    return const {};
  }
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (error) {
    errors.add('${label}_parse_failed:${file.path}:$error');
    return const {};
  }
}

String _resolvePath(Directory workspaceRoot, String path) {
  if (path.isEmpty) return path;
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    return path;
  }
  return '${workspaceRoot.path}${Platform.pathSeparator}$path';
}

String _fmt(double? value) => value == null ? '--' : value.toStringAsFixed(2);

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
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
