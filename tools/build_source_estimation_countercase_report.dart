import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutterrhythmquake/models/nied_station_db.dart';

const _hybridMethod = 'nied_gif_hybrid_v1';
const _centroidMethod = 'weighted_centroid_baseline';
const _scratchMethod = 'scratch_scan_v1';
const _methodIds = [_hybridMethod, _centroidMethod, _scratchMethod];
const _largeErrorKm = 100.0;
const _catastrophicErrorKm = 150.0;
const _highGeometryUncertaintyP90Km = 180.0;
const _highTravelTimeRmsSeconds = 5.0;
const _highRankInversionRate = 0.5;
const _waveSpeedKmPerSec = 3.8;
final _stationIndex = _buildStationIndex();

void main(List<String> args) {
  final inputPath =
      _argument(args, '--input') ?? '.dart_tool/source_estimation_benchmark';
  final jsonPath =
      _argument(args, '--output') ??
      '.dart_tool/source_estimation_countercases/report.json';
  final markdownPath =
      _argument(args, '--markdown') ??
      'docs/baselines/source_estimation_countercases.generated.md';

  final input = Directory(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('Benchmark directory does not exist: ${input.path}');
    exitCode = 66;
    return;
  }

  final cases = <_CaseDiagnostic>[];
  final skippedFiles = <Map<String, Object?>>[];
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
      if (decoded is! Map<String, Object?> ||
          decoded['case'] is! Map ||
          decoded['frames'] is! List ||
          decoded['summaries'] is! Map) {
        skippedFiles.add({
          'file': file.path,
          'reason': 'not_a_case_benchmark_report',
        });
        continue;
      }
      cases.add(_CaseDiagnostic.fromReport(file, decoded));
    } on FormatException catch (error) {
      skippedFiles.add({
        'file': file.path,
        'reason': 'invalid_json',
        'error': error.message,
      });
    }
  }

  final actionableCases =
      cases.where((entry) => entry.flags.isNotEmpty).toList(growable: false)
        ..sort(_comparePriority);
  final report = <String, Object?>{
    'schemaVersion': 'source_estimation_countercases_v1',
    'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
    'inputDirectory': input.path,
    'caseCount': cases.length,
    'actionableCaseCount': actionableCases.length,
    'methods': _methodIds,
    'cases': cases.map((entry) => entry.toJson()).toList(growable: false),
    'actionableCases': actionableCases
        .map((entry) => entry.caseId)
        .toList(growable: false),
    'skippedFiles': skippedFiles,
    'thresholds': const {
      'catastrophicMedianErrorKm': 150,
      'slowFirstEstimateSeconds': 20,
      'highTailMinimumSpreadKm': 75,
      'lateDriftMinimumGrowthKm': 50,
      'comparisonMinimumDifferenceKm': 10,
      'comparisonRatio': 1.25,
    },
  };

  final output = File(jsonPath)..parent.createSync(recursive: true);
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  final markdown = File(markdownPath)..parent.createSync(recursive: true);
  markdown.writeAsStringSync(_markdown(cases, actionableCases, skippedFiles));

  stdout.writeln(
    'wrote ${cases.length} source-estimation case diagnostics '
    '(${actionableCases.length} actionable)',
  );
  stdout.writeln('json: ${output.path}');
  stdout.writeln('markdown: ${markdown.path}');
}

class _CaseDiagnostic {
  final String caseId;
  final String caseType;
  final String reportFile;
  final String? region;
  final String? truthSource;
  final String truthClass;
  final int requestedFrameCount;
  final int decodedFrameCount;
  final Map<String, _MethodDiagnostic> methods;
  final Map<String, Object?> detection;
  final List<String> flags;
  final List<String> recommendations;

  const _CaseDiagnostic({
    required this.caseId,
    required this.caseType,
    required this.reportFile,
    required this.region,
    required this.truthSource,
    required this.truthClass,
    required this.requestedFrameCount,
    required this.decodedFrameCount,
    required this.methods,
    required this.detection,
    required this.flags,
    required this.recommendations,
  });

