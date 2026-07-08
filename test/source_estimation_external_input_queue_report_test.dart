import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_estimation_external_input_queue_report.dart';

void main() {
  test('external input queue script regenerates dependency reports first', () {
    final script = File(
      'tools/validate_source_estimation_external_input_queue.ps1',
    ).readAsStringSync();

    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(
      script,
      contains('tools\\validate_source_estimation_split_blocker_queue.ps1'),
    );
    expect(
      script,
      contains('tools\\validate_jma_reference_capture_association.ps1'),
    );
    expect(script, contains('tools\\validate_hinet_capture_repair_probe.ps1'));
    expect(
      script,
      contains('tools\\validate_hinet_authenticated_export_review.ps1'),
    );
    expect(script, contains('UseExistingDependencies'));
    expect(script, contains('UseExistingBlockerQueue'));
    expect(script, contains('UseExistingJmaCapture'));
    expect(script, contains('UseExistingHinetRepair'));
    expect(script, contains('UseExistingHinetExport'));
    expect(
      script,
      contains('build_source_estimation_external_input_queue_report.dart'),
    );
    expect(
      script.indexOf('validate_source_estimation_split_blocker_queue.ps1'),
      lessThan(
        script.indexOf(
          'build_source_estimation_external_input_queue_report.dart',
        ),
      ),
    );
  });

  test('external input queue lists only required external inputs', () {
    final reportFile = File(
      '.dart_tool/source_estimation_external_input_queue/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing external input queue report. Run '
        '`dart run tools/build_source_estimation_external_input_queue_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'source_estimation_external_input_queue_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['inputItemCount'], 6);
    expect(summary['automaticClearanceCount'], 0);
    expect((summary['inputTypeCounts'] as Map).cast<String, Object?>(), {
      'final_catalog_or_hinet_revision': 1,
      'local_jma_reference_capture_package': 2,
      'versioned_jma_final_catalog_record': 3,
    });

    final items = (report['items'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(
      items.any(
        (item) =>
            item['caseId'] == '20260620_iwate_offshore_m34_ref' &&
            item['inputType'] == 'missing_gif_archive_copy',
      ),
      isFalse,
    );
    expect(
      items
          .where(
            (item) => item['inputType'] == 'authenticated_hinet_export_row',
          )
          .toList(growable: false),
      isEmpty,
    );
  });

  test('external input queue can be built from empty passing reports', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_estimation_external_input_queue_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final blockers = File('${tempDir.path}/blockers.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'source_estimation_split_blocker_queue_v1',
          'status': 'pass',
          'blockers': [],
        }),
      );
    final jmaCapture = File('${tempDir.path}/jma_capture.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'jma_reference_capture_association_v1',
          'status': 'pass',
          'cases': [],
        }),
      );
    final repair = File('${tempDir.path}/repair.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'hinet_capture_repair_probe_v1',
          'status': 'pass',
          'cases': [],
        }),
      );
    final export = File('${tempDir.path}/export.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'hinet_authenticated_export_review_v1',
          'status': 'pass',
          'cases': [],
        }),
      );

    final report = buildSourceEstimationExternalInputQueueJson(
      blockerQueuePath: blockers.path,
      jmaCaptureAssociationPath: jmaCapture.path,
      hinetRepairProbePath: repair.path,
      hinetAuthenticatedExportReviewPath: export.path,
    );

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['inputItemCount'], 0);
    expect(summary['automaticClearanceCount'], 0);
    expect(report['warnings'], contains('external_input_queue_empty'));
  });
}
