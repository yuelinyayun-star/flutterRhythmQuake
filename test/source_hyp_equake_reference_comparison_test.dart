import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_hyp_equake_reference_comparison.dart';

void main() {
  test('EQuake comparison keeps references diagnostic-only', () {
    final temp = Directory.systemTemp.createTempSync(
      'source_hyp_equake_reference_comparison_test_',
    );
    addTearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    final reference = File('${temp.path}/equake_refs.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'equake_phase_origin_reference_cases_v1',
          'policy': {
            'referenceOnly': true,
            'notCatalogTruth': true,
            'gifDerived': true,
            'doNotUseForFrozenMetricTruth': true,
          },
          'cases': [
            {
              'caseId': 'eq_ref_case',
              'region': '苫小牧沖',
              'equakeFinalReport': {
                'latitude': 42.14,
                'longitude': 141.22,
                'depthKm': 118,
                'phaseCounts': {'p': 10, 's': 33, 'other': 6},
              },
              'catalogReference': {'latitude': 42.063, 'longitude': 141.347},
              'localReplay': {
                'hypBenchmarkCaseIds': ['hyp_case'],
                'currentCaptureCaseIds': ['current_case'],
              },
              'phaseProgression': [
                {'reportNo': 1, 'p': 7, 's': 0, 'other': 1},
                {'reportNo': 2, 'p': 9, 's': 0, 'other': 2},
                {'reportNo': 3, 'p': 9, 's': 0, 'other': 3},
                {'reportNo': 10, 'p': 10, 's': 33, 'other': 6},
              ],
            },
          ],
        }),
      );
    final hyp = File('${temp.path}/hyp_report.json')
      ..writeAsStringSync(
        jsonEncode({
          'rows': [
            {
              'caseId': 'hyp_case',
              'jqScoringHypLatitude': 42.1604,
              'jqScoringHypLongitude': 141.1736,
              'jqScoringHypDepthKm': 140,
              'jqScoringHypSupported': false,
              'jqScoringHypPhasePCount': 0,
              'jqScoringHypPhaseSCount': 13,
              'jqScoringHypPhaseOtherCount': 1,
              'jqScoringHypPhaseBalancePenalty': 145.2,
            },
          ],
        }),
      );
    final current = File('${temp.path}/current_report.json')
      ..writeAsStringSync(
        jsonEncode({
          'cases': [
            {
              'id': 'current_case',
              'finalEstimate': {
                'latitude': 42.10,
                'longitude': 141.30,
                'method': 'nied_gif_hybrid_v1',
                'supportingStationCount': 12,
                'diagnostics': {
                  'nied_gif_hyp_v1': {
                    'latitude': 42.0,
                    'longitude': 141.1,
                    'phase_p_count': 9,
                    'phase_s_count': 2,
                    'phase_other_count': 1,
                  },
                },
              },
            },
          ],
        }),
      );

    final report = buildSourceHypEquakeReferenceComparisonJson(
      referenceCases: reference,
      hypReport: hyp,
      currentCaptureReport: current,
    );

    expect(
      report['schemaVersion'],
      'source_hyp_equake_reference_comparison_v1',
    );
    final policy = (report['policy'] as Map).cast<String, Object?>();
    expect(policy['diagnosticOnly'], isTrue);
    expect(policy['referenceOnly'], isTrue);
    expect(policy['notCatalogTruth'], isTrue);
    expect(policy['productionCoordinateSwitchAllowed'], isFalse);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['caseCount'], 1);
    expect(summary['hypBenchmarkMatchedCount'], 1);
    expect(summary['currentCaptureMatchedCount'], 1);
    expect(summary['jqScoringZeroPAgainstEquakePCount'], 1);

    final row = ((report['rows'] as List).single as Map)
        .cast<String, Object?>();
    expect(row['hypBenchmarkCaseId'], 'hyp_case');
    expect(row['currentCaptureCaseId'], 'current_case');
    expect(row['jqScoringPhaseDeltaP'], -10);
    expect(
      row['findings'],
      containsAll([
        'matched_hyp_benchmark',
        'matched_current_capture',
        'jq_scoring_zero_p_against_equake_p_support',
        'equake_progression_p_only_to_mixed',
      ]),
    );

    final markdown = sourceHypEquakeReferenceComparisonMarkdown(report);
    expect(markdown, contains('# HYP vs EQuake reference comparison'));
    expect(markdown, contains('eq_ref_case'));
  });

  test('default EQuake reference packet data is parseable', () {
    final reference =
        jsonDecode(
              File(
                'docs/data/equake_phase_origin_reference_cases.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(
      reference['schemaVersion'],
      'equake_phase_origin_reference_cases_v1',
    );
    final policy = (reference['policy'] as Map).cast<String, Object?>();
    expect(policy['referenceOnly'], isTrue);
    expect(policy['notCatalogTruth'], isTrue);
    final cases = (reference['cases'] as List).cast<Map>();
    expect(cases, hasLength(3));
    expect(
      cases.map((caseData) => caseData['caseId']),
      contains('equake_20260622_tomakomai_south_offshore_m29_report10'),
    );
  });
}