  factory _CaseDiagnostic.fromReport(File file, Map<String, Object?> report) {
    final caseData = _map(report['case']);
    final summaries = _map(report['summaries']);
    final frames = _list(report['frames']);
    final truth = _map(caseData['truth']);
    final truthLat = _number(truth['latitude']);
    final truthLng = _number(truth['longitude']);
    final methods = <String, _MethodDiagnostic>{
      for (final methodId in _methodIds)
        methodId: _MethodDiagnostic.fromReport(
          methodId,
          _map(summaries[methodId]),
          frames,
          truthLatitude: truthLat,
          truthLongitude: truthLng,
        ),
    };
    final detectionSummary = _map(report['detectionSummary']);
    final classification = _map(caseData['classification']);
    final truthSource = truth['source']?.toString();
    final hybrid = methods[_hybridMethod]!;
    final centroid = methods[_centroidMethod]!;
    final scratch = methods[_scratchMethod]!;
    final flags = <String>[];
    final recommendations = <String>[];
    final caseType = caseData['caseType']?.toString() ?? 'unknown';

    if (caseType == 'event' && hybrid.estimateCount == 0) {
      flags.add('hybrid_no_estimate');
      recommendations.add(
        'Inspect source-trigger confirmation and member coherence before '
        'changing estimator weights.',
      );
    }
    if (hybrid.medianErrorKm case final value? when value >= 150) {
      flags.add('hybrid_catastrophic_location_error');
      recommendations.add(
        'Export member stations and timing picks; verify timestamp, station '
        'association and search bounds.',
      );
    }
    if (_meaningfullyWorse(hybrid.medianErrorKm, scratch.medianErrorKm)) {
      flags.add('hybrid_underperforms_scratch');
      recommendations.add(
        'Treat this as a regression countercase for the hybrid score.',
      );
    }
    if (_meaningfullyWorse(hybrid.medianErrorKm, centroid.medianErrorKm)) {
      flags.add('hybrid_underperforms_centroid');
      recommendations.add(
        'Keep the centroid result as a per-frame geometry diagnostic.',
      );
    }
    if (_hasHighTail(hybrid.medianErrorKm, hybrid.p90ErrorKm)) {
      flags.add('hybrid_high_error_tail');
      recommendations.add(
        'Inspect the frame where error starts growing and identify newly '
        'admitted or reactivated members.',
      );
    }
    if (_hasLateDrift(hybrid.firstErrorKm, hybrid.finalErrorKm)) {
      flags.add('hybrid_late_drift');
      recommendations.add(
        'Review stability-gate diagnostics and late member admission.',
      );
    }
    if (hybrid.hasOneSidedBoundaryEstimate) {
      flags.add('hybrid_one_sided_boundary_solution');
      recommendations.add(
        'Treat one-sided boundary solutions as low reliability unless '
        'independent residual or attenuation evidence supports them.',
      );
    }
    if ((hybrid.maxHorizontalUncertaintyP90Km ?? 0) >= 180) {
      flags.add('hybrid_high_geometry_uncertainty');
      recommendations.add(
        'Expose large horizontal uncertainty to UI and reports before '
        'changing production coordinates.',
      );
    }
    if ((hybrid.firstEstimateDelaySeconds ?? 0) > 20) {
      flags.add('slow_first_estimate');
      recommendations.add(
        'Separate detector confirmation delay from estimator runtime.',
      );
    }
    if (caseType == 'noise' && hybrid.estimateCount > 0) {
      flags.add('noise_false_estimate');
      recommendations.add(
        'Fix event triggering before evaluating source-location quality.',
      );
    }
    if ((report['decodedFrameCount'] as num? ?? 0).toInt() <
        (report['requestedFrameCount'] as num? ?? 0).toInt()) {
      flags.add('incomplete_replay_frames');
      recommendations.add(
        'Do not attribute discontinuities solely to the estimator.',
      );
    }

    return _CaseDiagnostic(
      caseId: caseData['caseId']?.toString() ?? file.uri.pathSegments.last,
      caseType: caseType,
      reportFile: file.path,
      region: classification['region']?.toString(),
      truthSource: truthSource,
      truthClass: _truthClass(truthSource),
      requestedFrameCount: (report['requestedFrameCount'] as num? ?? 0).toInt(),
      decodedFrameCount: (report['decodedFrameCount'] as num? ?? 0).toInt(),
      methods: methods,
      detection: {
        'firstCandidateDelaySeconds': _number(
          detectionSummary['firstCandidateDelaySeconds'],
        ),
        'firstConfirmedDelaySeconds': _number(
          detectionSummary['firstConfirmedDelaySeconds'],
        ),
        'missedCandidate': detectionSummary['missedCandidate'] == true,
        'missedConfirmed': detectionSummary['missedConfirmed'] == true,
        'maxActiveStationCount':
            (detectionSummary['maxActiveStationCount'] as num? ?? 0).toInt(),
      },
      flags: List.unmodifiable(flags),
      recommendations: List.unmodifiable(recommendations.toSet()),
    );
  }

  int get priorityScore {
    const weights = {
      'noise_false_estimate': 100,
      'hybrid_catastrophic_location_error': 90,
      'hybrid_no_estimate': 80,
      'hybrid_underperforms_scratch': 70,
      'hybrid_underperforms_centroid': 60,
      'hybrid_late_drift': 50,
      'hybrid_high_error_tail': 40,
      'hybrid_one_sided_boundary_solution': 35,
      'hybrid_high_geometry_uncertainty': 30,
      'slow_first_estimate': 20,
      'incomplete_replay_frames': 10,
    };
    return flags.fold(0, (sum, flag) => sum + (weights[flag] ?? 0));
  }

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'caseType': caseType,
    'reportFile': reportFile,
    'region': region,
    'truthSource': truthSource,
    'truthClass': truthClass,
    'requestedFrameCount': requestedFrameCount,
    'decodedFrameCount': decodedFrameCount,
    'detection': detection,
    'methods': {
      for (final entry in methods.entries) entry.key: entry.value.toJson(),
    },
    'flags': flags,
    'recommendations': recommendations,
    'priorityScore': priorityScore,
  };
}

class _MethodDiagnostic {
  final String methodId;
  final int estimateCount;
  final double? firstEstimateDelaySeconds;
  final double? firstErrorKm;
  final double? medianErrorKm;
  final double? p90ErrorKm;
  final double? finalErrorKm;
  final double? medianJumpKm;
  final double? p90JumpKm;
  final double? maximumErrorKm;
  final double? maximumJumpKm;
  final double? maxHorizontalUncertaintyP90Km;
  final bool hasOneSidedBoundaryEstimate;
  final _RiskSummary risk;
  final _CandidateCorrectionSummary candidateCorrections;
  final Map<String, Object?>? firstEstimate;
  final Map<String, Object?>? finalEstimate;
  final Map<String, Object?>? worstEstimate;
  final Map<String, Object?>? largestJumpEstimate;

  const _MethodDiagnostic({
    required this.methodId,
    required this.estimateCount,
    required this.firstEstimateDelaySeconds,
    required this.firstErrorKm,
    required this.medianErrorKm,
    required this.p90ErrorKm,
    required this.finalErrorKm,
    required this.medianJumpKm,
    required this.p90JumpKm,
    required this.maximumErrorKm,
    required this.maximumJumpKm,
    required this.maxHorizontalUncertaintyP90Km,
    required this.hasOneSidedBoundaryEstimate,
    required this.risk,
    required this.candidateCorrections,
    required this.firstEstimate,
    required this.finalEstimate,
    required this.worstEstimate,
    required this.largestJumpEstimate,
  });

