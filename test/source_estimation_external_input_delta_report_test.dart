import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_estimation_external_input_delta_report.dart';

void main() {
  test('external input delta validator regenerates dependencies first', () {
    final script = File(
      'tools/validate_source_estimation_external_input_delta.ps1',
    ).readAsStringSync();

    expect(
      script,
      contains('tools\\validate_source_estimation_external_input_queue.ps1'),
    );
    expect(
      script,
      contains(
        'tools\\validate_source_estimation_external_input_templates.ps1',
      ),
    );
    expect(script, contains('-UseExistingQueue'));
    expect(
      script,
      contains('build_source_estimation_external_input_delta_report.dart'),
    );
    expect(
      script,
      contains('source_estimation_external_input_delta_report_test.dart'),
    );
    expect(
      script.indexOf('validate_source_estimation_external_input_queue.ps1'),
      lessThan(
        script.indexOf(
          'validate_source_estimation_external_input_templates.ps1',
        ),
      ),
    );
    expect(
      script.indexOf('validate_source_estimation_external_input_templates.ps1'),
      lessThan(
        script.indexOf(
          'build_source_estimation_external_input_delta_report.dart',
        ),
      ),
    );
  });

  test('external input delta proves queue-template one-for-one coverage', () {
    final reportFile = File(
      '.dart_tool/source_estimation_external_input_delta/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing external input delta report. Run '
        '`dart run tools/build_source_estimation_external_input_delta_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'source_estimation_external_input_delta_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(report['warnings'], isEmpty);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['deltaRowCount'], 6);
    expect(summary['matchedTemplateCount'], 6);
    expect(summary['missingTemplateCount'], 0);
    expect(summary['staleTemplateCount'], 0);
    expect(summary['priorityMismatchCount'], 0);
    expect(summary['nonManualReviewTemplateCount'], 0);
    expect(summary['automaticClearanceTemplateCount'], 0);
    expect(summary['coverageComplete'], isTrue);
    expect(summary['safeTemplateSemantics'], isTrue);

    final rows = (report['rows'] as List)
        .map((raw) => (raw as Map).cast<String, Object?>())
        .toList(growable: false);
    final yamanashi = rows.singleWhere(
      (row) =>
          row['caseId'] == '20260626_yamanashi_central_west_m26_jma_equake5',
    );
    expect(yamanashi['status'], 'matched');
    expect(yamanashi['inputType'], 'local_jma_reference_capture_package');
    expect(yamanashi['manualReviewRequired'], isTrue);
    expect(yamanashi['automaticClearance'], isFalse);
  });

  test('external input delta fails unsafe or stale templates', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_estimation_external_input_delta_',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final queueFile = File('${tempDir.path}/queue.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'source_estimation_external_input_queue_v1',
          'status': 'pass',
          'summary': {'inputItemCount': 2},
          'errors': [],
          'warnings': [],
          'items': [
            {
              'priority': 10,
              'inputType': 'missing_gif_archive_copy',
              'caseId': 'sample_missing_template',
              'requiredInput': 'Place a GIF.',
              'sourceReport': 'test',
              'details': '',
            },
            {
              'priority': 20,
              'inputType': 'local_jma_reference_capture_package',
              'caseId': 'sample_unsafe_template',
              'requiredInput': 'Associate capture.',
              'sourceReport': 'test',
              'details': '',
            },
          ],
        }),
      );

    final templatesFile = File('${tempDir.path}/templates.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'source_estimation_external_input_templates_v1',
          'status': 'pass',
          'summary': {
            'templateCount': 2,
            'automaticClearanceCount': 1,
            'ledgerMutationCount': 1,
          },
          'errors': [],
          'warnings': [],
          'templates': [
            {
              'priority': 25,
              'inputType': 'local_jma_reference_capture_package',
              'caseId': 'sample_unsafe_template',
              'targetPath': 'docs/data/jma_reference_event_candidates.json',
              'action': 'unsafe',
              'validationCommand': 'none',
              'manualReviewRequired': false,
              'automaticClearance': true,
            },
            {
              'priority': 30,
              'inputType': 'versioned_jma_final_catalog_record',
              'caseId': 'sample_stale_template',
              'targetPath': 'fixture.json',
              'action': 'stale',
              'validationCommand': 'none',
              'manualReviewRequired': true,
              'automaticClearance': false,
            },
          ],
        }),
      );

    final report = buildSourceEstimationExternalInputDeltaJson(
      queuePath: queueFile.path,
      templatesPath: templatesFile.path,
    );

    expect(report['status'], 'fail');
    final errors = (report['errors'] as List).cast<String>();
    expect(
      errors,
      contains(
        'external_input_delta_missing_template:'
        'missing_gif_archive_copy::sample_missing_template',
      ),
    );
    expect(
      errors,
      contains(
        'external_input_delta_priority_mismatch:'
        'local_jma_reference_capture_package::sample_unsafe_template',
      ),
    );
    expect(
      errors,
      contains(
        'external_input_delta_template_not_manual_review:'
        'local_jma_reference_capture_package::sample_unsafe_template',
      ),
    );
    expect(
      errors,
      contains(
        'external_input_delta_template_allows_clearance:'
        'local_jma_reference_capture_package::sample_unsafe_template',
      ),
    );
    expect(
      errors,
      contains(
        'external_input_delta_stale_template:'
        'versioned_jma_final_catalog_record::sample_stale_template',
      ),
    );
    expect(errors, contains('external_input_delta_summary_allows_clearance'));
    expect(errors, contains('external_input_delta_summary_mutates_ledger'));

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['missingTemplateCount'], 1);
    expect(summary['staleTemplateCount'], 1);
    expect(summary['coverageComplete'], isFalse);
    expect(summary['safeTemplateSemantics'], isFalse);
  });
}
