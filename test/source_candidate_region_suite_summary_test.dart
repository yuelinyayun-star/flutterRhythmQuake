import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('candidate-region suite summary records all guard results', () {
    final summaryFile = File(
      '.dart_tool/source_candidate_region_suite/summary.json',
    );
    if (!summaryFile.existsSync()) {
      markTestSkipped(
        'Missing suite summary. Run '
        '`powershell -NoProfile -ExecutionPolicy Bypass -File '
        'tools\\validate_source_candidate_region_suite.ps1`.',
      );
      return;
    }

    final summary =
        jsonDecode(summaryFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      summary['schemaVersion'],
      'source_candidate_region_suite_validation_v1',
    );
    expect(summary['status'], 'pass');
    expect(
      summary['promotionMatrixReport'],
      '.dart_tool\\source_candidate_promotion_report\\matrix.json',
    );
    expect(
      summary['candidateRegionTimelineReport'],
      '.dart_tool\\source_candidate_region_timeline_report\\report.json',
    );

    final validations = {
      for (final rawValidation in summary['validations'] as List)
        (rawValidation as Map)['name'] as String: rawValidation
            .cast<String, Object?>(),
    };
    expect(
      validations.keys,
      containsAll({
        'residual_promotion_matrix',
        'candidate_region_timeline',
        'validation_script_structure',
      }),
    );
    expect(
      validations.values.every((entry) => entry['status'] == 'pass'),
      isTrue,
    );

    for (final name in [
      'residual_promotion_matrix',
      'candidate_region_timeline',
    ]) {
      final validation = validations[name]!;
      expect(validation['reportValidationStatus'], 'pass');
      expect(validation['reportValidationViolations'], isEmpty);
    }
  });
}