  factory _MethodDiagnostic.fromReport(
    String methodId,
    Map<String, Object?> summary,
    List<Object?> frames, {
    required double? truthLatitude,
    required double? truthLongitude,
  }) {
    final estimatedFrames = <Map<String, Object?>>[];
    for (final rawFrame in frames) {
      final frame = _map(rawFrame);
      final method = _map(_map(frame['methods'])[methodId]);
      if (method['estimate'] is Map) {
        estimatedFrames.add(frame);
      }
    }
    final first = estimatedFrames.isEmpty ? null : estimatedFrames.first;
    final last = estimatedFrames.isEmpty ? null : estimatedFrames.last;
    final errors = <double>[];
    final jumps = <double>[];
    final horizontalUncertaintyP90 = <double>[];
    var hasOneSidedBoundaryEstimate = false;
    Map<String, Object?>? worstFrame;
    Map<String, Object?>? largestJumpFrame;
    for (final frame in estimatedFrames) {
      final method = _map(_map(frame['methods'])[methodId]);
      final estimate = _map(method['estimate']);
      final diagnostics = _map(estimate['diagnostics']);
      final error = _number(method['errorKm']);
      final jump = _number(method['jumpKm']);
      final uncertaintyP90 = _number(
        diagnostics['horizontal_uncertainty_p90_km'],
      );
      if (uncertaintyP90 != null) {
        horizontalUncertaintyP90.add(uncertaintyP90);
      }
      if (diagnostics['station_geometry'] == 'one_sided' &&
          diagnostics['search_boundary_hit'] == true) {
        hasOneSidedBoundaryEstimate = true;
      }
      if (error != null) {
        errors.add(error);
        if (worstFrame == null ||
            error >
                (_frameMetric(worstFrame, methodId, 'errorKm') ??
                    double.negativeInfinity)) {
          worstFrame = frame;
        }
      }
      if (jump != null) {
        jumps.add(jump);
        if (largestJumpFrame == null ||
            jump >
                (_frameMetric(largestJumpFrame, methodId, 'jumpKm') ??
                    double.negativeInfinity)) {
          largestJumpFrame = frame;
        }
      }
    }

    return _MethodDiagnostic(
      methodId: methodId,
      estimateCount:
          (summary['estimateCount'] as num? ?? estimatedFrames.length).toInt(),
      firstEstimateDelaySeconds: _number(summary['firstEstimateDelaySeconds']),
      firstErrorKm: _frameMetric(first, methodId, 'errorKm'),
      medianErrorKm: _number(summary['medianErrorKm']),
      p90ErrorKm: _number(summary['p90ErrorKm']),
      finalErrorKm: _frameMetric(last, methodId, 'errorKm'),
      medianJumpKm: _number(summary['medianJumpKm']),
      p90JumpKm: _number(summary['p90JumpKm']),
      maximumErrorKm: errors.isEmpty ? null : errors.reduce(_max),
      maximumJumpKm: jumps.isEmpty ? null : jumps.reduce(_max),
      maxHorizontalUncertaintyP90Km: horizontalUncertaintyP90.isEmpty
          ? null
          : horizontalUncertaintyP90.reduce(_max),
      hasOneSidedBoundaryEstimate: hasOneSidedBoundaryEstimate,
      risk: _RiskSummary.fromFrames(
        methodId,
        estimatedFrames,
        truthLatitude: truthLatitude,
        truthLongitude: truthLongitude,
      ),
      candidateCorrections: _CandidateCorrectionSummary.fromFrames(
        methodId,
        estimatedFrames,
        truthLatitude: truthLatitude,
        truthLongitude: truthLongitude,
      ),
      firstEstimate: _estimateSnapshot(
        first,
        methodId,
        truthLatitude: truthLatitude,
        truthLongitude: truthLongitude,
      ),
      finalEstimate: _estimateSnapshot(
        last,
        methodId,
        truthLatitude: truthLatitude,
        truthLongitude: truthLongitude,
      ),
      worstEstimate: _estimateSnapshot(
        worstFrame,
        methodId,
        truthLatitude: truthLatitude,
        truthLongitude: truthLongitude,
      ),
      largestJumpEstimate: _estimateSnapshot(
        largestJumpFrame,
        methodId,
        truthLatitude: truthLatitude,
        truthLongitude: truthLongitude,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'methodId': methodId,
    'estimateCount': estimateCount,
    'firstEstimateDelaySeconds': firstEstimateDelaySeconds,
    'firstErrorKm': firstErrorKm,
    'medianErrorKm': medianErrorKm,
    'p90ErrorKm': p90ErrorKm,
    'finalErrorKm': finalErrorKm,
    'medianJumpKm': medianJumpKm,
    'p90JumpKm': p90JumpKm,
    'maximumErrorKm': maximumErrorKm,
    'maximumJumpKm': maximumJumpKm,
    'maxHorizontalUncertaintyP90Km': maxHorizontalUncertaintyP90Km,
    'hasOneSidedBoundaryEstimate': hasOneSidedBoundaryEstimate,
    'risk': risk.toJson(),
    'candidateCorrections': candidateCorrections.toJson(),
    'firstEstimate': firstEstimate,
    'finalEstimate': finalEstimate,
    'worstEstimate': worstEstimate,
    'largestJumpEstimate': largestJumpEstimate,
  };
}

class _RiskSummary {
  final int estimatedFrameCount;
  final int largeErrorFrameCount;
  final int catastrophicErrorFrameCount;
  final int geometryRiskFrameCount;
  final int highTravelTimeResidualFrameCount;
  final int highRankInversionFrameCount;
  final int truthWorseTravelTimeFitFrameCount;
  final int largeErrorCoveredByGeometryRiskCount;
  final int largeErrorCoveredByTravelTimeResidualCount;
  final int largeErrorCoveredByRankRiskCount;
  final int largeErrorCoveredByAnyRiskCount;
  final double? maxEstimateRmsResidualSeconds;
  final double? maxTruthRmsResidualSeconds;
  final double? maxEstimateRankInversionRate;
  final double? maxTruthRankInversionRate;

  const _RiskSummary({
    required this.estimatedFrameCount,
    required this.largeErrorFrameCount,
    required this.catastrophicErrorFrameCount,
    required this.geometryRiskFrameCount,
    required this.highTravelTimeResidualFrameCount,
    required this.highRankInversionFrameCount,
    required this.truthWorseTravelTimeFitFrameCount,
    required this.largeErrorCoveredByGeometryRiskCount,
    required this.largeErrorCoveredByTravelTimeResidualCount,
    required this.largeErrorCoveredByRankRiskCount,
    required this.largeErrorCoveredByAnyRiskCount,
    required this.maxEstimateRmsResidualSeconds,
    required this.maxTruthRmsResidualSeconds,
    required this.maxEstimateRankInversionRate,
    required this.maxTruthRankInversionRate,
  });

  factory _RiskSummary.fromFrames(
    String methodId,
    List<Map<String, Object?>> frames, {
    required double? truthLatitude,
    required double? truthLongitude,
  }) {
    final risks = frames
        .map(
          (frame) => _FrameRisk.fromFrame(
            methodId,
            frame,
            truthLatitude: truthLatitude,
            truthLongitude: truthLongitude,
          ),
        )
        .whereType<_FrameRisk>()
        .toList(growable: false);

    var largeError = 0;
    var catastrophicError = 0;
    var geometryRisk = 0;
    var highTravelTimeResidual = 0;
    var highRankInversion = 0;
    var truthWorseTravelTimeFit = 0;
    var largeErrorCoveredByGeometryRisk = 0;
    var largeErrorCoveredByTravelTimeResidual = 0;
    var largeErrorCoveredByRankRisk = 0;
    var largeErrorCoveredByAnyRisk = 0;
    final estimateRmsValues = <double>[];
    final truthRmsValues = <double>[];
    final estimateRankValues = <double>[];
    final truthRankValues = <double>[];

    for (final risk in risks) {
      final hasLargeError = (risk.errorKm ?? 0) >= _largeErrorKm;
      final hasCatastrophicError = (risk.errorKm ?? 0) >= _catastrophicErrorKm;
      final hasGeometryRisk = risk.geometryRisk;
      final hasTravelTimeRisk = risk.highEstimateRmsResidual;
      final hasRankRisk = risk.highEstimateRankInversion;
      if (hasLargeError) largeError++;
      if (hasCatastrophicError) catastrophicError++;
      if (hasGeometryRisk) geometryRisk++;
      if (hasTravelTimeRisk) highTravelTimeResidual++;
      if (hasRankRisk) highRankInversion++;
      if (risk.truthWorseTravelTimeFit) truthWorseTravelTimeFit++;
      if (hasLargeError && hasGeometryRisk) {
        largeErrorCoveredByGeometryRisk++;
      }
      if (hasLargeError && hasTravelTimeRisk) {
        largeErrorCoveredByTravelTimeResidual++;
      }
      if (hasLargeError && hasRankRisk) {
        largeErrorCoveredByRankRisk++;
      }
      if (hasLargeError &&
          (hasGeometryRisk || hasTravelTimeRisk || hasRankRisk)) {
        largeErrorCoveredByAnyRisk++;
      }
      final estimateRms = risk.estimateRmsResidualSeconds;
      if (estimateRms != null) estimateRmsValues.add(estimateRms);
      final truthRms = risk.truthRmsResidualSeconds;
      if (truthRms != null) truthRmsValues.add(truthRms);
      final estimateRank = risk.estimateRankInversionRate;
      if (estimateRank != null) estimateRankValues.add(estimateRank);
      final truthRank = risk.truthRankInversionRate;
      if (truthRank != null) truthRankValues.add(truthRank);
    }

    return _RiskSummary(
      estimatedFrameCount: risks.length,
      largeErrorFrameCount: largeError,
      catastrophicErrorFrameCount: catastrophicError,
      geometryRiskFrameCount: geometryRisk,
      highTravelTimeResidualFrameCount: highTravelTimeResidual,
      highRankInversionFrameCount: highRankInversion,
      truthWorseTravelTimeFitFrameCount: truthWorseTravelTimeFit,
      largeErrorCoveredByGeometryRiskCount: largeErrorCoveredByGeometryRisk,
      largeErrorCoveredByTravelTimeResidualCount:
          largeErrorCoveredByTravelTimeResidual,
      largeErrorCoveredByRankRiskCount: largeErrorCoveredByRankRisk,
      largeErrorCoveredByAnyRiskCount: largeErrorCoveredByAnyRisk,
      maxEstimateRmsResidualSeconds: estimateRmsValues.isEmpty
          ? null
          : estimateRmsValues.reduce(_max),
      maxTruthRmsResidualSeconds: truthRmsValues.isEmpty
          ? null
          : truthRmsValues.reduce(_max),
      maxEstimateRankInversionRate: estimateRankValues.isEmpty
          ? null
          : estimateRankValues.reduce(_max),
      maxTruthRankInversionRate: truthRankValues.isEmpty
          ? null
          : truthRankValues.reduce(_max),
    );
  }

  double? get geometryRiskCoverage => largeErrorFrameCount == 0
      ? null
      : largeErrorCoveredByGeometryRiskCount / largeErrorFrameCount;

  double? get travelTimeRiskCoverage => largeErrorFrameCount == 0
      ? null
      : largeErrorCoveredByTravelTimeResidualCount / largeErrorFrameCount;

  double? get rankRiskCoverage => largeErrorFrameCount == 0
      ? null
      : largeErrorCoveredByRankRiskCount / largeErrorFrameCount;

  double? get anyRiskCoverage => largeErrorFrameCount == 0
      ? null
      : largeErrorCoveredByAnyRiskCount / largeErrorFrameCount;

  Map<String, Object?> toJson() => {
    'estimatedFrameCount': estimatedFrameCount,
    'largeErrorThresholdKm': _largeErrorKm,
    'catastrophicErrorThresholdKm': _catastrophicErrorKm,
    'largeErrorFrameCount': largeErrorFrameCount,
    'catastrophicErrorFrameCount': catastrophicErrorFrameCount,
    'geometryRiskFrameCount': geometryRiskFrameCount,
    'highTravelTimeResidualFrameCount': highTravelTimeResidualFrameCount,
    'highRankInversionFrameCount': highRankInversionFrameCount,
    'truthWorseTravelTimeFitFrameCount': truthWorseTravelTimeFitFrameCount,
    'largeErrorCoveredByGeometryRiskCount':
        largeErrorCoveredByGeometryRiskCount,
    'largeErrorCoveredByTravelTimeResidualCount':
        largeErrorCoveredByTravelTimeResidualCount,
    'largeErrorCoveredByRankRiskCount': largeErrorCoveredByRankRiskCount,
    'largeErrorCoveredByAnyRiskCount': largeErrorCoveredByAnyRiskCount,
    'geometryRiskCoverage': geometryRiskCoverage,
    'travelTimeRiskCoverage': travelTimeRiskCoverage,
    'rankRiskCoverage': rankRiskCoverage,
    'anyRiskCoverage': anyRiskCoverage,
    'maxEstimateRmsResidualSeconds': maxEstimateRmsResidualSeconds,
    'maxTruthRmsResidualSeconds': maxTruthRmsResidualSeconds,
    'maxEstimateRankInversionRate': maxEstimateRankInversionRate,
    'maxTruthRankInversionRate': maxTruthRankInversionRate,
  };
}

class _CandidateCorrectionSummary {
  final int candidateFrameCount;
  final int appliedFrameCount;
  final int largeErrorFrameCount;
  final int largeErrorCandidateFrameCount;
  final int largeErrorImprovedFrameCount;
  final double? medianErrorKm;
  final double? p90ErrorKm;

  const _CandidateCorrectionSummary({
    required this.candidateFrameCount,
    required this.appliedFrameCount,
    required this.largeErrorFrameCount,
    required this.largeErrorCandidateFrameCount,
    required this.largeErrorImprovedFrameCount,
    required this.medianErrorKm,
    required this.p90ErrorKm,
  });

  factory _CandidateCorrectionSummary.fromFrames(
    String methodId,
    List<Map<String, Object?>> frames, {
    required double? truthLatitude,
    required double? truthLongitude,
  }) {
    final candidateErrors = <double>[];
    var candidateFrames = 0;
    var appliedFrames = 0;
    var largeErrorFrames = 0;
    var largeErrorCandidateFrames = 0;
    var largeErrorImprovedFrames = 0;

    for (final frame in frames) {
      final baselineError = _frameMetric(frame, methodId, 'errorKm');
      final hasLargeError = (baselineError ?? 0) >= _largeErrorKm;
      if (hasLargeError) largeErrorFrames++;

      final candidate = _candidateCorrectionSnapshot(
        frame,
        methodId,
        truthLatitude: truthLatitude,
        truthLongitude: truthLongitude,
      );
      if (candidate == null) continue;
      candidateFrames++;
      if (candidate['applied'] == true) appliedFrames++;
      final candidateError = _number(candidate['errorKm']);
      if (candidateError != null) candidateErrors.add(candidateError);
      if (hasLargeError) {
        largeErrorCandidateFrames++;
        if (baselineError != null &&
            candidateError != null &&
            candidateError < baselineError) {
          largeErrorImprovedFrames++;
        }
      }
    }

    return _CandidateCorrectionSummary(
      candidateFrameCount: candidateFrames,
      appliedFrameCount: appliedFrames,
      largeErrorFrameCount: largeErrorFrames,
      largeErrorCandidateFrameCount: largeErrorCandidateFrames,
      largeErrorImprovedFrameCount: largeErrorImprovedFrames,
      medianErrorKm: _percentile(candidateErrors, 0.5),
      p90ErrorKm: _percentile(candidateErrors, 0.9),
    );
  }

  double? get largeErrorCandidateCoverage => largeErrorFrameCount == 0
      ? null
      : largeErrorCandidateFrameCount / largeErrorFrameCount;

  double? get largeErrorImprovementCoverage => largeErrorFrameCount == 0
      ? null
      : largeErrorImprovedFrameCount / largeErrorFrameCount;

  Map<String, Object?> toJson() => {
    'candidateFrameCount': candidateFrameCount,
    'appliedFrameCount': appliedFrameCount,
    'largeErrorFrameCount': largeErrorFrameCount,
    'largeErrorCandidateFrameCount': largeErrorCandidateFrameCount,
    'largeErrorImprovedFrameCount': largeErrorImprovedFrameCount,
    'largeErrorCandidateCoverage': largeErrorCandidateCoverage,
    'largeErrorImprovementCoverage': largeErrorImprovementCoverage,
    'medianErrorKm': medianErrorKm,
    'p90ErrorKm': p90ErrorKm,
  };
}

class _FrameRisk {
  final double? errorKm;
  final bool geometryRisk;
  final double? estimateRmsResidualSeconds;
  final double? truthRmsResidualSeconds;
  final double? estimateRankInversionRate;
  final double? truthRankInversionRate;
  final bool highEstimateRmsResidual;
  final bool highEstimateRankInversion;
  final bool truthWorseTravelTimeFit;

  const _FrameRisk({
    required this.errorKm,
    required this.geometryRisk,
    required this.estimateRmsResidualSeconds,
    required this.truthRmsResidualSeconds,
    required this.estimateRankInversionRate,
    required this.truthRankInversionRate,
    required this.highEstimateRmsResidual,
    required this.highEstimateRankInversion,
    required this.truthWorseTravelTimeFit,
  });

  factory _FrameRisk.fromFrame(
    String methodId,
    Map<String, Object?> frame, {
    required double? truthLatitude,
    required double? truthLongitude,
  }) {
    final method = _map(_map(frame['methods'])[methodId]);
    final estimate = _map(method['estimate']);
    final estimateLat = _number(estimate['latitude']);
    final estimateLng = _number(estimate['longitude']);
    if (estimateLat == null || estimateLng == null) {
      return _FrameRisk(
        errorKm: _number(method['errorKm']),
        geometryRisk: false,
        estimateRmsResidualSeconds: null,
        truthRmsResidualSeconds: null,
        estimateRankInversionRate: null,
        truthRankInversionRate: null,
        highEstimateRmsResidual: false,
        highEstimateRankInversion: false,
        truthWorseTravelTimeFit: false,
      );
    }
    final diagnostics = _map(estimate['diagnostics']);
    final geometryRisk =
        (diagnostics['station_geometry'] == 'one_sided' &&
            diagnostics['search_boundary_hit'] == true) ||
        ((_number(diagnostics['horizontal_uncertainty_p90_km']) ?? 0) >=
            _highGeometryUncertaintyP90Km);
    final residuals = _travelTimeResiduals(
      diagnostics,
      estimateLatitude: estimateLat,
      estimateLongitude: estimateLng,
      truthLatitude: truthLatitude,
      truthLongitude: truthLongitude,
    );
    final estimateRms = residuals.$1;
    final truthRms = residuals.$2;
    final highEstimateRms =
        estimateRms != null && estimateRms >= _highTravelTimeRmsSeconds;
    final estimateRankInversion = _rankInversionRate(
      diagnostics,
      latitude: estimateLat,
      longitude: estimateLng,
    );
    final truthRankInversion = truthLatitude == null || truthLongitude == null
        ? null
        : _rankInversionRate(
            diagnostics,
            latitude: truthLatitude,
            longitude: truthLongitude,
          );
    final highRankInversion =
        estimateRankInversion != null &&
        estimateRankInversion >= _highRankInversionRate;
    final truthWorse =
        estimateRms != null && truthRms != null && truthRms > estimateRms * 1.4;

    return _FrameRisk(
      errorKm: _number(method['errorKm']),
      geometryRisk: geometryRisk,
      estimateRmsResidualSeconds: estimateRms,
      truthRmsResidualSeconds: truthRms,
      estimateRankInversionRate: estimateRankInversion,
      truthRankInversionRate: truthRankInversion,
      highEstimateRmsResidual: highEstimateRms,
      highEstimateRankInversion: highRankInversion,
      truthWorseTravelTimeFit: truthWorse,
    );
  }
}

Map<String, Object?>? _estimateSnapshot(
  Map<String, Object?>? frame,
  String methodId, {
  required double? truthLatitude,
  required double? truthLongitude,
}) {
  if (frame == null) return null;
  final method = _map(_map(frame['methods'])[methodId]);
  final estimate = _map(method['estimate']);
  if (estimate.isEmpty) return null;
  final diagnostics = _map(estimate['diagnostics']);
  return {
    'observedAtJst': frame['observedAtJst'],
    'errorKm': _number(method['errorKm']),
    'jumpKm': _number(method['jumpKm']),
    'latitude': _number(estimate['latitude']),
    'longitude': _number(estimate['longitude']),
    'supportingStationCount': (estimate['supportingStationCount'] as num?)
        ?.toInt(),
    'confidence': _number(estimate['confidence']),
    'timeScore': _number(diagnostics['time_score']),
    'rankScore': _number(diagnostics['rank_score']),
    'geometryPenalty': _number(diagnostics['geometry_penalty']),
    'finalScore': _number(diagnostics['final_score']),
    'stationGeometry': diagnostics['station_geometry']?.toString(),
    'stationAzimuthalGapDeg': _number(diagnostics['station_azimuthal_gap_deg']),
    'nearestStationDistanceKm': _number(
      diagnostics['nearest_station_distance_km'],
    ),
    'searchBoundaryMarginDeg': _number(
      diagnostics['search_boundary_margin_deg'],
    ),
    'searchBoundaryHit': diagnostics['search_boundary_hit'] == true,
    'horizontalUncertaintyP50Km': _number(
      diagnostics['horizontal_uncertainty_p50_km'],
    ),
    'horizontalUncertaintyP90Km': _number(
      diagnostics['horizontal_uncertainty_p90_km'],
    ),
    'searchBounds': diagnostics['search_bbox'],
    'topTimingPicks': diagnostics['top_timing_picks'],
    'candidateCorrection': _candidateCorrectionSnapshot(
      frame,
      methodId,
      truthLatitude: truthLatitude,
      truthLongitude: truthLongitude,
    ),
  };
}

Map<String, Object?>? _candidateCorrectionSnapshot(
  Map<String, Object?>? frame,
  String methodId, {
  required double? truthLatitude,
  required double? truthLongitude,
}) {
  if (frame == null) return null;
  final method = _map(_map(frame['methods'])[methodId]);
  final estimate = _map(method['estimate']);
  if (estimate.isEmpty) return null;
  final diagnostics = _map(estimate['diagnostics']);
  final corrections = _map(diagnostics['candidate_corrections']);
  final guard = _map(corrections['one_sided_boundary_centroid_guard']);
  final latitude = _number(guard['latitude']);
  final longitude = _number(guard['longitude']);
  if (latitude == null || longitude == null) return null;
  final baselineError = _number(method['errorKm']);
  final candidateError = truthLatitude == null || truthLongitude == null
      ? null
      : _haversineKm(latitude, longitude, truthLatitude, truthLongitude);
  return {
    'type': 'one_sided_boundary_centroid_guard',
    'latitude': latitude,
    'longitude': longitude,
    'errorKm': candidateError,
    'baselineErrorKm': baselineError,
    'improvementKm': baselineError == null || candidateError == null
        ? null
        : baselineError - candidateError,
    'applied': guard['applied'] == true,
    'score': _number(guard['score']),
    'timeScore': _number(guard['time_score']),
    'rankScore': _number(guard['rank_score']),
    'geometryPenalty': _number(guard['geometry_penalty']),
    'referenceDistanceKm': _number(guard['reference_distance_km']),
    'trigger': guard['trigger'],
  };
}

double? _frameMetric(
  Map<String, Object?>? frame,
  String methodId,
  String metric,
) {
  if (frame == null) return null;
  return _number(_map(_map(frame['methods'])[methodId])[metric]);
}

bool _meaningfullyWorse(double? subject, double? baseline) {
  if (subject == null || baseline == null) return false;
  return subject >= baseline * 1.25 && subject - baseline >= 10;
}

bool _hasHighTail(double? median, double? p90) {
  if (median == null || p90 == null) return false;
  return p90 >= median * 2.5 && p90 - median >= 75;
}

bool _hasLateDrift(double? first, double? finalValue) {
  if (first == null || finalValue == null) return false;
  return finalValue >= first * 1.75 && finalValue - first >= 50;
}

int _comparePriority(_CaseDiagnostic left, _CaseDiagnostic right) {
  final priority = right.priorityScore.compareTo(left.priorityScore);
  return priority != 0 ? priority : left.caseId.compareTo(right.caseId);
}

String _markdown(
  List<_CaseDiagnostic> cases,
  List<_CaseDiagnostic> actionableCases,
  List<Map<String, Object?>> skippedFiles,
) {
  final buffer = StringBuffer()
    ..writeln('# Source Estimation Countercase Report')
    ..writeln()
    ..writeln(
      '> Generated by `tools/build_source_estimation_countercase_report.dart`.',
    )
    ..writeln('> Do not tune production weights from a single case.')
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('- Cases parsed: ${cases.length}')
    ..writeln('- Actionable cases: ${actionableCases.length}')
    ..writeln('- Skipped JSON files: ${skippedFiles.length}')
    ..writeln()
    ..writeln('## Method Comparison')
    ..writeln()
    ..writeln(
      '| Case | Truth | Hybrid first / median / P90 / final | '
      'Centroid median | Scratch median | Estimate delay | Flags |',
    )
    ..writeln('|---|---|---:|---:|---:|---:|---|');

  for (final entry in cases) {
    final hybrid = entry.methods[_hybridMethod]!;
    final centroid = entry.methods[_centroidMethod]!;
    final scratch = entry.methods[_scratchMethod]!;
    final truth = switch (entry.truthClass) {
      'jma_verified' => 'JMA verified',
      'reference' => 'reference',
      _ => '--',
    };
    buffer.writeln(
      '| `${entry.caseId}` | $truth | '
      '${_metric(hybrid.firstErrorKm)} / '
      '${_metric(hybrid.medianErrorKm)} / '
      '${_metric(hybrid.p90ErrorKm)} / '
      '${_metric(hybrid.finalErrorKm)} | '
      '${_metric(centroid.medianErrorKm)} | '
      '${_metric(scratch.medianErrorKm)} | '
      '${_seconds(hybrid.firstEstimateDelaySeconds)} | '
      '${entry.flags.isEmpty ? '--' : entry.flags.map((flag) => '`$flag`').join('<br>')} |',
    );
  }

  buffer
    ..writeln()
    ..writeln('## Priority Countercases')
    ..writeln();
  if (actionableCases.isEmpty) {
    buffer.writeln('No countercases crossed the configured thresholds.');
  } else {
    for (final entry in actionableCases) {
      final hybrid = entry.methods[_hybridMethod]!;
      buffer
        ..writeln('### `${entry.caseId}`')
        ..writeln()
        ..writeln('- Region: ${entry.region ?? '--'}')
        ..writeln('- Truth source: `${entry.truthSource ?? 'unknown'}`')
        ..writeln(
          '- Hybrid first/median/P90/final error: '
          '${_metric(hybrid.firstErrorKm)} / '
          '${_metric(hybrid.medianErrorKm)} / '
          '${_metric(hybrid.p90ErrorKm)} / '
          '${_metric(hybrid.finalErrorKm)}',
        )
        ..writeln(
          '- Hybrid worst frame/error: '
          '${hybrid.worstEstimate?['observedAtJst'] ?? '--'} / '
          '${_metric(hybrid.maximumErrorKm)}',
        )
        ..writeln(
          '- Hybrid worst geometry: ${_geometrySummary(hybrid.worstEstimate)}',
        )
        ..writeln(
          '- Hybrid max horizontal uncertainty P90: '
          '${_metric(hybrid.maxHorizontalUncertaintyP90Km)}',
        )
        ..writeln('- Risk coverage: ${_riskSummary(hybrid.risk)}')
        ..writeln(
          '- Candidate correction: '
          '${_candidateCorrectionSummary(hybrid)}',
        )
        ..writeln(
          '- Detection candidate/confirmation: '
          '${_seconds(_number(entry.detection['firstCandidateDelaySeconds']))} / '
          '${_seconds(_number(entry.detection['firstConfirmedDelaySeconds']))}',
        )
        ..writeln(
          '- Flags: ${entry.flags.map((flag) => '`$flag`').join(', ')}',
        );
      for (final recommendation in entry.recommendations) {
        buffer.writeln('- Action: $recommendation');
      }
      buffer.writeln();
    }
  }

  buffer
    ..writeln('## Interpretation')
    ..writeln()
    ..writeln(
      '- `hybrid_underperforms_centroid` means timing/rank scoring is worse '
      'than a simple geometry baseline for that event.',
    )
    ..writeln(
      '- `hybrid_underperforms_scratch` is a severe regression because the '
      'Scratch scan is retained only as a weak historical baseline.',
    )
    ..writeln(
      '- `hybrid_high_error_tail` identifies unstable late frames even when '
      'the median remains acceptable.',
    )
    ..writeln(
      '- `hybrid_one_sided_boundary_solution` marks an estimate supported from '
      'one side while also hitting the station-derived search boundary.',
    )
    ..writeln(
      '- `hybrid_high_geometry_uncertainty` means the estimator already reports '
      'a P90 horizontal uncertainty of at least 180 km on some frame.',
    )
    ..writeln(
      '- `hybrid_no_estimate` must first be diagnosed at the independent '
      'source-trigger layer.',
    );
  return buffer.toString();
}

String _metric(double? value) => value == null ? '--' : '${_compact(value)} km';

String _seconds(double? value) => value == null ? '--' : '${_compact(value)} s';

String _geometrySummary(Map<String, Object?>? snapshot) {
  if (snapshot == null) return '--';
  final geometry = snapshot['stationGeometry']?.toString() ?? '--';
  final gap = _degrees(_number(snapshot['stationAzimuthalGapDeg']));
  final nearest = _metric(_number(snapshot['nearestStationDistanceKm']));
  final margin = _degrees(_number(snapshot['searchBoundaryMarginDeg']));
  final boundary = snapshot['searchBoundaryHit'] == true ? 'boundary' : 'inner';
  final p90 = _metric(_number(snapshot['horizontalUncertaintyP90Km']));
  return '$geometry, gap $gap, nearest $nearest, margin $margin, '
      '$boundary, P90u $p90';
}

String _riskSummary(_RiskSummary risk) {
  return 'large-error ${risk.largeErrorFrameCount}/${risk.estimatedFrameCount}, '
      'geom ${_percent(risk.geometryRiskCoverage)}, '
      'tt ${_percent(risk.travelTimeRiskCoverage)}, '
      'rank ${_percent(risk.rankRiskCoverage)}, '
      'any ${_percent(risk.anyRiskCoverage)}, '
      'max est/truth RMS '
      '${_seconds(risk.maxEstimateRmsResidualSeconds)} / '
      '${_seconds(risk.maxTruthRmsResidualSeconds)}, '
      'max est/truth rank inv '
      '${_percent(risk.maxEstimateRankInversionRate)} / '
      '${_percent(risk.maxTruthRankInversionRate)}';
}

String _candidateCorrectionSummary(_MethodDiagnostic method) {
  final summary = method.candidateCorrections;
  if (summary.candidateFrameCount == 0) {
    return 'none';
  }
  final worstCandidate = _map(method.worstEstimate?['candidateCorrection']);
  final worstText = worstCandidate.isEmpty
      ? 'worst-frame --'
      : 'worst-frame ${_metric(_number(worstCandidate['baselineErrorKm']))} -> '
            '${_metric(_number(worstCandidate['errorKm']))}';
  return 'frames ${summary.candidateFrameCount}, '
      'applied ${summary.appliedFrameCount}, '
      'median/P90 ${_metric(summary.medianErrorKm)} / '
      '${_metric(summary.p90ErrorKm)}, '
      'large-error coverage '
      '${summary.largeErrorCandidateFrameCount}/${summary.largeErrorFrameCount}, '
      'improved ${summary.largeErrorImprovedFrameCount}/'
      '${summary.largeErrorFrameCount}, '
      '$worstText';
}

String _degrees(double? value) =>
    value == null ? '--deg' : '${_compact(value)} deg';

String _percent(double? value) =>
    value == null ? '--' : '${(value * 100).round()}%';

String _compact(double value) {
  final rounded = value.toStringAsFixed(1);
  return rounded.endsWith('.0')
      ? rounded.substring(0, rounded.length - 2)
      : rounded;
}

(double?, double?) _travelTimeResiduals(
  Map<String, Object?> diagnostics, {
  required double estimateLatitude,
  required double estimateLongitude,
  required double? truthLatitude,
  required double? truthLongitude,
}) {
  final picks = <_PickInput>[];
  for (final rawPick in _list(diagnostics['top_timing_picks'])) {
    final pick = _map(rawPick);
    final code = pick['code']?.toString();
    final delay = _number(pick['delay_s']);
    if (code == null || delay == null) continue;
    final station = _stationIndex[code];
    if (station == null) continue;
    picks.add(_PickInput(station: station, observedDelaySeconds: delay));
  }
  if (picks.isEmpty) return (null, null);

  final estimateDistances = picks
      .map(
        (pick) => _haversineKm(
          estimateLatitude,
          estimateLongitude,
          pick.station.latitude,
          pick.station.longitude,
        ),
      )
      .toList(growable: false);
  final estimateRms = _relativeTravelTimeRms(picks, estimateDistances);
  double? truthRms;
  if (truthLatitude != null && truthLongitude != null) {
    final truthDistances = picks
        .map(
          (pick) => _haversineKm(
            truthLatitude,
            truthLongitude,
            pick.station.latitude,
            pick.station.longitude,
          ),
        )
        .toList(growable: false);
    truthRms = _relativeTravelTimeRms(picks, truthDistances);
  }
  return (estimateRms, truthRms);
}

double? _rankInversionRate(
  Map<String, Object?> diagnostics, {
  required double latitude,
  required double longitude,
}) {
  final inputs = <({double value, double distanceKm})>[];
  for (final rawPick in _list(diagnostics['top_timing_picks'])) {
    final pick = _map(rawPick);
    final code = pick['code']?.toString();
    final value = _number(pick['value']);
    if (code == null || value == null) continue;
    final station = _stationIndex[code];
    if (station == null) continue;
    inputs.add((
      value: value,
      distanceKm: _haversineKm(
        latitude,
        longitude,
        station.latitude,
        station.longitude,
      ),
    ));
  }
  var comparable = 0;
  var inversions = 0;
  for (var left = 0; left < inputs.length; left++) {
    for (var right = left + 1; right < inputs.length; right++) {
      final valueDiff = inputs[left].value - inputs[right].value;
      if (valueDiff.abs() < 0.05) continue;
      comparable++;
      final distanceDiff = inputs[left].distanceKm - inputs[right].distanceKm;
      if ((valueDiff > 0 && distanceDiff > 0) ||
          (valueDiff < 0 && distanceDiff < 0)) {
        inversions++;
      }
    }
  }
  return comparable == 0 ? null : inversions / comparable;
}

double? _relativeTravelTimeRms(
  List<_PickInput> picks,
  List<double> distancesKm,
) {
  if (picks.isEmpty || distancesKm.isEmpty) return null;
  final minDistance = distancesKm.reduce((a, b) => a < b ? a : b);
  var squareSum = 0.0;
  for (var index = 0; index < picks.length; index++) {
    final predicted = (distancesKm[index] - minDistance) / _waveSpeedKmPerSec;
    final residual = picks[index].observedDelaySeconds - predicted;
    squareSum += residual * residual;
  }
  return math.sqrt(squareSum / picks.length);
}

double _haversineKm(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadiusKm = 6371.0;
  final latA = _degToRad(latitudeA);
  final latB = _degToRad(latitudeB);
  final deltaLat = _degToRad(latitudeB - latitudeA);
  final deltaLon = _degToRad(longitudeB - longitudeA);
  final a =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(latA) *
          math.cos(latB) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _degToRad(double degrees) => degrees * math.pi / 180.0;

Map<String, _StationMeta> _buildStationIndex() {
  final result = <String, _StationMeta>{};
  for (final entry in NiedStationDb.stations) {
    final code = entry['code']?.toString();
    final latitude = _number(entry['lat']);
    final longitude = _number(entry['lng']);
    if (code == null || latitude == null || longitude == null) continue;
    result[code] = _StationMeta(
      code: code,
      latitude: latitude,
      longitude: longitude,
    );
  }
  return result;
}

class _PickInput {
  final _StationMeta station;
  final double observedDelaySeconds;

  const _PickInput({required this.station, required this.observedDelaySeconds});
}

class _StationMeta {
  final String code;
  final double latitude;
  final double longitude;

  const _StationMeta({
    required this.code,
    required this.latitude,
    required this.longitude,
  });
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }
  return const {};
}

List<Object?> _list(Object? value) => value is List ? value : const [];

double? _number(Object? value) => value is num ? value.toDouble() : null;

double _max(double left, double right) => left > right ? left : right;

double? _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index.clamp(0, sorted.length - 1)];
}

String _truthClass(String? source) {
  if (source == null || source.isEmpty) return 'unknown';
  return source.toLowerCase().startsWith('jma_') ? 'jma_verified' : 'reference';
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
