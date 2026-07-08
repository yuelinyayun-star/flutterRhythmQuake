import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';
import 'package:latlong2/latlong.dart';

import 'support/source_estimation_benchmark.dart';

const _largeErrorKm = 100.0;
const _baselineVariant = 'baseline';
const _diagnosticVariant = 'centroid_guard_high_uncertainty_diagnostic';
const _appliedGuardVariant = 'centroid_guard_high_uncertainty';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'offshore geometry variants produce a comparison report',
    () async {
      const fixtures = <String>[
        'nara_m36.json',
        'iwate_offshore_m34_ref.json',
        'fukushima_offshore_m32_20260621_eq6.json',
        'iwate_east_offshore_m30_20260622_hinet.json',
        'iwate_offshore_m30_20260622_eq10.json',
        'kushiro_offshore_m30_20260622_jma.json',
        'tomakomai_south_offshore_m35_20260622_hinet.json',
      ];
      const variants = <String, NiedGifHybridSourceEstimator>{
        'baseline': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
        ),
        'expanded': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
          bboxPaddingDeg: 1.80,
        ),
        'expanded_weak_center': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
          bboxPaddingDeg: 1.80,
          centerDistancePenaltyPerKm: 0.003,
        ),
        'centroid_guard': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
          useOneSidedBoundaryCentroidGuard: true,
        ),
        'centroid_guard_high_uncertainty': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
          useOneSidedBoundaryCentroidGuard: true,
          oneSidedBoundaryCentroidGuardMinUncertaintyP90Km: 180.0,
          oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm: 80.0,
        ),
        'centroid_guard_high_uncertainty_diagnostic':
            NiedGifHybridSourceEstimator(
              fallback: WeightedCentroidSourceEstimator(),
              emitOneSidedBoundaryCentroidGuardCandidate: true,
              oneSidedBoundaryCentroidGuardMinUncertaintyP90Km: 180.0,
              oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm: 80.0,
            ),
        'soft_geometry_001': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
          oneSidedBoundaryPenaltyPerKm: 0.01,
        ),
        'soft_geometry_003': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
          oneSidedBoundaryPenaltyPerKm: 0.03,
        ),
        'soft_geometry_010': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
          oneSidedBoundaryPenaltyPerKm: 0.10,
        ),
        'soft_geometry_030': NiedGifHybridSourceEstimator(
          fallback: WeightedCentroidSourceEstimator(),
          oneSidedBoundaryPenaltyPerKm: 0.30,
        ),
      };
      final rows = <Map<String, Object?>>[];

      for (final fixture in fixtures) {
        final replayCase = SourceEstimationReplayCase.fromManifest(
          File('test/fixtures/source_estimation/$fixture'),
          workspaceRoot: Directory.current,
        );
        if (!replayCase.captureDirectory.existsSync()) {
          rows.add({
            'caseId': replayCase.caseId,
            'variant': 'all',
            'skipped': true,
            'reason': 'missing_capture',
          });
          continue;
        }
        for (final variant in variants.entries) {
          final report = await SourceEstimationBenchmarkRunner(
            replayCase,
            hybridEstimator: variant.value,
          ).run();
          final summary =
              report.summaries[SourceEstimationBenchmarkRunner.hybridMethod]!;
          final candidateSummary = _candidateCorrectionSummary(
            report,
            replayCase.truth?.epicenter,
          );
          rows.add({
            'caseId': replayCase.caseId,
            'region': replayCase.classification['region'],
            'variant': variant.key,
            'estimateCount': summary.estimateCount,
            'firstEstimateDelaySeconds': summary.firstEstimateDelaySeconds,
            'medianErrorKm': summary.medianErrorKm,
            'p90ErrorKm': summary.p90ErrorKm,
            'medianJumpKm': summary.medianJumpKm,
            'p90JumpKm': summary.p90JumpKm,
            'p95RuntimeMicros': summary.p95RuntimeMicros,
            'candidateCorrectionCount': candidateSummary.count,
            'candidateAppliedFrameCount': candidateSummary.appliedCount,
            'candidateMedianErrorKm': candidateSummary.medianErrorKm,
            'candidateP90ErrorKm': candidateSummary.p90ErrorKm,
            'largeErrorFrameCount': candidateSummary.largeErrorFrameCount,
            'largeErrorCandidateFrameCount':
                candidateSummary.largeErrorCandidateFrameCount,
            'largeErrorImprovedFrameCount':
                candidateSummary.largeErrorImprovedFrameCount,
          });
        }
      }

      final promotionMatrix = _promotionMatrix(rows);
      final output = File(
        '.dart_tool/source_estimation_offshore_geometry_experiment/report.json',
      )..parent.createSync(recursive: true);
      output.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 'source_estimation_offshore_geometry_experiment_v2',
          'variants': {
            'baseline': {'bboxPaddingDeg': 0.60, 'centerDistancePenaltyPerKm': 0.015},
            'expanded': {'bboxPaddingDeg': 1.80, 'centerDistancePenaltyPerKm': 0.015},
            'expanded_weak_center': {'bboxPaddingDeg': 1.80, 'centerDistancePenaltyPerKm': 0.003},
            'centroid_guard': {'bboxPaddingDeg': 0.60, 'centerDistancePenaltyPerKm': 0.015, 'useOneSidedBoundaryCentroidGuard': true},
            'centroid_guard_high_uncertainty': {'bboxPaddingDeg': 0.60, 'centerDistancePenaltyPerKm': 0.015, 'useOneSidedBoundaryCentroidGuard': true, 'oneSidedBoundaryCentroidGuardMinUncertaintyP90Km': 180.0, 'oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm': 80.0},
            'centroid_guard_high_uncertainty_diagnostic': {'bboxPaddingDeg': 0.60, 'centerDistancePenaltyPerKm': 0.015, 'emitOneSidedBoundaryCentroidGuardCandidate': true, 'oneSidedBoundaryCentroidGuardMinUncertaintyP90Km': 180.0, 'oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm': 80.0},
            'soft_geometry_001': {'bboxPaddingDeg': 0.60, 'centerDistancePenaltyPerKm': 0.015, 'oneSidedBoundaryPenaltyPerKm': 0.01, 'oneSidedBoundarySupportedDistanceKm': 60.0},
            'soft_geometry_003': {'bboxPaddingDeg': 0.60, 'centerDistancePenaltyPerKm': 0.015, 'oneSidedBoundaryPenaltyPerKm': 0.03, 'oneSidedBoundarySupportedDistanceKm': 60.0},
            'soft_geometry_010': {'bboxPaddingDeg': 0.60, 'centerDistancePenaltyPerKm': 0.015, 'oneSidedBoundaryPenaltyPerKm': 0.10, 'oneSidedBoundarySupportedDistanceKm': 60.0},
            'soft_geometry_030': {'bboxPaddingDeg': 0.60, 'centerDistancePenaltyPerKm': 0.015, 'oneSidedBoundaryPenaltyPerKm': 0.30, 'oneSidedBoundarySupportedDistanceKm': 60.0},
          },
          'promotionMatrix': promotionMatrix.map((row) => row.toJson()).toList(growable: false),
          'rows': rows,
        })}\n',
      );
      final markdown = File(
        'docs/baselines/source_estimation_offshore_geometry_experiment.generated.md',
      )..parent.createSync(recursive: true);
      markdown.writeAsStringSync(_markdown(rows));

      expect(rows.where((row) => row['skipped'] == true), isEmpty);
      expect(rows, hasLength(fixtures.length * variants.length));
      final tomakomaiBaseline = _row(
        rows,
        '20260622_tomakomai_south_offshore_m35_hinet',
        'baseline',
      );
      final tomakomaiDiagnostic = _row(
        rows,
        '20260622_tomakomai_south_offshore_m35_hinet',
        'centroid_guard_high_uncertainty_diagnostic',
      );
      expect(
        tomakomaiDiagnostic['p90ErrorKm'],
        tomakomaiBaseline['p90ErrorKm'],
      );
      expect(tomakomaiDiagnostic['candidateCorrectionCount'], greaterThan(0));
      expect(tomakomaiDiagnostic['candidateAppliedFrameCount'], 0);
      expect(
        tomakomaiDiagnostic['candidateP90ErrorKm'] as double,
        lessThan(tomakomaiDiagnostic['p90ErrorKm'] as double),
      );
      expect(
        _promotionDecision(
          promotionMatrix,
          '20260622_tomakomai_south_offshore_m35_hinet',
        ),
        'positive_boundary_candidate',
      );
      expect(
        _promotionDecision(
          promotionMatrix,
          '20260622_kushiro_offshore_m30_jma',
        ),
        'positive_boundary_candidate',
      );
      expect(
        _promotionDecision(promotionMatrix, '20260620_iwate_offshore_m34_ref'),
        'pass_no_candidate',
      );
      expect(
        _promotionDecision(
          promotionMatrix,
          '20260621_fukushima_offshore_m32_eq6',
        ),
        'reject_as_primary_fix',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Map<String, Object?> _row(
  List<Map<String, Object?>> rows,
  String caseId,
  String variant,
) {
  return rows.singleWhere(
    (row) => row['caseId'] == caseId && row['variant'] == variant,
  );
}

String _markdown(List<Map<String, Object?>> rows) {
  final matrix = _promotionMatrix(rows);
  final buffer = StringBuffer()
    ..writeln('# Offshore Search Geometry Experiment')
    ..writeln()
    ..writeln(
      '> Experimental replay only. Production remains on the baseline variant.',
    )
    ..writeln()
    ..writeln('## Promotion/Rejection Matrix')
    ..writeln()
    ..writeln(
      '| Case | Baseline P90 | Applied guard P90 | Candidate P90 | Candidate frames | Large-error coverage | Improved coverage | Decision | Reason |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |');
  for (final row in matrix) {
    buffer.writeln(
      '| `${row.caseId}` | '
      '${_number(row.baselineP90ErrorKm, 'km')} | '
      '${_number(row.appliedGuardP90ErrorKm, 'km')} | '
      '${_number(row.candidateP90ErrorKm, 'km')} | '
      '${row.candidateFrameCount} | '
      '${_ratio(row.largeErrorCandidateFrameCount, row.largeErrorFrameCount)} | '
      '${_ratio(row.largeErrorImprovedFrameCount, row.largeErrorFrameCount)} | '
      '`${row.decision}` | '
      '${row.reason} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('## Variant Replay Table')
    ..writeln()
    ..writeln(
      '| Case | Variant | Estimates | First delay | Median error | P90 error | P90 jump | Candidate frames | Candidate median | Candidate P90 | P95 runtime |',
    )
    ..writeln(
      '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );
  for (final row in rows) {
    if (row['skipped'] == true) {
      buffer.writeln(
        '| `${row['caseId']}` | skipped | - | - | - | - | - | - | - | - | - |',
      );
      continue;
    }
    buffer.writeln(
      '| `${row['caseId']}` | `${row['variant']}` | '
      '${row['estimateCount']} | '
      '${_number(row['firstEstimateDelaySeconds'], 's')} | '
      '${_number(row['medianErrorKm'], 'km')} | '
      '${_number(row['p90ErrorKm'], 'km')} | '
      '${_number(row['p90JumpKm'], 'km')} | '
      '${row['candidateCorrectionCount']} | '
      '${_number(row['candidateMedianErrorKm'], 'km')} | '
      '${_number(row['candidateP90ErrorKm'], 'km')} | '
      '${_number(row['p95RuntimeMicros'], 'us')} |',
    );
  }
  return buffer.toString();
}

List<_PromotionMatrixRow> _promotionMatrix(List<Map<String, Object?>> rows) {
  final caseIds =
      rows
          .where((row) => row['skipped'] != true)
          .map((row) => row['caseId']! as String)
          .toSet()
          .toList()
        ..sort();
  return [
    for (final caseId in caseIds)
      _promotionMatrixRow(
        caseId: caseId,
        baseline: _row(rows, caseId, _baselineVariant),
        diagnostic: _row(rows, caseId, _diagnosticVariant),
        appliedGuard: _row(rows, caseId, _appliedGuardVariant),
      ),
  ];
}

_PromotionMatrixRow _promotionMatrixRow({
  required String caseId,
  required Map<String, Object?> baseline,
  required Map<String, Object?> diagnostic,
  required Map<String, Object?> appliedGuard,
}) {
  final baselineP90 = _asDouble(baseline['p90ErrorKm']);
  final appliedGuardP90 = _asDouble(appliedGuard['p90ErrorKm']);
  final candidateP90 = _asDouble(diagnostic['candidateP90ErrorKm']);
  final candidateFrameCount =
      (diagnostic['candidateCorrectionCount'] as num?)?.toInt() ?? 0;
  final largeErrorFrameCount =
      (diagnostic['largeErrorFrameCount'] as num?)?.toInt() ?? 0;
  final largeErrorCandidateFrameCount =
      (diagnostic['largeErrorCandidateFrameCount'] as num?)?.toInt() ?? 0;
  final largeErrorImprovedFrameCount =
      (diagnostic['largeErrorImprovedFrameCount'] as num?)?.toInt() ?? 0;
  final fullCoverage =
      largeErrorFrameCount > 0 &&
      largeErrorCandidateFrameCount == largeErrorFrameCount &&
      largeErrorImprovedFrameCount == largeErrorFrameCount;
  final candidateBeatsBaseline =
      candidateP90 != null && baselineP90 != null && candidateP90 < baselineP90;
  final decision = candidateFrameCount == 0
      ? 'pass_no_candidate'
      : fullCoverage && candidateBeatsBaseline
      ? 'positive_boundary_candidate'
      : largeErrorFrameCount > 0 &&
            largeErrorCandidateFrameCount < largeErrorFrameCount
      ? 'reject_as_primary_fix'
      : candidateP90 != null &&
            baselineP90 != null &&
            candidateP90 >= baselineP90
      ? 'reject_regression_risk'
      : 'hold_for_more_cases';
  final reason = switch (decision) {
    'pass_no_candidate' =>
      'No high-uncertainty boundary candidate emitted; baseline is unchanged.',
    'positive_boundary_candidate' =>
      'Candidate covers and improves every large-error frame in this case.',
    'reject_as_primary_fix' =>
      'Candidate does not cover all large-error frames; inspect residual and member evolution first.',
    'reject_regression_risk' =>
      'Candidate P90 is not better than the baseline P90.',
    _ =>
      'Evidence is mixed; keep diagnostic-only until more countercases pass.',
  };
  return _PromotionMatrixRow(
    caseId: caseId,
    baselineP90ErrorKm: baselineP90,
    appliedGuardP90ErrorKm: appliedGuardP90,
    candidateP90ErrorKm: candidateP90,
    candidateFrameCount: candidateFrameCount,
    largeErrorFrameCount: largeErrorFrameCount,
    largeErrorCandidateFrameCount: largeErrorCandidateFrameCount,
    largeErrorImprovedFrameCount: largeErrorImprovedFrameCount,
    decision: decision,
    reason: reason,
  );
}

String _promotionDecision(List<_PromotionMatrixRow> rows, String caseId) {
  return rows.singleWhere((row) => row.caseId == caseId).decision;
}

_CandidateCorrectionSummary _candidateCorrectionSummary(
  SourceEstimationBenchmarkReport report,
  LatLng? truth,
) {
  final errors = <double>[];
  var count = 0;
  var appliedCount = 0;
  var largeErrorFrameCount = 0;
  var largeErrorCandidateFrameCount = 0;
  var largeErrorImprovedFrameCount = 0;
  for (final frame in report.frames) {
    final method = frame.methods[SourceEstimationBenchmarkRunner.hybridMethod];
    final estimate = method?.estimate;
    final baselineError = method?.errorKm;
    final hasLargeError = (baselineError ?? 0) >= _largeErrorKm;
    if (hasLargeError) largeErrorFrameCount++;
    final diagnostics = estimate?.diagnostics;
    final corrections = diagnostics?['candidate_corrections'];
    if (corrections is! Map) continue;
    final guard = corrections['one_sided_boundary_centroid_guard'];
    if (guard is! Map) continue;
    count++;
    if (guard['applied'] == true) appliedCount++;
    final latitude = _asDouble(guard['latitude']);
    final longitude = _asDouble(guard['longitude']);
    double? candidateError;
    if (truth != null && latitude != null && longitude != null) {
      candidateError = _distanceKm(LatLng(latitude, longitude), truth);
      errors.add(candidateError);
    }
    if (hasLargeError) {
      largeErrorCandidateFrameCount++;
      if (baselineError != null &&
          candidateError != null &&
          candidateError < baselineError) {
        largeErrorImprovedFrameCount++;
      }
    }
  }
  return _CandidateCorrectionSummary(
    count: count,
    appliedCount: appliedCount,
    medianErrorKm: _percentile(errors, 0.5),
    p90ErrorKm: _percentile(errors, 0.9),
    largeErrorFrameCount: largeErrorFrameCount,
    largeErrorCandidateFrameCount: largeErrorCandidateFrameCount,
    largeErrorImprovedFrameCount: largeErrorImprovedFrameCount,
  );
}

class _CandidateCorrectionSummary {
  final int count;
  final int appliedCount;
  final double? medianErrorKm;
  final double? p90ErrorKm;
  final int largeErrorFrameCount;
  final int largeErrorCandidateFrameCount;
  final int largeErrorImprovedFrameCount;

  const _CandidateCorrectionSummary({
    required this.count,
    required this.appliedCount,
    required this.medianErrorKm,
    required this.p90ErrorKm,
    required this.largeErrorFrameCount,
    required this.largeErrorCandidateFrameCount,
    required this.largeErrorImprovedFrameCount,
  });
}

class _PromotionMatrixRow {
  final String caseId;
  final double? baselineP90ErrorKm;
  final double? appliedGuardP90ErrorKm;
  final double? candidateP90ErrorKm;
  final int candidateFrameCount;
  final int largeErrorFrameCount;
  final int largeErrorCandidateFrameCount;
  final int largeErrorImprovedFrameCount;
  final String decision;
  final String reason;

  const _PromotionMatrixRow({
    required this.caseId,
    required this.baselineP90ErrorKm,
    required this.appliedGuardP90ErrorKm,
    required this.candidateP90ErrorKm,
    required this.candidateFrameCount,
    required this.largeErrorFrameCount,
    required this.largeErrorCandidateFrameCount,
    required this.largeErrorImprovedFrameCount,
    required this.decision,
    required this.reason,
  });

  Map<String, Object?> toJson() => {
    'caseId': caseId,
    'baselineP90ErrorKm': baselineP90ErrorKm,
    'appliedGuardP90ErrorKm': appliedGuardP90ErrorKm,
    'candidateP90ErrorKm': candidateP90ErrorKm,
    'candidateFrameCount': candidateFrameCount,
    'largeErrorThresholdKm': _largeErrorKm,
    'largeErrorFrameCount': largeErrorFrameCount,
    'largeErrorCandidateFrameCount': largeErrorCandidateFrameCount,
    'largeErrorImprovedFrameCount': largeErrorImprovedFrameCount,
    'decision': decision,
    'reason': reason,
  };
}

String _number(Object? value, String unit) =>
    value is num ? '${value.toDouble().toStringAsFixed(1)} $unit' : '-';

String _ratio(int numerator, int denominator) =>
    denominator == 0 ? '-' : '$numerator/$denominator';

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

double? _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index.clamp(0, sorted.length - 1)];
}

double _distanceKm(LatLng a, LatLng b) {
  const earthRadiusKm = 6371.0;
  final lat1 = a.latitude * pi / 180;
  final lat2 = b.latitude * pi / 180;
  final dLat = (b.latitude - a.latitude) * pi / 180;
  final dLng = (b.longitude - a.longitude) * pi / 180;
  final h =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
  return earthRadiusKm * 2 * atan2(sqrt(h), sqrt(1 - h));
}
