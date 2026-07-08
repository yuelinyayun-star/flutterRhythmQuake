import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hyp_vs_hybrid_report.dart';

void main() {
  test('HYP-vs-hybrid report compares diagnostics without promotion', () {
    final temp = Directory.systemTemp.createTempSync(
      'source_hyp_vs_hybrid_report_test_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    _writeBenchmark(
      temp,
      caseId: 'supported_case',
      truthLat: 40.0,
      truthLng: 142.0,
      hybridLat: 40.4,
      hybridLng: 142.4,
      hybridErrorKm: 55,
      hypLat: 40.02,
      hypLng: 142.01,
      hypDepthKm: 40,
      hypSupported: true,
      hypPOnlySupported: false,
      hypDepthSupported: true,
      p: 4,
      s: 5,
      o: 0,
      unarrivedPenalty: 2.0,
    );
    _writeBenchmark(
      temp,
      caseId: 'p_only_case',
      truthLat: 37.3,
      truthLng: 141.0,
      hybridLat: 37.2,
      hybridLng: 141.0,
      hybridErrorKm: 12,
      hypLat: 36.6,
      hypLng: 140.0,
      hypDepthKm: 140,
      hypSupported: false,
      hypPOnlySupported: true,
      hypDepthSupported: false,
      p: 8,
      s: 0,
      o: 0,
      unarrivedPenalty: 80.0,
    );

    final report = buildSourceHypVsHybridReportJson(inputDirectory: temp);

    expect(report['schemaVersion'], 'source_hyp_vs_hybrid_report_v1');
    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['productionCoordinateSwitchAllowed'], isFalse);
    expect(policy['referenceAlgorithmInput'], 'nied_kmoni_gif_reverse_decoded');

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 2);
    expect(summary['hypSupportedCount'], 1);
    expect(summary['hypDepthSupportedCount'], 1);
    expect(summary['hypPOnlySupportedCount'], 1);
    expect(summary['hypImprovedFinalCount'], 1);

    final rows = {
      for (final raw in report['rows'] as List)
        (raw as Map)['caseId'] as String: raw.cast<String, Object?>(),
    };
    expect(
      rows['supported_case']!['findings'],
      containsAll(['hyp_improves_final_error', 'hyp_supported']),
    );
    expect(
      rows['p_only_case']!['findings'],
      containsAll([
        'hyp_regresses_final_error',
        'p_only_timing_fit_only',
        'no_s_support',
        'large_unarrived_penalty',
      ]),
    );

    final findings = (report['findings'] as List).cast<String>();
    expect(findings, contains('p_only_cases_must_not_promote_location'));
    expect(findings, contains('unarrived_penalty_needs_calibration'));
    expect(
      findings,
      contains('some_reference_cases_have_two_phase_depth_support'),
    );

    final markdown = sourceHypVsHybridReportMarkdown(report);
    expect(markdown, contains('# Source HYP vs hybrid diagnostic report'));
    expect(markdown, contains('supported_case'));
    expect(markdown, contains('p_only_case'));
  });
}

void _writeBenchmark(
  Directory directory, {
  required String caseId,
  required double truthLat,
  required double truthLng,
  required double hybridLat,
  required double hybridLng,
  required double hybridErrorKm,
  required double hypLat,
  required double hypLng,
  required double hypDepthKm,
  required bool hypSupported,
  required bool hypPOnlySupported,
  required bool hypDepthSupported,
  required int p,
  required int s,
  required int o,
  required double unarrivedPenalty,
}) {
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
              'estimate': {
                'latitude': hybridLat,
                'longitude': hybridLng,
                'supportingStationCount': p + s + o,
                'diagnostics': {
                  'nied_gif_hyp_v1': {'method': 'nied_gif_hyp_v1', 'supported': hypSupported, 'p_only_supported': hypPOnlySupported, 'depth_supported': hypDepthSupported, 'latitude': hypLat, 'longitude': hypLng, 'depth_km': hypDepthKm, 'phase_p_count': p, 'phase_s_count': s, 'phase_other_count': o, 'phase_mean_residual_s': 1.2, 'pair_mean_residual_s': 0.9, 'pair_count': 12, 'unarrived_penalty': unarrivedPenalty, 'unarrived_penalty_count': 3},
                },
              },
            },
          },
        },
      ],
    })}\n',
  );
}
