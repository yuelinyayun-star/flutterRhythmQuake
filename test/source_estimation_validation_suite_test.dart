import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'source-estimation validation suite runs split and candidate guards',
    () {
      final script = File(
        'tools/validate_source_estimation_suite.ps1',
      ).readAsStringSync();

      expect(script, contains("\$ErrorActionPreference = 'Stop'"));
      expect(
        script,
        contains('tools\\validate_source_estimation_split_audit.ps1'),
      );
      expect(
        script,
        contains(
          'tools\\validate_source_estimation_split_assignment_readiness.ps1',
        ),
      );
      expect(
        script,
        contains('tools\\validate_source_estimation_split_blocker_queue.ps1'),
      );
      expect(
        script,
        contains('finalCatalogOrHinetRevisionReviewPacketReportPath'),
      );
      expect(script, contains('-UseExistingReadiness'));
      expect(script, contains('tools\\validate_jma_catalog_availability.ps1'));
      expect(script, contains('jmaFinalCatalogReviewPacketReportPath'));
      expect(
        script,
        contains('tools\\validate_jma_reference_event_candidates.ps1'),
      );
      expect(
        script,
        contains('tools\\validate_jma_reference_capture_association.ps1'),
      );
      expect(script, contains('jmaReferenceCaptureReviewPacketReportPath'));
      expect(
        script,
        contains('tools\\validate_hinet_truth_quality_review.ps1'),
      );
      expect(
        script,
        contains('tools\\validate_hinet_capture_provenance_review.ps1'),
      );
      expect(
        script,
        contains('build_hinet_capture_exclusion_template_report.dart'),
      );
      expect(
        script,
        contains('build_hinet_capture_exclusion_review_packet.dart'),
      );
      expect(script, contains('-UseExistingTruthReview'));
      expect(
        script,
        contains('tools\\validate_hinet_capture_repair_probe.ps1'),
      );
      expect(script, contains('-UseExistingProvenanceReview'));
      expect(
        script,
        contains('tools\\validate_hinet_truth_quality_review_queue.ps1'),
      );
      expect(
        script,
        contains('tools\\validate_hinet_external_evidence_targets.ps1'),
      );
      expect(
        script,
        contains('tools\\validate_hinet_authenticated_export_review.ps1'),
      );
      expect(
        script,
        contains('hinetAuthenticatedExportReviewPacketReportPath'),
      );
      expect(script, contains('-UseExistingExternalEvidenceTargets'));
      expect(
        script,
        contains('tools\\validate_source_estimation_external_input_queue.ps1'),
      );
      expect(script, contains('-UseExistingDependencies'));
      expect(
        script,
        contains(
          'tools\\validate_source_estimation_external_input_templates.ps1',
        ),
      );
      expect(
        script,
        contains('tools\\validate_source_estimation_external_input_delta.ps1'),
      );
      expect(
        script,
        contains(
          'tools\\validate_source_estimation_external_input_attempts.ps1',
        ),
      );
      expect(
        script,
        contains(
          'tools\\validate_source_estimation_external_input_worklist.ps1',
        ),
      );
      expect(
        script,
        contains('tools\\validate_source_trigger_threshold_review.ps1'),
      );
      expect(script, contains('tools\\validate_plum_replay_capture_gap.ps1'));
      expect(
        script,
        contains(
          'tools\\validate_source_estimation_split_assignment_patch.ps1',
        ),
      );
      expect(
        script,
        contains('tools\\validate_source_candidate_region_suite.ps1'),
      );
      expect(
        script,
        contains('test\\source_estimation_validation_suite_test.dart'),
      );
      expect(
        script.indexOf('validate_source_estimation_split_audit.ps1'),
        lessThan(
          script.indexOf('validate_source_trigger_threshold_review.ps1'),
        ),
      );
      expect(
        script.indexOf('validate_source_trigger_threshold_review.ps1'),
        lessThan(script.indexOf('validate_plum_replay_capture_gap.ps1')),
      );
      expect(
        script.indexOf('validate_plum_replay_capture_gap.ps1'),
        lessThan(
          script.indexOf(
            'validate_source_estimation_split_assignment_readiness.ps1',
          ),
        ),
      );
      expect(
        script.indexOf(
          'validate_source_estimation_split_assignment_readiness.ps1',
        ),
        lessThan(
          script.indexOf('validate_source_estimation_split_blocker_queue.ps1'),
        ),
      );
      expect(
        script.indexOf('validate_source_estimation_split_blocker_queue.ps1'),
        lessThan(script.indexOf('validate_jma_catalog_availability.ps1')),
      );
      expect(
        script.indexOf('validate_jma_catalog_availability.ps1'),
        lessThan(script.indexOf('validate_jma_reference_event_candidates.ps1')),
      );
      expect(
        script.indexOf('validate_jma_reference_event_candidates.ps1'),
        lessThan(
          script.indexOf('validate_jma_reference_capture_association.ps1'),
        ),
      );
      expect(
        script.indexOf('validate_jma_reference_capture_association.ps1'),
        lessThan(script.indexOf('validate_hinet_truth_quality_review.ps1')),
      );
      expect(
        script.indexOf('validate_hinet_truth_quality_review.ps1'),
        lessThan(
          script.indexOf('validate_hinet_capture_provenance_review.ps1'),
        ),
      );
      expect(
        script.indexOf('validate_hinet_capture_provenance_review.ps1'),
        lessThan(script.indexOf('validate_hinet_capture_repair_probe.ps1')),
      );
      expect(
        script.indexOf('validate_hinet_capture_repair_probe.ps1'),
        lessThan(
          script.indexOf('validate_hinet_truth_quality_review_queue.ps1'),
        ),
      );
      expect(
        script.indexOf('validate_hinet_truth_quality_review_queue.ps1'),
        lessThan(
          script.indexOf('validate_hinet_external_evidence_targets.ps1'),
        ),
      );
      expect(
        script.indexOf('validate_hinet_external_evidence_targets.ps1'),
        lessThan(
          script.indexOf('validate_hinet_authenticated_export_review.ps1'),
        ),
      );
      expect(
        script.indexOf('validate_hinet_authenticated_export_review.ps1'),
        lessThan(
          script.indexOf('validate_source_estimation_external_input_queue.ps1'),
        ),
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
        script.indexOf(
          'validate_source_estimation_external_input_templates.ps1',
        ),
        lessThan(
          script.indexOf('validate_source_estimation_external_input_delta.ps1'),
        ),
      );
      expect(
        script.indexOf('validate_source_estimation_external_input_delta.ps1'),
        lessThan(
          script.indexOf(
            'validate_source_estimation_external_input_attempts.ps1',
          ),
        ),
      );
      expect(
        script.indexOf(
          'validate_source_estimation_external_input_attempts.ps1',
        ),
        lessThan(
          script.indexOf(
            'validate_source_estimation_external_input_worklist.ps1',
          ),
        ),
      );
      expect(
        script.indexOf(
          'validate_source_estimation_external_input_worklist.ps1',
        ),
        lessThan(
          script.indexOf(
            'validate_source_estimation_split_assignment_patch.ps1',
          ),
        ),
      );
      expect(
        script.indexOf('validate_hinet_truth_quality_review.ps1'),
        lessThan(
          script.indexOf(
            'validate_source_estimation_split_assignment_patch.ps1',
          ),
        ),
      );
      expect(
        script.indexOf('validate_source_estimation_split_assignment_patch.ps1'),
        lessThan(script.indexOf('validate_source_candidate_region_suite.ps1')),
      );
      expect(script, contains('source_estimation_validation_suite_v1'));
      expect(
        script,
        contains('source_estimation_split_audit_validation_failed'),
      );
      expect(
        script,
        contains(
          'source_estimation_split_assignment_readiness_validation_failed',
        ),
      );
      expect(
        script,
        contains('source_estimation_split_blocker_queue_validation_failed'),
      );
      expect(
        script,
        contains(
          'final_catalog_or_hinet_revision_review_packet_validation_failed',
        ),
      );
      expect(script, contains('jma_catalog_availability_validation_failed'));
      expect(
        script,
        contains('jma_final_catalog_review_packet_validation_failed'),
      );
      expect(
        script,
        contains('jma_reference_event_candidates_validation_failed'),
      );
      expect(
        script,
        contains('jma_reference_capture_association_validation_failed'),
      );
      expect(
        script,
        contains('jma_reference_capture_review_packet_validation_failed'),
      );
      expect(script, contains('hinet_truth_quality_review_validation_failed'));
      expect(
        script,
        contains('hinet_capture_provenance_review_validation_failed'),
      );
      expect(
        script,
        contains('hinet_capture_exclusion_templates_validation_failed'),
      );
      expect(
        script,
        contains('hinet_capture_exclusion_review_packet_validation_failed'),
      );
      expect(script, contains('hinet_capture_repair_probe_validation_failed'));
      expect(
        script,
        contains('hinet_truth_quality_review_queue_validation_failed'),
      );
      expect(script, contains('validate_hinet_external_evidence_targets.ps1'));
      expect(
        script,
        contains('hinet_authenticated_export_review_validation_failed'),
      );
      expect(
        script,
        contains('hinet_authenticated_export_row_templates_validation_failed'),
      );
      expect(
        script,
        contains('hinet_authenticated_export_review_packet_validation_failed'),
      );
      expect(
        script,
        contains('source_estimation_external_input_queue_validation_failed'),
      );
      expect(
        script,
        contains(
          'source_estimation_external_input_templates_validation_failed',
        ),
      );
      expect(
        script,
        contains('source_estimation_external_input_delta_validation_failed'),
      );
      expect(
        script,
        contains('source_estimation_external_input_attempts_validation_failed'),
      );
      expect(
        script,
        contains('source_estimation_external_input_worklist_validation_failed'),
      );
      expect(
        script,
        contains('source_trigger_threshold_review_validation_failed'),
      );
      expect(script, contains('plum_replay_capture_gap_validation_failed'));
      expect(
        script,
        contains('source_estimation_split_assignment_patch_validation_failed'),
      );
      expect(
        script,
        contains('source_candidate_region_suite_validation_failed'),
      );
      expect(
        script.indexOf(r'Set-Content -Path "$summaryDirectory\summary.json"'),
        lessThan(
          script.indexOf('source_estimation_validation_suite_test.dart'),
        ),
      );
    },
  );

  test('source-estimation validation suite summary records all guards', () {
    final summaryFile = File(
      '.dart_tool/source_estimation_validation_suite/summary.json',
    );
    if (!summaryFile.existsSync()) {
      markTestSkipped(
        'Missing validation suite summary. Run '
        '`powershell -NoProfile -ExecutionPolicy Bypass -File '
        'tools\\validate_source_estimation_suite.ps1`.',
      );
      return;
    }

    final summary =
        jsonDecode(summaryFile.readAsStringSync()) as Map<String, Object?>;
    expect(summary['schemaVersion'], 'source_estimation_validation_suite_v1');
    expect(summary['status'], 'pass');
    expect(
      summary['splitAuditReport'],
      '.dart_tool\\source_estimation_split_audit\\report.json',
    );
    expect(
      summary['splitAssignmentReadinessReport'],
      '.dart_tool\\source_estimation_split_assignment_readiness\\report.json',
    );
    expect(
      summary['splitBlockerQueueReport'],
      '.dart_tool\\source_estimation_split_blocker_queue\\report.json',
    );
    expect(
      summary['finalCatalogOrHinetRevisionReviewPacketReport'],
      '.dart_tool\\final_catalog_or_hinet_revision_review_packet\\report.json',
    );
    expect(
      summary['jmaCatalogAvailabilityReport'],
      '.dart_tool\\jma_catalog_availability_report\\report.json',
    );
    expect(
      summary['jmaFinalCatalogReviewPacketReport'],
      '.dart_tool\\jma_final_catalog_review_packet\\report.json',
    );
    expect(
      summary['jmaReferenceEventCandidatesSummary'],
      '.dart_tool\\jma_reference_event_candidates\\summary.json',
    );
    expect(
      summary['jmaReferenceCaptureAssociationReport'],
      '.dart_tool\\jma_reference_capture_association\\report.json',
    );
    expect(
      summary['jmaReferenceCaptureReviewPacketReport'],
      '.dart_tool\\jma_reference_capture_review_packet\\report.json',
    );
    expect(
      summary['hinetTruthQualityReviewReport'],
      '.dart_tool\\hinet_truth_quality_review\\report.json',
    );
    expect(
      summary['hinetCaptureProvenanceReviewReport'],
      '.dart_tool\\hinet_capture_provenance_review\\report.json',
    );
    expect(
      summary['hinetCaptureExclusionTemplatesReport'],
      '.dart_tool\\hinet_capture_exclusion_templates\\report.json',
    );
    expect(
      summary['hinetCaptureExclusionReviewPacketReport'],
      '.dart_tool\\hinet_capture_exclusion_review_packet\\report.json',
    );
    expect(
      summary['hinetCaptureRepairProbeReport'],
      '.dart_tool\\hinet_capture_repair_probe\\report.json',
    );
    expect(
      summary['hinetTruthQualityReviewQueueReport'],
      '.dart_tool\\hinet_truth_quality_review_queue\\report.json',
    );
    expect(
      summary['hinetExternalEvidenceTargets'],
      'docs\\data\\hinet_external_evidence_targets.json',
    );
    expect(
      summary['hinetAuthenticatedExportRequest'],
      'docs\\data\\hinet_authenticated_export_request.json',
    );
    expect(
      summary['hinetAuthenticatedExportRows'],
      'docs\\data\\hinet_authenticated_export_rows.json',
    );
    expect(
      summary['hinetAuthenticatedExportReviewReport'],
      '.dart_tool\\hinet_authenticated_export_review\\report.json',
    );
    expect(
      summary['hinetAuthenticatedExportRowTemplatesReport'],
      '.dart_tool\\hinet_authenticated_export_row_templates\\report.json',
    );
    expect(
      summary['hinetAuthenticatedExportReviewPacketReport'],
      '.dart_tool\\hinet_authenticated_export_review_packet\\report.json',
    );
    expect(
      summary['externalInputQueueReport'],
      '.dart_tool\\source_estimation_external_input_queue\\report.json',
    );
    expect(
      summary['externalInputTemplatesReport'],
      '.dart_tool\\source_estimation_external_input_templates\\report.json',
    );
    expect(
      summary['externalInputDeltaReport'],
      '.dart_tool\\source_estimation_external_input_delta\\report.json',
    );
    expect(
      summary['externalInputAttemptsReport'],
      '.dart_tool\\source_estimation_external_input_attempts\\report.json',
    );
    expect(
      summary['externalInputWorklistReport'],
      '.dart_tool\\source_estimation_external_input_worklist\\report.json',
    );
    expect(
      summary['sourceTriggerThresholdReviewReport'],
      '.dart_tool\\source_trigger_threshold_review\\report.json',
    );
    expect(
      summary['plumReplayCaptureGapReport'],
      '.dart_tool\\plum_replay_capture_gap\\report.json',
    );
    expect(
      summary['splitAssignmentPatchReport'],
      '.dart_tool\\source_estimation_split_assignment_patch\\report.json',
    );
    expect(
      summary['candidateRegionSuiteSummary'],
      '.dart_tool\\source_candidate_region_suite\\summary.json',
    );

    final validations = {
      for (final rawValidation in summary['validations'] as List)
        (rawValidation as Map)['name'] as String: rawValidation
            .cast<String, Object?>(),
    };
    expect(
      validations.keys,
      containsAll({
        'source_estimation_split_audit',
        'source_estimation_split_assignment_readiness',
        'source_estimation_split_blocker_queue',
        'final_catalog_or_hinet_revision_review_packet',
        'jma_catalog_availability',
        'jma_final_catalog_review_packet',
        'jma_reference_event_candidates',
        'jma_reference_capture_association',
        'jma_reference_capture_review_packet',
        'hinet_truth_quality_review',
        'hinet_capture_provenance_review',
        'hinet_capture_exclusion_templates',
        'hinet_capture_exclusion_review_packet',
        'hinet_capture_repair_probe',
        'hinet_truth_quality_review_queue',
        'hinet_external_evidence_targets',
        'hinet_authenticated_export_review',
        'hinet_authenticated_export_row_templates',
        'hinet_authenticated_export_review_packet',
        'source_estimation_external_input_queue',
        'source_estimation_external_input_templates',
        'source_estimation_external_input_delta',
        'source_estimation_external_input_attempts',
        'source_estimation_external_input_worklist',
        'source_trigger_threshold_review',
        'plum_replay_capture_gap',
        'source_estimation_split_assignment_patch',
        'source_candidate_region_suite',
      }),
    );
    expect(
      validations.values.every((entry) => entry['status'] == 'pass'),
      isTrue,
    );

    final splitAudit = validations['source_estimation_split_audit']!;
    expect(splitAudit['reportStatus'], 'pass');
    expect(splitAudit['reportErrors'], isEmpty);
    expect(
      splitAudit['reportWarnings'],
      contains('unassigned_reference_event_count:12'),
    );
    expect(
      splitAudit['reportWarnings'],
      isNot(contains('independent_quiet_window_count_below_2:1')),
    );

    final assignmentReadiness =
        validations['source_estimation_split_assignment_readiness']!;
    expect(assignmentReadiness['reportStatus'], 'pass');
    expect(assignmentReadiness['reportErrors'], isEmpty);
    expect(
      assignmentReadiness['reportWarnings'],
      contains('recent_jma_final_catalog_links_pending:9'),
    );
    expect(
      assignmentReadiness['reportWarnings'],
      isNot(
        contains(
          startsWith('split_assignment_ready_cases_require_manual_split:'),
        ),
      ),
    );
    expect(assignmentReadiness['readyForFrozenSplitCount'], 7);
    expect(assignmentReadiness['blockedByManualSplitAssignmentCount'], 11);
    expect(assignmentReadiness['readyForManualSplitAssignmentCount'], 0);
    expect(
      (assignmentReadiness['datasetUseTierCounts'] as Map)
          .cast<String, Object?>(),
      {
        'metadata_only_or_incomplete': 4,
        'diagnostic_ready': 8,
        'strict_ready': 7,
      },
    );

    final blockerQueue = validations['source_estimation_split_blocker_queue']!;
    expect(
      blockerQueue['command'],
      'tools\\validate_source_estimation_split_blocker_queue.ps1 '
      '-UseExistingReadiness',
    );
    expect(blockerQueue['reportStatus'], 'pass');
    expect(blockerQueue['reportErrors'], isEmpty);
    expect(
      blockerQueue['reportWarnings'],
      isNot(contains('manual_ready_cases_still_unassigned')),
    );
    expect(blockerQueue['blockedCaseCount'], 12);
    expect(blockerQueue['completedSplitAssignmentCount'], 7);
    expect(blockerQueue['readyForManualSplitAssignmentCount'], 0);

    final finalCatalogOrHinetRevisionReviewPacket =
        validations['final_catalog_or_hinet_revision_review_packet']!;
    expect(
      finalCatalogOrHinetRevisionReviewPacket['command'],
      'tools\\build_final_catalog_or_hinet_revision_review_packet.dart',
    );
    expect(finalCatalogOrHinetRevisionReviewPacket['reportStatus'], 'pass');
    expect(finalCatalogOrHinetRevisionReviewPacket['reportErrors'], isEmpty);
    expect(finalCatalogOrHinetRevisionReviewPacket['reportWarnings'], isEmpty);
    expect(finalCatalogOrHinetRevisionReviewPacket['packetCount'], 1);
    expect(
      finalCatalogOrHinetRevisionReviewPacket['manualReviewRequiredCount'],
      1,
    );
    expect(
      finalCatalogOrHinetRevisionReviewPacket['automaticClearanceCount'],
      0,
    );
    expect(finalCatalogOrHinetRevisionReviewPacket['fixtureMutationCount'], 0);
    expect(
      finalCatalogOrHinetRevisionReviewPacket['splitManifestMutationCount'],
      0,
    );
    expect(finalCatalogOrHinetRevisionReviewPacket['truthPromotionCount'], 0);
    expect(
      finalCatalogOrHinetRevisionReviewPacket['negativeAttemptOnlyCount'],
      1,
    );
    expect(
      finalCatalogOrHinetRevisionReviewPacket['resolutionAllowedByPacketCount'],
      0,
    );

    final jmaAvailability = validations['jma_catalog_availability']!;
    expect(
      jmaAvailability['command'],
      'tools\\validate_jma_catalog_availability.ps1 -UseExistingReadiness',
    );
    expect(jmaAvailability['reportStatus'], 'pass');
    expect(jmaAvailability['reportErrors'], isEmpty);
    expect(jmaAvailability['reportWarnings'], isEmpty);
    expect(jmaAvailability['jmaCatalogBlockerCount'], 9);
    expect(jmaAvailability['externalCatalogNotYetAvailableCount'], 9);
    expect(jmaAvailability['catalogAvailableLinkMissingCount'], 0);

    final jmaFinalCatalogReviewPacket =
        validations['jma_final_catalog_review_packet']!;
    expect(
      jmaFinalCatalogReviewPacket['command'],
      'tools\\build_jma_final_catalog_review_packet.dart',
    );
    expect(jmaFinalCatalogReviewPacket['reportStatus'], 'pass');
    expect(jmaFinalCatalogReviewPacket['reportErrors'], isEmpty);
    expect(jmaFinalCatalogReviewPacket['reportWarnings'], isEmpty);
    expect(jmaFinalCatalogReviewPacket['packetCount'], 9);
    expect(jmaFinalCatalogReviewPacket['manualReviewRequiredCount'], 9);
    expect(jmaFinalCatalogReviewPacket['automaticClearanceCount'], 0);
    expect(jmaFinalCatalogReviewPacket['fixtureMutationCount'], 0);
    expect(jmaFinalCatalogReviewPacket['catalogTruthWriteCount'], 0);
    expect(jmaFinalCatalogReviewPacket['writeLinkAllowedCount'], 0);
    expect(
      jmaFinalCatalogReviewPacket['externalCatalogNotYetAvailableCount'],
      9,
    );

    final jmaCandidates = validations['jma_reference_event_candidates']!;
    expect(jmaCandidates['reportStatus'], 'pass');
    expect(jmaCandidates['reportErrors'], isEmpty);
    expect(jmaCandidates['eventCount'], 7);
    expect(jmaCandidates['pendingCaptureCount'], 2);
    expect(jmaCandidates['captureAssociatedCount'], 5);
    expect(jmaCandidates['referenceOnlyCount'], 7);
    expect(jmaCandidates['finalCatalogPendingCount'], 7);
    expect(jmaCandidates['eqscFinalReportCount'], 1);
    expect(jmaCandidates['equakeFinalReportCount'], 3);
    expect(jmaCandidates['equakeNonFinalSnapshotCount'], 1);

    final jmaCaptureAssociation =
        validations['jma_reference_capture_association']!;
    expect(jmaCaptureAssociation['reportStatus'], 'pass');
    expect(jmaCaptureAssociation['reportErrors'], isEmpty);
    expect(jmaCaptureAssociation['reportWarnings'], isEmpty);
    expect(jmaCaptureAssociation['eventCount'], 7);
    expect(jmaCaptureAssociation['pendingCaptureCount'], 2);
    expect(jmaCaptureAssociation['captureAssociatedCount'], 5);
    expect(jmaCaptureAssociation['captureAssociationMissingCount'], 2);
    expect(jmaCaptureAssociation['localCaptureCandidateMatchCount'], 4);
    expect(jmaCaptureAssociation['localFixtureCandidateMatchCount'], 0);
    expect(jmaCaptureAssociation['captureDirectoryMissingCount'], 0);
    expect(jmaCaptureAssociation['captureReplayManifestMissingCount'], 0);

    final jmaCaptureReviewPacket =
        validations['jma_reference_capture_review_packet']!;
    expect(
      jmaCaptureReviewPacket['command'],
      'tools\\build_jma_reference_capture_review_packet.dart',
    );
    expect(jmaCaptureReviewPacket['reportStatus'], 'pass');
    expect(jmaCaptureReviewPacket['reportErrors'], isEmpty);
    expect(jmaCaptureReviewPacket['reportWarnings'], isEmpty);
    expect(jmaCaptureReviewPacket['packetCount'], 2);
    expect(jmaCaptureReviewPacket['manualReviewRequiredCount'], 2);
    expect(jmaCaptureReviewPacket['automaticClearanceCount'], 0);
    expect(jmaCaptureReviewPacket['manifestMutationCount'], 0);
    expect(jmaCaptureReviewPacket['captureAssociationClearedByPacketCount'], 0);
    expect(jmaCaptureReviewPacket['finalCatalogTruthCount'], 0);
    expect(jmaCaptureReviewPacket['localCandidateMatchCount'], 0);

    final hinetReview = validations['hinet_truth_quality_review']!;
    expect(
      hinetReview['command'],
      'tools\\validate_hinet_truth_quality_review.ps1 -UseExistingReadiness',
    );
    expect(hinetReview['reportStatus'], 'pass');
    expect(hinetReview['reportErrors'], isEmpty);
    expect(hinetReview['reportWarnings'], isEmpty);
    expect(hinetReview['hinetReviewCaseCount'], 7);
    expect(hinetReview['decisionCaseCount'], 7);
    expect(hinetReview['pendingDecisionCount'], 1);
    expect(hinetReview['acceptedForConstrainedReferenceSplitCount'], 6);
    expect(hinetReview['blockingEvidenceCaseCount'], 1);
    expect(hinetReview['blockingEvidenceCount'], 1);
    expect(hinetReview['captureDirectoryExistsCount'], 7);
    expect(hinetReview['captureManifestExistsCount'], 7);
    expect(hinetReview['captureProvenanceCompleteCount'], 6);
    expect(hinetReview['captureManifestFailureCount'], 1);
    expect(hinetReview['referenceIsolatedCount'], 2);
    expect(hinetReview['catalogTruthFlagMismatchCount'], 0);
    expect(hinetReview['manualReviewReadyCount'], 2);

    final hinetCaptureProvenanceReview =
        validations['hinet_capture_provenance_review']!;
    expect(
      hinetCaptureProvenanceReview['command'],
      'tools\\validate_hinet_capture_provenance_review.ps1 '
      '-UseExistingTruthReview',
    );
    expect(hinetCaptureProvenanceReview['reportStatus'], 'pass');
    expect(hinetCaptureProvenanceReview['reportErrors'], isEmpty);
    expect(hinetCaptureProvenanceReview['reportWarnings'], isEmpty);
    expect(hinetCaptureProvenanceReview['caseCount'], 1);
    expect(hinetCaptureProvenanceReview['pendingRepairOrExclusionCount'], 0);
    expect(hinetCaptureProvenanceReview['exclusionApprovedCount'], 1);
    expect(hinetCaptureProvenanceReview['readyAfterExclusionCount'], 1);
    expect(hinetCaptureProvenanceReview['unresolvedCaptureIssueCount'], 0);
    expect(hinetCaptureProvenanceReview['failedGifCount'], 1);
    expect(hinetCaptureProvenanceReview['missingFrameCount'], 1);
    expect(hinetCaptureProvenanceReview['blockingEvidenceCount'], 1);

    final hinetCaptureExclusionTemplates =
        validations['hinet_capture_exclusion_templates']!;
    expect(
      hinetCaptureExclusionTemplates['command'],
      'tools\\build_hinet_capture_exclusion_template_report.dart',
    );
    expect(hinetCaptureExclusionTemplates['reportStatus'], 'pass');
    expect(hinetCaptureExclusionTemplates['reportErrors'], isEmpty);
    expect(hinetCaptureExclusionTemplates['reportWarnings'], isEmpty);
    expect(hinetCaptureExclusionTemplates['exclusionTemplateCount'], 0);
    expect(hinetCaptureExclusionTemplates['manualReviewRequiredCount'], 0);
    expect(hinetCaptureExclusionTemplates['automaticClearanceCount'], 0);
    expect(hinetCaptureExclusionTemplates['ledgerMutationCount'], 0);
    expect(hinetCaptureExclusionTemplates['affectedFileCount'], 0);

    final hinetCaptureExclusionReviewPacket =
        validations['hinet_capture_exclusion_review_packet']!;
    expect(
      hinetCaptureExclusionReviewPacket['command'],
      'tools\\build_hinet_capture_exclusion_review_packet.dart',
    );
    expect(hinetCaptureExclusionReviewPacket['reportStatus'], 'pass');
    expect(hinetCaptureExclusionReviewPacket['reportErrors'], isEmpty);
    expect(hinetCaptureExclusionReviewPacket['reportWarnings'], isEmpty);
    expect(hinetCaptureExclusionReviewPacket['packetCount'], 0);
    expect(hinetCaptureExclusionReviewPacket['manualReviewRequiredCount'], 0);
    expect(hinetCaptureExclusionReviewPacket['automaticClearanceCount'], 0);
    expect(hinetCaptureExclusionReviewPacket['ledgerMutationCount'], 0);
    expect(hinetCaptureExclusionReviewPacket['readyAfterExclusionCount'], 0);
    expect(hinetCaptureExclusionReviewPacket['missingGifArchiveCopyCount'], 0);

    final hinetCaptureRepairProbe = validations['hinet_capture_repair_probe']!;
    expect(
      hinetCaptureRepairProbe['command'],
      'tools\\validate_hinet_capture_repair_probe.ps1 '
      '-UseExistingProvenanceReview',
    );
    expect(hinetCaptureRepairProbe['reportStatus'], 'pass');
    expect(hinetCaptureRepairProbe['reportErrors'], isEmpty);
    expect(hinetCaptureRepairProbe['caseCount'], 0);
    expect(hinetCaptureRepairProbe['affectedFileCount'], 0);
    expect(hinetCaptureRepairProbe['repairInputTemplateCount'], 0);
    expect(hinetCaptureRepairProbe['manualReviewRequiredCount'], 0);
    expect(hinetCaptureRepairProbe['automaticClearanceCount'], 0);
    expect(hinetCaptureRepairProbe['localCandidateCount'], 0);
    expect(hinetCaptureRepairProbe['validGifCandidateCount'], 0);
    expect(hinetCaptureRepairProbe['remoteHintCount'], 0);
    expect(hinetCaptureRepairProbe['invalidCandidateCount'], 0);
    expect(hinetCaptureRepairProbe['repairCandidateReadyCount'], 0);
    expect(hinetCaptureRepairProbe['unresolvedRepairCaseCount'], 0);

    final hinetReviewQueue = validations['hinet_truth_quality_review_queue']!;
    expect(
      hinetReviewQueue['command'],
      'tools\\validate_hinet_truth_quality_review_queue.ps1 '
      '-UseExistingTruthReview',
    );
    expect(hinetReviewQueue['reportStatus'], 'pass');
    expect(hinetReviewQueue['reportErrors'], isEmpty);
    expect(hinetReviewQueue['reportWarnings'], isEmpty);
    expect(hinetReviewQueue['caseCount'], 7);
    expect(hinetReviewQueue['priorityExternalEvidenceReviewCount'], 6);
    expect(hinetReviewQueue['captureRepairBlockedCount'], 1);
    expect(hinetReviewQueue['catalogFlagMismatchBlockedCount'], 0);
    expect(hinetReviewQueue['externalEvidenceMissingCount'], 1);
    expect(hinetReviewQueue['acceptedForConstrainedReferenceSplitCount'], 6);

    final hinetExternalEvidence =
        validations['hinet_external_evidence_targets']!;
    expect(
      hinetExternalEvidence['schemaVersion'],
      'hinet_external_evidence_targets_v1',
    );
    expect(hinetExternalEvidence['targetCount'], 3);
    expect(hinetExternalEvidence['pendingExternalEvidenceCount'], 3);
    expect(hinetExternalEvidence['hinetAvailabilityCheckCount'], 4);
    expect(hinetExternalEvidence['hinetLoginRequiredCheckCount'], 2);
    expect(hinetExternalEvidence['hinetAcceptedEventEvidenceCheckCount'], 0);
    expect(hinetExternalEvidence['jmaDailyFindingCount'], 3);
    expect(hinetExternalEvidence['sufficientExternalEvidenceCount'], 0);
    expect(hinetExternalEvidence['authenticatedExportRequestCount'], 6);
    expect(hinetExternalEvidence['pendingAuthenticatedExportCount'], 6);
    expect(hinetExternalEvidence['authenticatedExportRowCount'], 6);
    expect(hinetExternalEvidence['pendingAuthenticatedExportRowCount'], 0);
    expect(hinetExternalEvidence['submittedAuthenticatedExportRowCount'], 6);
    expect(hinetExternalEvidence['rejectedAuthenticatedExportRowCount'], 0);

    final authenticatedExportReview =
        validations['hinet_authenticated_export_review']!;
    expect(
      authenticatedExportReview['command'],
      'tools\\validate_hinet_authenticated_export_review.ps1 '
      '-UseExistingExternalEvidenceTargets',
    );
    expect(authenticatedExportReview['reportStatus'], 'pass');
    expect(authenticatedExportReview['reportErrors'], isEmpty);
    expect(authenticatedExportReview['reportWarnings'], isEmpty);
    expect(authenticatedExportReview['rowCount'], 6);
    expect(authenticatedExportReview['pendingExportCount'], 0);
    expect(authenticatedExportReview['submittedForReviewCount'], 6);
    expect(authenticatedExportReview['rejectedCount'], 0);
    expect(authenticatedExportReview['validSubmittedRowCount'], 6);
    expect(authenticatedExportReview['decisionEvidenceReadyCount'], 0);
    expect(authenticatedExportReview['pendingDecisionCount'], 0);
    expect(authenticatedExportReview['acceptedDecisionCount'], 6);
    expect(authenticatedExportReview['validationErrorCount'], 0);

    final authenticatedExportRowTemplates =
        validations['hinet_authenticated_export_row_templates']!;
    expect(
      authenticatedExportRowTemplates['command'],
      'tools\\build_hinet_authenticated_export_row_templates.dart',
    );
    expect(authenticatedExportRowTemplates['reportStatus'], 'pass');
    expect(authenticatedExportRowTemplates['reportErrors'], isEmpty);
    expect(authenticatedExportRowTemplates['reportWarnings'], isEmpty);
    expect(authenticatedExportRowTemplates['rowTemplateCount'], 0);
    expect(authenticatedExportRowTemplates['manualReviewRequiredCount'], 0);
    expect(authenticatedExportRowTemplates['automaticClearanceCount'], 0);
    expect(authenticatedExportRowTemplates['credentialFieldCount'], 0);

    final authenticatedExportReviewPacket =
        validations['hinet_authenticated_export_review_packet']!;
    expect(
      authenticatedExportReviewPacket['command'],
      'tools\\build_hinet_authenticated_export_review_packet.dart',
    );
    expect(authenticatedExportReviewPacket['reportStatus'], 'pass');
    expect(authenticatedExportReviewPacket['reportErrors'], isEmpty);
    expect(authenticatedExportReviewPacket['reportWarnings'], isEmpty);
    expect(authenticatedExportReviewPacket['packetCount'], 0);
    expect(authenticatedExportReviewPacket['manualReviewRequiredCount'], 0);
    expect(authenticatedExportReviewPacket['automaticClearanceCount'], 0);
    expect(authenticatedExportReviewPacket['ledgerMutationCount'], 0);
    expect(authenticatedExportReviewPacket['submittedForReviewCount'], 0);
    expect(authenticatedExportReviewPacket['decisionEvidenceReadyCount'], 0);
    expect(authenticatedExportReviewPacket['credentialFieldCount'], 0);

    final externalInputQueue =
        validations['source_estimation_external_input_queue']!;
    expect(
      externalInputQueue['command'],
      'tools\\validate_source_estimation_external_input_queue.ps1 '
      '-UseExistingDependencies',
    );
    expect(externalInputQueue['reportStatus'], 'pass');
    expect(externalInputQueue['reportErrors'], isEmpty);
    expect(externalInputQueue['reportWarnings'], isEmpty);
    expect(externalInputQueue['inputItemCount'], 6);
    expect(externalInputQueue['automaticClearanceCount'], 0);
    expect(
      (externalInputQueue['inputTypeCounts'] as Map).cast<String, Object?>(),
      {
        'final_catalog_or_hinet_revision': 1,
        'local_jma_reference_capture_package': 2,
        'versioned_jma_final_catalog_record': 3,
      },
    );

    final externalInputTemplates =
        validations['source_estimation_external_input_templates']!;
    expect(externalInputTemplates['reportStatus'], 'pass');
    expect(externalInputTemplates['reportErrors'], isEmpty);
    expect(externalInputTemplates['reportWarnings'], isEmpty);
    expect(externalInputTemplates['templateCount'], 6);
    expect(externalInputTemplates['manualReviewRequiredCount'], 6);
    expect(externalInputTemplates['automaticClearanceCount'], 0);
    expect(externalInputTemplates['ledgerMutationCount'], 0);
    expect(
      (externalInputTemplates['inputTypeCounts'] as Map)
          .cast<String, Object?>(),
      {
        'final_catalog_or_hinet_revision': 1,
        'local_jma_reference_capture_package': 2,
        'versioned_jma_final_catalog_record': 3,
      },
    );

    final externalInputDelta =
        validations['source_estimation_external_input_delta']!;
    expect(externalInputDelta['reportStatus'], 'pass');
    expect(externalInputDelta['reportErrors'], isEmpty);
    expect(externalInputDelta['reportWarnings'], isEmpty);
    expect(externalInputDelta['deltaRowCount'], 6);
    expect(externalInputDelta['matchedTemplateCount'], 6);
    expect(externalInputDelta['missingTemplateCount'], 0);
    expect(externalInputDelta['staleTemplateCount'], 0);
    expect(externalInputDelta['priorityMismatchCount'], 0);
    expect(externalInputDelta['nonManualReviewTemplateCount'], 0);
    expect(externalInputDelta['automaticClearanceTemplateCount'], 0);
    expect(externalInputDelta['coverageComplete'], isTrue);
    expect(externalInputDelta['safeTemplateSemantics'], isTrue);

    final externalInputAttempts =
        validations['source_estimation_external_input_attempts']!;
    expect(
      externalInputAttempts['command'],
      'tools\\validate_source_estimation_external_input_attempts.ps1 '
      '-UseExistingQueue',
    );
    expect(externalInputAttempts['reportStatus'], 'pass');
    expect(externalInputAttempts['reportErrors'], isEmpty);
    expect(
      externalInputAttempts['reportWarnings'],
      containsAll([
        'attempt_references_nonqueued_input:'
            'local_jma_reference_capture_package::'
            '20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21',
        'attempt_references_nonqueued_input:'
            'local_jma_reference_capture_package::'
            '20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8',
        'attempt_references_nonqueued_input:'
            'missing_gif_archive_copy::20260620_iwate_offshore_m34_ref',
      ]),
    );
    expect(externalInputAttempts['attemptCount'], 18);
    expect(externalInputAttempts['automaticClearanceCount'], 0);
    expect(externalInputAttempts['negativeAttemptOnlyCount'], 18);
    expect(
      (externalInputAttempts['inputTypeCounts'] as Map).cast<String, Object?>(),
      {
        'authenticated_hinet_export_row': 6,
        'final_catalog_or_hinet_revision': 1,
        'local_jma_reference_capture_package': 4,
        'missing_gif_archive_copy': 4,
        'versioned_jma_final_catalog_record': 3,
      },
    );

    final externalInputWorklist =
        validations['source_estimation_external_input_worklist']!;
    expect(
      externalInputWorklist['command'],
      'tools\\validate_source_estimation_external_input_worklist.ps1 '
      '-UseExistingQueue -UseExistingTemplates -UseExistingAttempts '
      '-UseExistingRepairProbe -UseExistingAuthenticatedExportPacket '
      '-UseExistingJmaReferenceCapturePacket '
      '-UseExistingJmaFinalCatalogPacket '
      '-UseExistingFinalCatalogOrHinetRevisionPacket',
    );
    expect(externalInputWorklist['reportStatus'], 'pass');
    expect(externalInputWorklist['reportErrors'], isEmpty);
    expect(externalInputWorklist['reportWarnings'], isEmpty);
    expect(externalInputWorklist['openInputCount'], 6);
    expect(externalInputWorklist['attemptedInputCount'], 6);
    expect(externalInputWorklist['unattemptedInputCount'], 0);
    expect(externalInputWorklist['manualReviewRequiredCount'], 6);
    expect(externalInputWorklist['automaticClearanceCount'], 0);
    expect(externalInputWorklist['operationArtifactCount'], 6);
    expect(externalInputWorklist['highestPriority'], 20);
    expect(
      externalInputWorklist['nextInputType'],
      'local_jma_reference_capture_package',
    );
    expect(
      externalInputWorklist['nextCaseId'],
      '20260625_iwate_offshore_m46_jma_eqsc9',
    );
    expect(externalInputWorklist['nextHasAttempts'], isTrue);
    expect(
      (externalInputWorklist['inputTypeCounts'] as Map).cast<String, Object?>(),
      {
        'final_catalog_or_hinet_revision': 1,
        'local_jma_reference_capture_package': 2,
        'versioned_jma_final_catalog_record': 3,
      },
    );
    expect(
      (externalInputWorklist['attemptedInputTypeCounts'] as Map)
          .cast<String, Object?>(),
      {
        'final_catalog_or_hinet_revision': 1,
        'local_jma_reference_capture_package': 2,
        'versioned_jma_final_catalog_record': 3,
      },
    );

    final thresholdReview = validations['source_trigger_threshold_review']!;
    expect(thresholdReview['reportStatus'], 'pass');
    expect(thresholdReview['reportErrors'], isEmpty);
    expect(
      thresholdReview['reportWarnings'],
      contains('capture_received_at_unavailable_historical_fetch'),
    );
    expect(thresholdReview['captureProvenanceLocallyCompleteCount'], 1);
    expect(thresholdReview['historicalFetchCaptureCount'], 1);
    expect(thresholdReview['sourceTriggerMissedEventCount'], 0);
    expect(thresholdReview['quietWindowCount'], 2);
    expect(thresholdReview['quietWindowPassedCount'], 2);
    expect(thresholdReview['quietWindowCandidateFrameCount'], 0);
    expect(thresholdReview['quietWindowConfirmedFrameCount'], 0);
    expect(thresholdReview['quietWindowFalseEstimateFrameCount'], 0);
    expect(thresholdReview['thresholdReviewClearedCount'], 1);
    expect(thresholdReview['noiseWindowValidationRequiredCount'], 0);

    final plumReplayCaptureGap = validations['plum_replay_capture_gap']!;
    expect(
      plumReplayCaptureGap['command'],
      'tools\\validate_plum_replay_capture_gap.ps1',
    );
    expect(plumReplayCaptureGap['reportStatus'], 'pass');
    expect(plumReplayCaptureGap['reportErrors'], isEmpty);
    expect(plumReplayCaptureGap['caseCount'], 7);
    expect(plumReplayCaptureGap['completeCaseCount'], 6);
    expect(plumReplayCaptureGap['totalGapCaseCount'], 1);
    expect(plumReplayCaptureGap['gapCaseCount'], 0);
    expect(plumReplayCaptureGap['excludedGapCaseCount'], 1);
    expect(plumReplayCaptureGap['failedGifCount'], 0);
    expect(plumReplayCaptureGap['excludedFailedGifCount'], 16);
    expect(plumReplayCaptureGap['totalFailedGifCount'], 16);

    final assignmentPatch =
        validations['source_estimation_split_assignment_patch']!;
    expect(assignmentPatch['reportStatus'], 'pass');
    expect(assignmentPatch['reportErrors'], isEmpty);
    expect(assignmentPatch['reportWarnings'], isEmpty);
    expect(assignmentPatch['applyRequested'], isFalse);
    expect(assignmentPatch['readyToApplyCount'], 0);
    expect(assignmentPatch['alreadyAppliedCount'], 7);

    final candidateRegion = validations['source_candidate_region_suite']!;
    expect(candidateRegion['reportStatus'], 'pass');
  });
}
