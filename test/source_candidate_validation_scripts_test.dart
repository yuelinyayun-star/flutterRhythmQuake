import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('candidate-region suite runs both matrix guards', () {
    final suite = File(
      'tools/validate_source_candidate_region_suite.ps1',
    ).readAsStringSync();

    expect(suite, contains("\$ErrorActionPreference = 'Stop'"));
    expect(
      suite,
      contains('tools\\validate_source_candidate_promotion_matrix.ps1'),
    );
    expect(
      suite,
      contains('tools\\validate_source_candidate_region_timeline.ps1'),
    );
    expect(
      suite,
      contains('test\\source_candidate_validation_scripts_test.dart'),
    );
    expect(
      suite,
      contains('test\\source_candidate_region_suite_summary_test.dart'),
    );
    expect(
      suite.indexOf('validate_source_candidate_promotion_matrix.ps1'),
      lessThan(suite.indexOf('validate_source_candidate_region_timeline.ps1')),
    );
    expect(
      suite.indexOf('validate_source_candidate_region_timeline.ps1'),
      lessThan(suite.indexOf('source_candidate_validation_scripts_test.dart')),
    );
    expect(suite, contains('source_candidate_region_suite_validation_v1'));
    expect(suite, contains(r'$summaryDirectory'));
    expect(suite, contains('ConvertFrom-Json'));
    expect(suite, contains('reportValidationStatus'));
    expect(suite, contains('reportValidationViolations'));
    expect(suite, contains('promotion_matrix_report_validation_failed'));
    expect(
      suite,
      contains('candidate_region_timeline_report_validation_failed'),
    );
    expect(suite, contains('residual_promotion_matrix'));
    expect(suite, contains('candidate_region_timeline'));
    expect(suite, contains('validation_script_structure'));
    expect(
      suite.indexOf(r'Set-Content -Path "$summaryDirectory\summary.json"'),
      lessThan(
        suite.indexOf('source_candidate_region_suite_summary_test.dart'),
      ),
    );
  });

  test('promotion matrix guard regenerates reports before testing', () {
    final script = File(
      'tools/validate_source_candidate_promotion_matrix.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(script, contains('build_source_estimation_early_frame_report.dart'));
    expect(script, contains('build_source_candidate_promotion_report.dart'));
    expect(
      script,
      contains('test\\source_candidate_promotion_matrix_report_test.dart'),
    );
    expect(
      script.indexOf('build_source_estimation_early_frame_report.dart'),
      lessThan(script.indexOf('build_source_candidate_promotion_report.dart')),
    );
    expect(
      script.indexOf('build_source_candidate_promotion_report.dart'),
      lessThan(
        script.indexOf('source_candidate_promotion_matrix_report_test.dart'),
      ),
    );
  });

  test('timeline guard regenerates report before testing', () {
    final script = File(
      'tools/validate_source_candidate_region_timeline.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(
      script,
      contains('build_source_candidate_region_timeline_report.dart'),
    );
    expect(
      script,
      contains('test\\source_candidate_region_timeline_report_test.dart'),
    );
    expect(
      script.indexOf('build_source_candidate_region_timeline_report.dart'),
      lessThan(
        script.indexOf('source_candidate_region_timeline_report_test.dart'),
      ),
    );
  });
}
