import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tools/build_source_estimation_external_input_worklist_report.dart';

void main() {
  test(
    'external input worklist validator reuses existing reports when asked',
    () {
      final script = File(
        'tools/validate_source_estimation_external_input_worklist.ps1',
      ).readAsStringSync();

      expect(script, contains(r'[switch]$UseExistingQueue'));
      expect(script, contains(r'[switch]$UseExistingTemplates'));
      expect(script, contains(r'[switch]$UseExistingAttempts'));
      expect(script, contains(r'[switch]$UseExistingRepairProbe'));
      expect(
        script,
        contains(r'[switch]$UseExistingAuthenticatedExportPacket'),
      );
      expect(
        script,
        contains(r'[switch]$UseExistingJmaReferenceCapturePacket'),
      );
      expect(script, contains(r'[switch]$UseExistingJmaFinalCatalogPacket'));
      expect(
        script,
        contains(r'[switch]$UseExistingFinalCatalogOrHinetRevisionPacket'),
      );
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
      expect(
        script,
        contains(
          'tools\\validate_source_estimation_external_input_attempts.ps1',
        ),
      );
      expect(
        script,
        contains('tools\\validate_hinet_capture_repair_probe.ps1'),
      );
      expect(
        script,
        contains('tools\\validate_hinet_authenticated_export_review.ps1'),
      );
      expect(
        script,
        contains('tools\\validate_jma_reference_capture_association.ps1'),
      );
      expect(
        script,
        contains('tools\\build_jma_final_catalog_review_packet.dart'),
      );
      expect(
        script,
        contains(
          'tools\\build_final_catalog_or_hinet_revision_review_packet.dart',
        ),
      );
      expect(
        script,
        contains('build_source_estimation_external_input_worklist_report.dart'),
      );
      expect(
        script,
        contains('source_estimation_external_input_worklist_report_test.dart'),
      );
    },
  );

  test('external input worklist summarizes remaining manual-only inputs', () {
    final reportFile = File(
      '.dart_tool/source_estimation_external_input_worklist/report.json',
    );
    if (!reportFile.existsSync()) {
      markTestSkipped(
        'Missing external input worklist report. Run '
        '`powershell -NoProfile -ExecutionPolicy Bypass -File '
        'tools\\validate_source_estimation_external_input_worklist.ps1`.',
      );
      return;
    }

    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, Object?>;
    expect(
      report['schemaVersion'],
      'source_estimation_external_input_worklist_v1',
    );
    expect(report['status'], 'pass');
    expect(report['errors'], isEmpty);
    expect(report['warnings'], isEmpty);
    expect(
      report['queuePath'],
      '.dart_tool/source_estimation_external_input_queue/report.json',
    );
    expect(
      report['templatesPath'],
      '.dart_tool/source_estimation_external_input_templates/report.json',
    );
    expect(
      report['attemptsPath'],
      '.dart_tool/source_estimation_external_input_attempts/report.json',
    );
    expect(
      report['repairProbePath'],
      '.dart_tool/hinet_capture_repair_probe/report.json',
    );
    expect(
      report['authenticatedExportPacketPath'],
      '.dart_tool/hinet_authenticated_export_review_packet/report.json',
    );
    expect(
      report['jmaReferenceCapturePacketPath'],
      '.dart_tool/jma_reference_capture_review_packet/report.json',
    );
    expect(
      report['jmaFinalCatalogPacketPath'],
      '.dart_tool/jma_final_catalog_review_packet/report.json',
    );
    expect(
      report['finalCatalogOrHinetRevisionPacketPath'],
      '.dart_tool/final_catalog_or_hinet_revision_review_packet/report.json',
    );

    final summary = (report['summary'] as Map).cast<String, Object?>();
    expect(summary['openInputCount'], 6);
    expect(summary['attemptedInputCount'], 6);
    expect(summary['unattemptedInputCount'], 0);
    expect(summary['manualReviewRequiredCount'], 6);
    expect(summary['automaticClearanceCount'], 0);
    expect(summary['operationArtifactCount'], 6);
    expect(summary['highestPriority'], 20);
    expect(summary['nextInputType'], 'local_jma_reference_capture_package');
    expect(summary['nextCaseId'], '20260625_iwate_offshore_m46_jma_eqsc9');
    expect(summary['nextHasAttempts'], isTrue);
    expect((summary['inputTypeCounts'] as Map).cast<String, Object?>(), {
      'final_catalog_or_hinet_revision': 1,
      'local_jma_reference_capture_package': 2,
      'versioned_jma_final_catalog_record': 3,
    });
    expect(
      (summary['attemptedInputTypeCounts'] as Map).cast<String, Object?>(),
      {
        'final_catalog_or_hinet_revision': 1,
        'local_jma_reference_capture_package': 2,
        'versioned_jma_final_catalog_record': 3,
      },
    );

    final rows = (report['rows'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    expect(rows, hasLength(6));
    expect(
      rows.any(
        (row) =>
            row['caseId'] == '20260620_iwate_offshore_m34_ref' &&
            row['inputType'] == 'missing_gif_archive_copy',
      ),
      isFalse,
    );

    expect(
      rows
          .where((row) => row['inputType'] == 'authenticated_hinet_export_row')
          .toList(growable: false),
      isEmpty,
    );

    final captureRow = rows.firstWhere(
      (row) => row['caseId'] == '20260625_iwate_offshore_m46_jma_eqsc9',
    );
    final captureArtifact = (captureRow['operationArtifact'] as Map)
        .cast<String, Object?>();
    expect(captureArtifact['kind'], 'jma_reference_capture_review_packet');
    expect(captureArtifact['packetStatus'], 'pending_capture_association');
    expect(
      captureArtifact['associationTargetPath'],
      'docs/data/jma_reference_event_candidates.json',
    );
    expect(
      captureArtifact['validationCommand'],
      'powershell -NoProfile -ExecutionPolicy Bypass -File '
      'tools\\validate_jma_reference_capture_association.ps1',
    );
    expect(
      captureArtifact['dryRunCommand'],
      'dart run tools\\import_jma_reference_capture_package.dart '
      '--input <reviewed-capture-association.json> --dry-run',
    );
    expect(captureArtifact['manualReviewRequired'], isTrue);
    expect(captureArtifact['automaticClearance'], isFalse);
    expect(captureArtifact['manifestMutation'], isFalse);
    expect(captureArtifact['captureAssociationClearedByPacket'], isFalse);
    expect(captureArtifact['finalCatalogTruth'], isFalse);

    expect(
      rows.any(
        (row) =>
            row['caseId'] ==
            '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
      ),
      isFalse,
    );

    final finalCatalogRow = rows.firstWhere(
      (row) => row['caseId'] == '20260622_kushiro_offshore_m30_jma',
    );
    final finalCatalogArtifact = (finalCatalogRow['operationArtifact'] as Map)
        .cast<String, Object?>();
    expect(finalCatalogArtifact['kind'], 'jma_final_catalog_review_packet');
    expect(
      finalCatalogArtifact['packetStatus'],
      'external_catalog_not_yet_available',
    );
    expect(finalCatalogArtifact['eventYear'], 2026);
    expect(finalCatalogArtifact['latestAvailableFinalCatalogYear'], 2023);
    expect(
      finalCatalogArtifact['dryRunLinkCommand'],
      contains('link_jma_catalog.dart'),
    );
    expect(finalCatalogArtifact['writeLinkAllowed'], isFalse);
    expect(finalCatalogArtifact['manualReviewRequired'], isTrue);
    expect(finalCatalogArtifact['automaticClearance'], isFalse);
    expect(finalCatalogArtifact['fixtureMutation'], isFalse);
    expect(finalCatalogArtifact['catalogTruthWrite'], isFalse);

    final revisionRow = rows.firstWhere(
      (row) => row['caseId'] == '20260621_iwate_offshore_m33_eq8',
    );
    final revisionArtifact = (revisionRow['operationArtifact'] as Map)
        .cast<String, Object?>();
    expect(
      revisionArtifact['kind'],
      'final_catalog_or_hinet_revision_review_packet',
    );
    expect(revisionArtifact['packetStatus'], 'reference_only');
    expect(revisionArtifact['negativeAttemptOnlyCount'], 1);
    expect(revisionArtifact['manualReviewRequired'], isTrue);
    expect(revisionArtifact['automaticClearance'], isFalse);
    expect(revisionArtifact['fixtureMutation'], isFalse);
    expect(revisionArtifact['splitManifestMutation'], isFalse);
    expect(revisionArtifact['truthPromotion'], isFalse);
    expect(revisionArtifact['resolutionAllowedByPacket'], isFalse);
  });

  test('worklist rejects automatic clearance semantics', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'source_external_input_worklist_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final templates =
        jsonDecode(
              File(
                '.dart_tool/source_estimation_external_input_templates/report.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final templateRows = (templates['templates'] as List)
        .map((entry) => (entry as Map).cast<String, Object?>())
        .toList(growable: false);
    final firstTemplate = templateRows.first;
    firstTemplate['automaticClearance'] = true;
    templates['templates'] = templateRows;

    final templateFile = File('${tempDir.path}/templates.json')
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(templates)}\n',
      );

    final report = buildSourceEstimationExternalInputWorklistJson(
      templatesPath: templateFile.path,
    );
    expect(report['status'], 'fail');
    expect(
      report['errors'],
      contains(
        'external_input_worklist_template_allows_clearance:'
        '${firstTemplate['inputType']}::${firstTemplate['caseId']}',
      ),
    );
  });
}
