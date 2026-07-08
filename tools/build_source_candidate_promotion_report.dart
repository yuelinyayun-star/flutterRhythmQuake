import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _defaultInput = '.dart_tool/source_estimation_early_frame_report';
const _defaultOutput =
    '.dart_tool/source_candidate_promotion_report/report.json';
const _defaultMarkdown =
    'docs/baselines/source_candidate_promotion_report.generated.md';

const _rankSupportDelta = -0.05;
const _attenuationSupportDelta = -0.05;
const _rankRegressionDelta = 0.10;
const _attenuationRegressionRatio = 1.25;
const _delayedConfirmationWindowSeconds = 5.0;
const _delayedConfirmationClusterKm = 30.0;
const _expectedCoreCaseIds = {
  '20260621_fukushima_offshore_m32_eq6',
  '20260622_kushiro_offshore_m30_jma',
  '20260622_tomakomai_south_offshore_m35_hinet',
  '20260625_iwate_offshore_m32_jma',
};

void main(List<String> args) {
  final inputPath = _argument(args, '--input') ?? _defaultInput;
  final outputPath = _argument(args, '--output') ?? _defaultOutput;
  final markdownPath = _argument(args, '--markdown') ?? _defaultMarkdown;

  final input = Directory(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('Early-frame report directory does not exist: $inputPath');
    exitCode = 66;
    return;
  }

  final skippedFiles = <Map<String, Object?>>[];
  final cases = <_CasePromotionReport>[];
  final files =
      input
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.json'))
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));

  for (final file in files) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        skippedFiles.add({'file': file.path, 'reason': 'not_a_json_object'});
        continue;
      }
      final report = decoded.cast<String, Object?>();
      if (report['schemaVersion'] !=
          'source_estimation_early_frame_report_v1') {
        skippedFiles.add({
          'file': file.path,
          'reason': 'not_an_early_frame_report',
        });
        continue;
      }
      cases.add(_CasePromotionReport.fromEarlyFrameReport(file, report));
    } on FormatException catch (error) {
      skippedFiles.add({
        'file': file.path,
        'reason': 'invalid_json',
        'error': error.message,
      });
    }
  }

  final report = <String, Object?>{
    'schemaVersion': 'source_candidate_promotion_report_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'inputDirectory': input.path,
    'caseCount': cases.length,
    'candidateFrameCount': cases.fold<int>(
      0,
      (total, entry) => total + entry.candidateFrames.length,
    ),
    'productionGate': const {
      'usesTruthLabels': false,
      'rankSupportDeltaMax': _rankSupportDelta,
      'attenuationSupportDeltaMax': _attenuationSupportDelta,
      'dualRegressionReject': {
        'rankDeltaMin': _rankRegressionDelta,
        'attenuationRatioMin': _attenuationRegressionRatio,
      },
      'decision':
          'accept if rank or attenuation supports candidate and '
          'rank plus attenuation do not both strongly regress',
      'travelTimeResiduals':
          'diagnostic_only_until_positive_cases_can_be_'
          'separated_from_fukushima_without_truth',
      'delayedConfirmationDiagnostic': {
        'windowSeconds': _delayedConfirmationWindowSeconds,
        'clusterDistanceKm': _delayedConfirmationClusterKm,
        'productionCoordinateSwitch': false,
      },
    },
    'cases': cases.map((entry) => entry.toJson()).toList(growable: false),
    'skippedFiles': skippedFiles,
    'validation': _validation(cases, skippedFiles).toJson(),
  };

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(
    _markdown(
      input.path,
      cases,
      skippedFiles,
      _validation(cases, skippedFiles),
    ),
  );

  stdout.writeln(
    'wrote candidate promotion report for ${cases.length} early-frame cases',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

class _PromotionValidation {
  final List<String> violations;

  const _PromotionValidation({required this.violations});

  bool get passed => violations.isEmpty;

  Map<String, Object?> toJson() => {
    'status': passed ? 'pass' : 'fail',
    'violations': violations,
    'expectedCoreCases': _expectedCoreCaseIds.toList(growable: false),
  };
}

class _CasePromotionReport {
  final String caseId;
  final String inputPath;
  final int earlyFrameCount;
  final List<_FramePromotion> candidateFrames;
  final List<String> findings;

  const _CasePromotionReport({
    required this.caseId,
    required this.inputPath,
    required this.earlyFrameCount,
    required this.candidateFrames,
    required this.findings,
  });

  factory _CasePromotionReport.fromEarlyFrameReport(
    File file,
    Map<String, Object?> report,
  ) {
    final frames = _list(report['frames']);
    final candidateFrames = <_FramePromotion>[];
    for (final rawFrame in frames) {
      final frame = _map(rawFrame);
      if (frame['candidate'] == null) continue;
      candidateFrames.add(_FramePromotion.fromFrame(frame));
    }
    return _CasePromotionReport(
      caseId: report['caseId']?.toString() ?? file.uri.pathSegments.last,
      inputPath: file.path,
      earlyFrameCount: frames.length,
      candidateFrames: candidateFrames,
      findings: _caseFindings(candidateFrames),
    );
  }

  int get acceptedCount =>
      candidateFrames.where((frame) => frame.accepted).length;

  int get rejectedCount => candidateFrames.length - acceptedCount;

  int get offlineImprovedCount =>
      candidateFrames.where((frame) => frame.offlineImproves).length;

  int get falseAcceptCount => candidateFrames
      .where((frame) => frame.accepted && !frame.offlineImproves)
      .length;

  int get missedPositiveCount => candidateFrames
      .where((frame) => !frame.accepted && frame.offlineImproves)
      .length;

  int get delayedRecoveredMissedPositiveCount => candidateFrames
      .where(
        (frame) =>
            !frame.accepted &&
            frame.offlineImproves &&
            delayedConfirmation(frame) != null,
      )
      .length;

  int get delayedFalseRecoveryCount => candidateFrames
      .where(
        (frame) =>
            !frame.accepted &&
            !frame.offlineImproves &&
            delayedConfirmation(frame) != null,
      )
      .length;

  _DelayedConfirmation? delayedConfirmation(_FramePromotion frame) {
    if (frame.accepted || frame.observedAt == null) return null;
    final frameTime = frame.observedAt!;
    for (final future in candidateFrames) {
      if (!future.accepted || future.observedAt == null) continue;
      final seconds =
          future.observedAt!.difference(frameTime).inMilliseconds /
          Duration.millisecondsPerSecond;
      if (seconds <= 0 || seconds > _delayedConfirmationWindowSeconds) {
        continue;
      }
      final distanceKm = _haversineKm(
        frame.candidateLatitude,
        frame.candidateLongitude,
        future.candidateLatitude,
        future.candidateLongitude,
      );
      if (distanceKm == null || distanceKm > _delayedConfirmationClusterKm) {
        continue;
      }
      return _DelayedConfirmation(
        confirmed: true,
        confirmingObservedAtJst: future.observedAtJst,
        delaySeconds: seconds,
        clusterDistanceKm: distanceKm,
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'inputPath': inputPath,
    'earlyFrameCount': earlyFrameCount,
    'candidateFrameCount': candidateFrames.length,
    'acceptedCandidateFrames': acceptedCount,
    'rejectedCandidateFrames': rejectedCount,
    'offlineImprovedCandidateFrames': offlineImprovedCount,
    'offlineFalseAcceptFrames': falseAcceptCount,
    'offlineMissedPositiveFrames': missedPositiveCount,
    'delayedRecoveredMissedPositiveFrames': delayedRecoveredMissedPositiveCount,
    'delayedFalseRecoveryFrames': delayedFalseRecoveryCount,
    'findings': findings,
    'frames': candidateFrames
        .map((frame) => frame.toJson(delayed: delayedConfirmation(frame)))
        .toList(growable: false),
  };
}

class _FramePromotion {
  final int sourceFrameIndex;
  final String? observedAtJst;
  final double? candidateLatitude;
  final double? candidateLongitude;
  final double? baselineErrorKm;
  final double? candidateErrorKm;
  final double? baselineTravelRms;
  final double? candidateTravelRms;
  final double? baselineRankInversionRate;
  final double? candidateRankInversionRate;
  final double? baselineAttenuationRms;
  final double? candidateAttenuationRms;
  final bool rankSupportsCandidate;
  final bool attenuationSupportsCandidate;
  final bool dualResidualRegression;
  final bool accepted;
  final List<String> rejectReasons;

  const _FramePromotion({
    required this.sourceFrameIndex,
    required this.observedAtJst,
    required this.candidateLatitude,
    required this.candidateLongitude,
    required this.baselineErrorKm,
    required this.candidateErrorKm,
    required this.baselineTravelRms,
    required this.candidateTravelRms,
    required this.baselineRankInversionRate,
    required this.candidateRankInversionRate,
    required this.baselineAttenuationRms,
    required this.candidateAttenuationRms,
    required this.rankSupportsCandidate,
    required this.attenuationSupportsCandidate,
    required this.dualResidualRegression,
    required this.accepted,
    required this.rejectReasons,
  });

  factory _FramePromotion.fromFrame(Map<String, Object?> frame) {
    final baseline = _map(frame['baseline']);
    final candidate = _map(frame['candidate']);
    final baselineTravelRms = _number(
      _map(baseline['travelTimeResiduals'])['rms'],
    );
    final candidateTravelRms = _number(
      _map(candidate['travelTimeResiduals'])['rms'],
    );
    final baselineRank = _number(_map(baseline['rank'])['inversionRate']);
    final candidateRank = _number(_map(candidate['rank'])['inversionRate']);
    final baselineAttenuation = _number(
      _map(baseline['attenuationResiduals'])['rms'],
    );
    final candidateAttenuation = _number(
      _map(candidate['attenuationResiduals'])['rms'],
    );
    final rankDelta = _delta(candidateRank, baselineRank);
    final attenuationDelta = _delta(candidateAttenuation, baselineAttenuation);
    final attenuationRatio = _ratio(candidateAttenuation, baselineAttenuation);
    final rankSupportsCandidate =
        rankDelta != null && rankDelta <= _rankSupportDelta;
    final attenuationSupportsCandidate =
        attenuationDelta != null &&
        attenuationDelta <= _attenuationSupportDelta;
    final dualResidualRegression =
        rankDelta != null &&
        attenuationRatio != null &&
        rankDelta >= _rankRegressionDelta &&
        attenuationRatio >= _attenuationRegressionRatio;
    final rejectReasons = <String>[];
    if (!rankSupportsCandidate && !attenuationSupportsCandidate) {
      rejectReasons.add('no_rank_or_attenuation_support');
    }
    if (dualResidualRegression) {
      rejectReasons.add('rank_and_attenuation_regress_together');
    }
    final accepted = rejectReasons.isEmpty;

    return _FramePromotion(
      sourceFrameIndex: (_number(frame['sourceFrameIndex']) ?? -1).toInt(),
      observedAtJst: frame['observedAtJst']?.toString(),
      candidateLatitude: _number(candidate['latitude']),
      candidateLongitude: _number(candidate['longitude']),
      baselineErrorKm: _number(baseline['errorKm']),
      candidateErrorKm: _number(candidate['errorKm']),
      baselineTravelRms: baselineTravelRms,
      candidateTravelRms: candidateTravelRms,
      baselineRankInversionRate: baselineRank,
      candidateRankInversionRate: candidateRank,
      baselineAttenuationRms: baselineAttenuation,
      candidateAttenuationRms: candidateAttenuation,
      rankSupportsCandidate: rankSupportsCandidate,
      attenuationSupportsCandidate: attenuationSupportsCandidate,
      dualResidualRegression: dualResidualRegression,
      accepted: accepted,
      rejectReasons: List.unmodifiable(rejectReasons),
    );
  }

  bool get offlineImproves =>
      candidateErrorKm != null &&
      baselineErrorKm != null &&
      candidateErrorKm! < baselineErrorKm!;

  double? get rankDelta =>
      _delta(candidateRankInversionRate, baselineRankInversionRate);

  double? get attenuationDelta =>
      _delta(candidateAttenuationRms, baselineAttenuationRms);

  double? get attenuationRatio =>
      _ratio(candidateAttenuationRms, baselineAttenuationRms);

  double? get travelRatio => _ratio(candidateTravelRms, baselineTravelRms);

  DateTime? get observedAt {
    final value = observedAtJst;
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  Map<String, Object?> toJson({_DelayedConfirmation? delayed}) => {
    'sourceFrameIndex': sourceFrameIndex,
    'observedAtJst': observedAtJst,
    'candidateLocation': {
      'latitude': candidateLatitude,
      'longitude': candidateLongitude,
    },
    'productionGate': {
      'accepted': accepted,
      'rankSupportsCandidate': rankSupportsCandidate,
      'attenuationSupportsCandidate': attenuationSupportsCandidate,
      'dualResidualRegression': dualResidualRegression,
      'rejectReasons': rejectReasons,
      'rankDelta': rankDelta,
      'attenuationDelta': attenuationDelta,
      'attenuationRatio': attenuationRatio,
      'travelRatioDiagnosticOnly': travelRatio,
    },
    'offlineEvaluation': {
      'baselineErrorKm': baselineErrorKm,
      'candidateErrorKm': candidateErrorKm,
      'candidateImprovesTruthError': offlineImproves,
    },
    'delayedConfirmationDiagnostic':
        delayed?.toJson() ?? const {'confirmed': false},
    'residuals': {
      'travelTimeRmsSeconds': {
        'baseline': baselineTravelRms,
        'candidate': candidateTravelRms,
      },
      'rankInversionRate': {
        'baseline': baselineRankInversionRate,
        'candidate': candidateRankInversionRate,
      },
      'attenuationRms': {
        'baseline': baselineAttenuationRms,
        'candidate': candidateAttenuationRms,
      },
    },
  };
}

class _DelayedConfirmation {
  final bool confirmed;
  final String? confirmingObservedAtJst;
  final double delaySeconds;
  final double clusterDistanceKm;

  const _DelayedConfirmation({
    required this.confirmed,
    required this.confirmingObservedAtJst,
    required this.delaySeconds,
    required this.clusterDistanceKm,
  });

  Map<String, Object?> toJson() => {
    'confirmed': confirmed,
    'confirmingObservedAtJst': confirmingObservedAtJst,
    'delaySeconds': delaySeconds,
    'clusterDistanceKm': clusterDistanceKm,
  };
}

List<String> _caseFindings(List<_FramePromotion> frames) {
  if (frames.isEmpty) return const ['no_candidate_frames'];
  final accepted = frames.where((frame) => frame.accepted).length;
  final falseAccepts = frames
      .where((frame) => frame.accepted && !frame.offlineImproves)
      .length;
  final missed = frames
      .where((frame) => !frame.accepted && frame.offlineImproves)
      .length;
  final findings = <String>[];
  if (accepted == 0) findings.add('gate_rejects_all_candidate_frames');
  if (accepted == frames.length) {
    findings.add('gate_accepts_all_candidate_frames');
  }
  if (falseAccepts == 0) findings.add('no_offline_false_accepts');
  if (missed > 0) findings.add('offline_missed_positive_frames');
  if (frames.any((frame) => frame.dualResidualRegression)) {
    findings.add('dual_residual_regression_present');
  }
  return findings;
}

String _markdown(
  String inputPath,
  List<_CasePromotionReport> cases,
  List<Map<String, Object?>> skippedFiles,
  _PromotionValidation validation,
) {
  final buffer = StringBuffer()
    ..writeln('# Source Candidate Promotion Report')
    ..writeln()
    ..writeln(
      'Generated from early-frame reports in `$inputPath`. This report is '
      'diagnostic-only and does not change production source coordinates.',
    )
    ..writeln()
    ..writeln('## Gate')
    ..writeln()
    ..writeln(
      '- Production-available rule: accept a diagnostic candidate only when '
      'rank inversion or static attenuation scatter supports it.',
    )
    ..writeln(
      '- Hard reject: rank inversion and attenuation scatter both strongly '
      'regress.',
    )
    ..writeln(
      '- Travel-time RMS remains diagnostic-only because it worsens in both '
      'positive offshore cases and the Fukushima failure case.',
    )
    ..writeln(
      '- Delayed confirmation is also diagnostic-only: a rejected candidate is '
      'marked recoverable only if the same candidate area is accepted within '
      '${_delayedConfirmationWindowSeconds.toStringAsFixed(0)} seconds and '
      '${_delayedConfirmationClusterKm.toStringAsFixed(0)} km.',
    )
    ..writeln(
      '- Truth-error columns below are offline evaluation labels, not '
      'production inputs.',
    )
    ..writeln()
    ..writeln('## Case Summary')
    ..writeln()
    ..writeln(
      '| Case | Candidate frames | Accepted | Rejected | Offline improved | '
      'False accepts | Missed positives | Delayed recovered | Delayed false | '
      'Findings |',
    )
    ..writeln(
      '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |',
    );

  for (final entry in cases) {
    buffer.writeln(
      '| `${entry.caseId}` | ${entry.candidateFrames.length} | '
      '${entry.acceptedCount} | ${entry.rejectedCount} | '
      '${entry.offlineImprovedCount} | ${entry.falseAcceptCount} | '
      '${entry.missedPositiveCount} | '
      '${entry.delayedRecoveredMissedPositiveCount} | '
      '${entry.delayedFalseRecoveryCount} | '
      '${entry.findings.map((item) => '`$item`').join(', ')} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Candidate Frames')
    ..writeln();

  for (final entry in cases) {
    buffer
      ..writeln('### ${entry.caseId}')
      ..writeln()
      ..writeln(
        '| Time | Base err | Cand err | Decision | Rank delta | Atten delta | '
        'Atten ratio | Travel ratio | Delayed confirm | Reason |',
      )
      ..writeln(
        '| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | --- | --- |',
      );
    for (final frame in entry.candidateFrames) {
      final delayed = entry.delayedConfirmation(frame);
      buffer.writeln(
        '| `${frame.observedAtJst ?? ''}` | ${_fmt(frame.baselineErrorKm)} | '
        '${_fmt(frame.candidateErrorKm)} | '
        '${frame.accepted ? '`accept`' : '`reject`'} | '
        '${_fmt(frame.rankDelta, digits: 3)} | '
        '${_fmt(frame.attenuationDelta, digits: 3)} | '
        '${_fmt(frame.attenuationRatio, digits: 2)} | '
        '${_fmt(frame.travelRatio, digits: 2)} | '
        '${_delayedLabel(delayed)} | '
        '${frame.rejectReasons.map((item) => '`$item`').join(', ')} |',
      );
    }
    if (entry.candidateFrames.isEmpty) {
      buffer.writeln(
        '| -- | -- | -- | `no_candidate` | -- | -- | -- | -- | -- |',
      );
    }
    buffer.writeln();
  }

  if (skippedFiles.isNotEmpty) {
    buffer
      ..writeln('## Skipped Files')
      ..writeln()
      ..writeln('| File | Reason |')
      ..writeln('| --- | --- |');
    for (final skipped in skippedFiles) {
      buffer.writeln('| `${skipped['file']}` | `${skipped['reason']}` |');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Validation')
    ..writeln()
    ..writeln('- Status: `${validation.passed ? 'pass' : 'fail'}`.');
  if (validation.violations.isEmpty) {
    buffer.writeln('- Violations: none.');
  } else {
    buffer.writeln('- Violations:');
    for (final violation in validation.violations) {
      buffer.writeln('  - `$violation`');
    }
  }
  buffer.writeln();

  final acceptedCases = cases
      .where((entry) => entry.acceptedCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final missedCases = cases
      .where((entry) => entry.missedPositiveCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final unrecoveredMissedCases = cases
      .where(
        (entry) =>
            entry.missedPositiveCount >
            entry.delayedRecoveredMissedPositiveCount,
      )
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final falseAcceptCases = cases
      .where((entry) => entry.falseAcceptCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);
  final delayedRecoveryCases = cases
      .where((entry) => entry.delayedRecoveredMissedPositiveCount > 0)
      .map((entry) => entry.caseId)
      .toList(growable: false);

  buffer
    ..writeln('## Decision')
    ..writeln()
    ..writeln('- Accepted candidate cases: ${_caseList(acceptedCases)}.')
    ..writeln('- Offline missed-positive cases: ${_caseList(missedCases)}.')
    ..writeln(
      '- Missed-positive cases still not recovered by residual-only delayed '
      'confirmation: '
      '${_caseList(unrecoveredMissedCases)}.',
    )
    ..writeln(
      '- Residual-only delayed confirmation recovers pending candidates for: '
      '${_caseList(delayedRecoveryCases)}.',
    )
    ..writeln(
      '- Local-support delayed recovery is reported separately in '
      '`source_candidate_region_timeline.generated.md` so candidate-coordinate '
      'diagnostics and local member-growth diagnostics stay distinct.',
    )
    ..writeln('- Offline false-accept cases: ${_caseList(falseAcceptCases)}.')
    ..writeln(
      '- Candidate coordinates remain diagnostic-only. The refreshed matrix '
      'now shows that the gate is conservative enough to avoid false accepts, '
      'but residual-only promotion still misses real-positive patterns such as '
      'Iwate-style early one-sided candidates.',
    );

  return buffer.toString();
}

_PromotionValidation _validation(
  List<_CasePromotionReport> cases,
  List<Map<String, Object?>> skippedFiles,
) {
  final byId = {for (final entry in cases) entry.caseId: entry};
  final violations = <String>[];
  if (skippedFiles.isNotEmpty) {
    violations.add('promotion_matrix_has_skipped_inputs');
  }
  for (final caseId in _expectedCoreCaseIds) {
    if (!byId.containsKey(caseId)) {
      violations.add('missing_case:$caseId');
    }
  }
  for (final entry in cases) {
    if (entry.falseAcceptCount != 0) {
      violations.add(
        '${entry.caseId}:offline_false_accepts:${entry.falseAcceptCount}',
      );
    }
    if (entry.delayedFalseRecoveryCount != 0) {
      violations.add(
        '${entry.caseId}:delayed_false_recoveries:${entry.delayedFalseRecoveryCount}',
      );
    }
  }

  _expectCount(
    violations,
    byId,
    caseId: '20260621_fukushima_offshore_m32_eq6',
    field: 'accepted',
    actual: (entry) => entry.acceptedCount,
    expected: 0,
  );
  _expectCount(
    violations,
    byId,
    caseId: '20260621_fukushima_offshore_m32_eq6',
    field: 'rejected',
    actual: (entry) => entry.rejectedCount,
    expected: 8,
  );
  _expectCount(
    violations,
    byId,
    caseId: '20260625_iwate_offshore_m32_jma',
    field: 'accepted',
    actual: (entry) => entry.acceptedCount,
    expected: 0,
  );
  _expectCount(
    violations,
    byId,
    caseId: '20260625_iwate_offshore_m32_jma',
    field: 'rejected',
    actual: (entry) => entry.rejectedCount,
    expected: 3,
  );
  _expectCount(
    violations,
    byId,
    caseId: '20260625_iwate_offshore_m32_jma',
    field: 'missed_positive',
    actual: (entry) => entry.missedPositiveCount,
    expected: 3,
  );
  _expectCount(
    violations,
    byId,
    caseId: '20260622_kushiro_offshore_m30_jma',
    field: 'accepted',
    actual: (entry) => entry.acceptedCount,
    expected: 5,
  );
  _expectCount(
    violations,
    byId,
    caseId: '20260622_kushiro_offshore_m30_jma',
    field: 'delayed_recovered',
    actual: (entry) => entry.delayedRecoveredMissedPositiveCount,
    expected: 3,
  );
  _expectCount(
    violations,
    byId,
    caseId: '20260622_tomakomai_south_offshore_m35_hinet',
    field: 'accepted',
    actual: (entry) => entry.acceptedCount,
    expected: 3,
  );
  _expectCount(
    violations,
    byId,
    caseId: '20260622_tomakomai_south_offshore_m35_hinet',
    field: 'rejected',
    actual: (entry) => entry.rejectedCount,
    expected: 0,
  );
  return _PromotionValidation(violations: violations);
}

void _expectCount(
  List<String> violations,
  Map<String, _CasePromotionReport> byId, {
  required String caseId,
  required String field,
  required int Function(_CasePromotionReport entry) actual,
  required int expected,
}) {
  final entry = byId[caseId];
  if (entry == null) return;
  final value = actual(entry);
  if (value != expected) {
    violations.add('$caseId:$field:$value!=expected_$expected');
  }
}

String _caseList(List<String> caseIds) {
  if (caseIds.isEmpty) return 'none';
  return caseIds.map((caseId) => '`$caseId`').join(', ');
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

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double? _delta(double? candidate, double? baseline) {
  if (candidate == null || baseline == null) return null;
  return candidate - baseline;
}

double? _ratio(double? candidate, double? baseline) {
  if (candidate == null || baseline == null || baseline == 0) return null;
  return candidate / baseline;
}

double? _haversineKm(
  double? leftLat,
  double? leftLng,
  double? rightLat,
  double? rightLng,
) {
  if (leftLat == null ||
      leftLng == null ||
      rightLat == null ||
      rightLng == null) {
    return null;
  }
  const radiusKm = 6371.0;
  final dLat = _degreesToRadians(rightLat - leftLat);
  final dLng = _degreesToRadians(rightLng - leftLng);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degreesToRadians(leftLat)) *
          math.cos(_degreesToRadians(rightLat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * radiusKm * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degreesToRadians(double degrees) => degrees * math.pi / 180.0;

String _delayedLabel(_DelayedConfirmation? delayed) {
  if (delayed == null) return '--';
  return '${_fmt(delayed.delaySeconds, digits: 1)}s / '
      '${_fmt(delayed.clusterDistanceKm, digits: 1)}km';
}

String _fmt(double? value, {int digits = 1}) {
  if (value == null || !value.isFinite) return '--';
  return value.toStringAsFixed(digits);
}
