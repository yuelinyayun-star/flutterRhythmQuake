import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimator.dart';

import '../tools/build_source_hyp_jma2001_experiment_report.dart';
import 'support/source_estimation_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JMA2001 experiment report compares HYP diagnostics safely', () {
    final temp = Directory.systemTemp.createTempSync(
      'source_hyp_jma2001_experiment_report_test_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    _writeBenchmark(
      temp,
      caseId: 'jma_improved_case',
      truthLat: 40.0,
      truthLng: 142.0,
      hybridErrorKm: 22,
      baselineHypLat: 40.60,
      baselineHypLng: 142.50,
      baselineSupported: false,
      jmaHypLat: 40.02,
      jmaHypLng: 142.01,
      jmaSupported: true,
      includeJma2001: true,
      jqHypLat: 40.01,
      jqHypLng: 142.01,
      jqSupported: true,
      includeJqScoring: true,
    );
    _writeBenchmark(
      temp,
      caseId: 'missing_jma_case',
      truthLat: 37.3,
      truthLng: 141.0,
      hybridErrorKm: 12,
      baselineHypLat: 37.31,
      baselineHypLng: 141.01,
      baselineSupported: true,
      jmaHypLat: 37.31,
      jmaHypLng: 141.01,
      jmaSupported: true,
      includeJma2001: false,
      jqHypLat: 37.31,
      jqHypLng: 141.01,
      jqSupported: true,
      includeJqScoring: false,
    );

    final report = buildSourceHypJma2001ExperimentReportJson(
      inputDirectory: temp,
    );

    expect(report['schemaVersion'], 'source_hyp_jma2001_experiment_report_v1');
    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['productionCoordinateSwitchAllowed'], isFalse);
    expect(policy['requiresReplayWithEmitJma2001HypExperiment'], isTrue);
    expect(policy['requiresReplayWithEmitJqScoringHypExperiment'], isTrue);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 2);
    expect(summary['jma2001HypPresentCount'], 1);
    expect(summary['jqScoringHypPresentCount'], 1);
    expect(summary['baselineHypSupportedCount'], 1);
    expect(summary['jma2001HypSupportedCount'], 1);
    expect(summary['jqScoringHypSupportedCount'], 1);
    expect(summary['jma2001ImprovedVsBaselineHypCount'], 1);
    expect(summary['jqScoringImprovedVsBaselineHypCount'], 1);

    final rows = {
      for (final raw in report['rows'] as List)
        (raw as Map)['caseId'] as String: raw.cast<String, Object?>(),
    };
    expect(
      rows['jma_improved_case']!['findings'],
      containsAll([
        'jma2001_improves_hyp_by_10km',
        'jma2001_gains_supported_case',
        'jma2001_low_error_candidate',
        'jq_scoring_improves_hyp_by_10km',
        'jq_scoring_gains_supported_case',
        'jq_scoring_low_error_candidate',
      ]),
    );
    expect(
      rows['missing_jma_case']!['findings'],
      containsAll([
        'missing_jma2001_hyp_experiment',
        'missing_jq_scoring_hyp_experiment',
      ]),
    );

    final findings = (report['findings'] as List).cast<String>();
    expect(findings, contains('some_reports_missing_jma2001_experiment'));
    expect(findings, contains('some_reports_missing_jq_scoring_experiment'));
    expect(findings, contains('jma2001_improves_some_hyp_candidates'));
    expect(findings, contains('jq_scoring_improves_some_hyp_candidates'));
    expect(findings, contains('diagnostic_only_do_not_promote'));

    final markdown = sourceHypJma2001ExperimentMarkdown(report);
    expect(markdown, contains('# HYP JMA2001 experiment report'));
    expect(markdown, contains('jma_improved_case'));
    expect(markdown, contains('missing_jma_case'));
  });

  test(
    'optionally generates local JMA2001 experiment references and report',
    () async {
      const generate = bool.fromEnvironment('SOURCE_HYP_JMA2001_GENERATE');
      if (!generate) return;
      const caseFilter = String.fromEnvironment(
        'SOURCE_HYP_JMA2001_CASE_FILTER',
      );

      const manifests = [
        (
          name: 'iwate_east_offshore_m30_20260622_hinet.json',
          inputMode: SourceEstimationBenchmarkInputMode.dualLayer,
        ),
        (
          name: 'kushiro_offshore_m30_20260622_jma.json',
          inputMode: SourceEstimationBenchmarkInputMode.dualLayer,
        ),
        (
          name: 'tomakomai_south_offshore_m35_20260622_hinet.json',
          inputMode: SourceEstimationBenchmarkInputMode.dualLayer,
        ),
        (
          name: 'wakayama_south_m25_20260622_hinet.json',
          inputMode: SourceEstimationBenchmarkInputMode.dualLayer,
        ),
        (
          name: 'fukushima_hamadori_m35_20260630_hinet_equake10.json',
          inputMode: SourceEstimationBenchmarkInputMode.surfaceImageOnly,
        ),
      ];
      final outputDirectory = Directory(
        '.dart_tool/source_hyp_jma2001_experiment_benchmark',
      )..createSync(recursive: true);

      for (final manifest in manifests) {
        if (caseFilter.isNotEmpty && !manifest.name.contains(caseFilter)) {
          continue;
        }
        final replayCase = SourceEstimationReplayCase.fromManifest(
          File('test/fixtures/source_estimation/${manifest.name}'),
          workspaceRoot: Directory.current,
        );
        if (!replayCase.captureDirectory.existsSync()) {
          continue;
        }

        final report = await SourceEstimationBenchmarkRunner(
          replayCase,
          hybridEstimator: const NiedGifHybridSourceEstimator(
            fallback: WeightedCentroidSourceEstimator(),
            emitOneSidedBoundaryCentroidGuardCandidate: true,
            oneSidedBoundaryCentroidGuardMinUncertaintyP90Km: 180.0,
            oneSidedBoundaryCentroidGuardMinNearestStationDistanceKm: 80.0,
            emitJma2001HypExperiment: true,
            emitJqScoringHypExperiment: true,
            emitKotoho7HypExperiment: true,
          ),
          inputMode: manifest.inputMode,
        ).run();
        report.writeJson(
          File(
            '${outputDirectory.path}${Platform.pathSeparator}'
            '${replayCase.caseId}.reference.json',
          ),
        );
      }

      final report = buildSourceHypJma2001ExperimentReportJson(
        inputDirectory: outputDirectory,
      );
      final json = File(
        '.dart_tool/source_hyp_jma2001_experiment_report/report.json',
      )..parent.createSync(recursive: true);
      json.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
      final markdown = File(
        'docs/baselines/source_hyp_jma2001_experiment_report.generated.md',
      )..parent.createSync(recursive: true);
      markdown.writeAsStringSync(sourceHypJma2001ExperimentMarkdown(report));

      expect(report['status'], 'pass');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

void _writeBenchmark(
  Directory directory, {
  required String caseId,
  required double truthLat,
  required double truthLng,
  required double hybridErrorKm,
  required double baselineHypLat,
  required double baselineHypLng,
  required bool baselineSupported,
  required double jmaHypLat,
  required double jmaHypLng,
  required bool jmaSupported,
  required bool includeJma2001,
  required double jqHypLat,
  required double jqHypLng,
  required bool jqSupported,
  required bool includeJqScoring,
}) {
  final diagnostics = <String, Object?>{
    'nied_gif_hyp_v1': _hyp(
      method: 'nied_gif_hyp_v1',
      lat: baselineHypLat,
      lng: baselineHypLng,
      supported: baselineSupported,
      travelTimeModel: 'fixed_velocity_v1',
      scoringModel: 'weighted_residual_pair_penalty_v1',
    ),
  };
  if (includeJma2001) {
    diagnostics['nied_gif_hyp_jma2001_experiment'] = _hyp(
      method: 'nied_gif_hyp_jma2001_experiment',
      lat: jmaHypLat,
      lng: jmaHypLng,
      supported: jmaSupported,
      travelTimeModel: 'jma2001_polynomial_approximation',
      scoringModel: 'weighted_residual_pair_penalty_v1',
    );
  }
  if (includeJqScoring) {
    diagnostics['nied_gif_hyp_jq_scoring_experiment'] = _hyp(
      method: 'nied_gif_hyp_jq_scoring_experiment',
      lat: jqHypLat,
      lng: jqHypLng,
      supported: jqSupported,
      travelTimeModel: 'jma2001_polynomial_approximation',
      scoringModel: 'jq_reference_candidate_s_flag_origin_variance_v1',
    );
  }

  final file = File(
    '${directory.path}${Platform.pathSeparator}$caseId.reference.json',
  );
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'case': {
        'caseId': caseId,
        'truth': {'latitude': truthLat, 'longitude': truthLng},
      },
      'decodedFrameCount': 1,
      'requestedFrameCount': 1,
      'frames': [
        {
          'methods': {
            'nied_gif_hybrid_v1': {
              'errorKm': hybridErrorKm,
              'estimate': {'latitude': truthLat, 'longitude': truthLng, 'supportingStationCount': 9, 'diagnostics': diagnostics},
            },
          },
        },
      ],
    })}\n',
  );
}

Map<String, Object?> _hyp({
  required String method,
  required double lat,
  required double lng,
  required bool supported,
  required String travelTimeModel,
  required String scoringModel,
}) {
  return {
    'method': method,
    'supported': supported,
    'p_only_supported': false,
    'depth_supported': supported,
    'latitude': lat,
    'longitude': lng,
    'depth_km': 40.0,
    'phase_p_count': 4,
    'phase_s_count': 5,
    'phase_other_count': 0,
    'phase_mean_residual_s': 1.2,
    'pair_mean_residual_s': 0.9,
    'pair_count': 12,
    'unarrived_penalty': supported ? 2.0 : 80.0,
    'unarrived_penalty_count': supported ? 1 : 8,
    'travel_time_model': travelTimeModel,
    'scoring_model': scoringModel,
  };
}
