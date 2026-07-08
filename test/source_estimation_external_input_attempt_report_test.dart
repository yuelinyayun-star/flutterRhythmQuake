import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_estimation_external_input_attempt_report.dart';

void main() {
  test('external input attempts validator regenerates queue first', () {
    final script = File(
      'tools/validate_source_estimation_external_input_attempts.ps1',
    ).readAsStringSync();

    expect(script, contains(r'[switch]$UseExistingQueue'));
    expect(script, contains(r'if (-not $UseExistingQueue)'));
    expect(
      script,
      contains('tools\\validate_source_estimation_external_input_queue.ps1'),
    );
    expect(
      script,
      contains('build_source_estimation_external_input_attempt_report.dart'),
    );
    expect(
      script,
      contains('source_estimation_external_input_attempt_report_test.dart'),
    );
    expect(
      script.indexOf('validate_source_estimation_external_input_queue.ps1'),
      lessThan(
        script.indexOf(
          'build_source_estimation_external_input_attempt_report.dart',
        ),
      ),
    );
  });

  test('external input attempts stay negative and non-clearing', () {
    final reportFile = File(
      '.dart_tool/source_estimation_external_input_attempts/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing external input attempts report. Run '
        '`powershell -NoProfile -ExecutionPolicy Bypass -File '
        'tools\\validate_source_estimation_external_input_attempts.ps1`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'source_estimation_external_input_attempt_report_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(
      report['warnings'],
      containsAll([
        'attempt_references_nonqueued_input:'
            'local_jma_reference_capture_package::'
            '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
        'attempt_references_nonqueued_input:'
            'local_jma_reference_capture_package::'
            '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
      ]),
    );
    expect(
      report['queuePath'],
      '.dart_tool/source_estimation_external_input_queue/report.json',
    );
    expect(
      report['attemptsPath'],
      'docs/data/source_estimation_external_input_attempts.json',
    );

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['attemptCount'], 18);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['negativeAttemptOnlyCount'], 18);
    expect((summary['inputTypeCounts'] as Map).cast<String, Object?>(), {
      'authenticated_hinet_export_row': 6,
      'final_catalog_or_hinet_revision': 1,
      'local_jma_reference_capture_package': 4,
      'missing_gif_archive_copy': 4,
      'versioned_jma_final_catalog_record': 3,
    });

    final attempts = (report['attempts'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(attempts, hasLength(18));
    for (final attempt in attempts) {
      expect(attempt['evidenceStrength'], 'negative_attempt_only');
      expect(attempt['automaticClearance'], isFalse);
    }
    expect(
      attempts.map((attempt) => attempt['method']),
      containsAll([
        'local_exact_filename_scan',
        'local_exact_filename_rescan',
        'local_exact_filename_extended_scan',
        'remote_hint_recheck',
        'local_timestamp_keyword_capture_scan',
        'authenticated_source_login_page_check',
        'authenticated_source_form_login_check',
        'official_jma_final_catalog_availability_check',
        'official_jma_final_catalog_and_hinet_revision_availability_check',
      ]),
    );
    expect(
      attempts.map((attempt) => attempt['caseId']),
      containsAll([
        '20260620_iwate_offshore_m34_ref',
        '20260622_iwate_east_offshore_m30_hinet',
        '20260622_tomakomai_south_offshore_m35_hinet',
        '20260623_tokachi_southeast_offshore_m34_hinet',
        '20260622_kushiro_offshore_m30_jma',
        '20260624_fukushima_aizu_m32_jma_eq5',
        '20260625_iwate_offshore_m32_jma',
        '20260621_iwate_offshore_m33_eq8',
        '20260625_iwate_offshore_m46_jma_eqsc9',
        '20260626_yamanashi_central_west_m26_jma_equake5',
        '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
        '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
      ]),
    );
  });

  test('automatic clearance or positive evidence fails', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_external_input_attempts_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final attempts =
        jsonDecode(
              File(
                'docs/data/source_estimation_external_input_attempts.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final rows = (attempts['attempts'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    rows.first
      ..['automaticClearance'] = true
      ..['evidenceStrength'] = 'repair_candidate_ready';
    attempts['attempts'] = rows;

    final attemptsFile = File('${tempDir.path}/attempts.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(attempts)}\n',
      );

    final report = buildSourceEstimationExternalInputAttemptJson(
      attemptsPath: attemptsFile.path,
    );
    expect(report['status'], 'fail');
    expect(
      report['errors'],
      contains(
        'attempt_allows_automatic_clearance:'
        '20260626_iwate_m34_missing_jma_b_workspace_downloads_pictures_scan',
      ),
    );
    expect(
      report['errors'],
      contains(
        'attempt_has_nonnegative_evidence:'
        '20260626_iwate_m34_missing_jma_b_workspace_downloads_pictures_scan',
      ),
    );
  });
}
