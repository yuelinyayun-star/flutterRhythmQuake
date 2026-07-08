import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_estimation_external_input_template_report.dart';

void main() {
  test('external input template validator regenerates queue first', () {
    final script = File(
      'tools/validate_source_estimation_external_input_templates.ps1',
    ).readAsStringSync();

    expect(script, contains('[switch]\$UseExistingQueue'));
    expect(script, contains("\$ErrorActionPreference = 'Stop'"));
    expect(
      script,
      contains('tools\\validate_source_estimation_external_input_queue.ps1'),
    );
    expect(script, contains('if (-not \$UseExistingQueue)'));
    expect(
      script,
      contains('build_source_estimation_external_input_template_report.dart'),
    );
    expect(
      script.indexOf('validate_source_estimation_external_input_queue.ps1'),
      lessThan(
        script.indexOf(
          'build_source_estimation_external_input_template_report.dart',
        ),
      ),
    );

    final suiteScript = File(
      'tools/validate_source_estimation_suite.ps1',
    ).readAsStringSync();
    expect(
      suiteScript,
      contains(
        'tools\\validate_source_estimation_external_input_templates.ps1 `',
      ),
    );
    expect(suiteScript, contains('-UseExistingQueue'));
  });

  test('external input templates mirror the queue without clearing blockers', () {
    final reportFile = File(
      '.dart_tool/source_estimation_external_input_templates/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing external input template report. Run '
        '`dart run tools/build_source_estimation_external_input_template_report.dart`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'source_estimation_external_input_templates_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['templateCount'], 6);
    expect(summary['manualReviewRequiredCount'], 6);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['ledgerMutationCount'], 0);
    expect((summary['inputTypeCounts'] as Map).cast<String, Object?>(), {
      'final_catalog_or_hinet_revision': 1,
      'local_jma_reference_capture_package': 2,
      'versioned_jma_final_catalog_record': 3,
    });

    final templates = (report['templates'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);

    final yamanashi = templates.singleWhere(
      (template) =>
          template['caseId'] ==
          '20260626_yamanashi_central_west_m26_jma_equake5',
    );
    expect(yamanashi['inputType'], 'local_jma_reference_capture_package');
    expect(
      yamanashi['targetPath'],
      'docs/data/jma_reference_event_candidates.json',
    );
    expect(yamanashi['automaticClearance'], isFalse);
    expect(yamanashi['manualReviewRequired'], isTrue);
    final yamanashiTemplate = (yamanashi['template'] as Map)
        .cast<String, Object?>();
    expect(
      yamanashiTemplate.keys,
      containsAll([
        'eventId',
        'status',
        'reviewedAtUtc',
        'reviewer',
        'captureDirectory',
        'manifestPath',
        'packageSource',
        'associationReason',
        'requiredLocalFiles',
        'dryRunCommand',
        'afterFilling',
      ]),
    );
    expect(
      yamanashiTemplate['dryRunCommand'],
      contains('tools/import_jma_reference_capture_package.dart'),
    );
    expect(yamanashiTemplate['dryRunCommand'], contains('--dry-run'));
    final yamanashiNotes = (yamanashi['notes'] as List)
        .map((note) => note.toString())
        .join('\n');
    expect(yamanashiNotes, contains('final catalog truth'));
    expect(yamanashiNotes, contains('split membership'));

    expect(
      templates.any(
        (template) =>
            template['caseId'] ==
            '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
      ),
      isFalse,
    );

    expect(
      templates
          .where(
            (template) =>
                template['inputType'] == 'authenticated_hinet_export_row',
          )
          .toList(growable: false),
      isEmpty,
    );

    expect(
      templates.any(
        (template) => template['inputType'] == 'missing_gif_archive_copy',
      ),
      isFalse,
    );
  });

  test('external input templates can be built from a minimal queue', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_estimation_external_input_templates_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final queue = File('${tempDir.path}/queue.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 'source_estimation_external_input_queue_v1',
          'status': 'pass',
          'items': [
            {
              'priority': 15,
              'inputType': 'authenticated_hinet_export_row',
              'caseId': 'sample_case',
              'requiredInput': 'Fill one row.',
              'sourceReport': 'hinet_authenticated_export_review',
              'details': 'decisionStatus=pending_manual_review',
            },
          ],
        }),
      );

    final report = buildSourceEstimationExternalInputTemplateJson(
      queuePath: queue.path,
      fixtureDirectory: tempDir.path,
    );

    expect(report['status'], 'pass');
    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['templateCount'], 1);
    expect(summary['automaticClearanceCount'], 0);
    final templates = report['templates'] as List;
    expect((templates.single as Map)['caseId'], 'sample_case');
  });
}
