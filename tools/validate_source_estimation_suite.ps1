$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_split_audit.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_trigger_threshold_review.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_plum_replay_capture_gap.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_split_assignment_readiness.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_split_blocker_queue.ps1 `
  -UseExistingReadiness
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_jma_catalog_availability.ps1 `
  -UseExistingReadiness
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_jma_reference_event_candidates.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_jma_reference_capture_association.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_truth_quality_review.ps1 `
  -UseExistingReadiness
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_capture_provenance_review.ps1 `
  -UseExistingTruthReview
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_capture_repair_probe.ps1 `
  -UseExistingProvenanceReview
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_truth_quality_review_queue.ps1 `
  -UseExistingTruthReview
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_external_evidence_targets.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_authenticated_export_review.ps1 `
  -UseExistingExternalEvidenceTargets
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_external_input_queue.ps1 `
  -UseExistingDependencies
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_external_input_templates.ps1 `
  -UseExistingQueue
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_external_input_delta.ps1 `
  -UseExistingQueue `
  -UseExistingTemplates
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_external_input_attempts.ps1 `
  -UseExistingQueue
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_external_input_worklist.ps1 `
  -UseExistingQueue `
  -UseExistingTemplates `
  -UseExistingAttempts `
  -UseExistingRepairProbe `
  -UseExistingAuthenticatedExportPacket `
  -UseExistingJmaReferenceCapturePacket `
  -UseExistingJmaFinalCatalogPacket `
  -UseExistingFinalCatalogOrHinetRevisionPacket
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_split_assignment_patch.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_candidate_region_suite.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$summaryDirectory = '.dart_tool\source_estimation_validation_suite'
New-Item -ItemType Directory -Force -Path $summaryDirectory | Out-Null

$splitAuditReportPath = '.dart_tool\source_estimation_split_audit\report.json'
$splitAssignmentReadinessReportPath = '.dart_tool\source_estimation_split_assignment_readiness\report.json'
$splitBlockerQueueReportPath = '.dart_tool\source_estimation_split_blocker_queue\report.json'
$finalCatalogOrHinetRevisionReviewPacketReportPath = '.dart_tool\final_catalog_or_hinet_revision_review_packet\report.json'
$jmaCatalogAvailabilityReportPath = '.dart_tool\jma_catalog_availability_report\report.json'
$jmaFinalCatalogReviewPacketReportPath = '.dart_tool\jma_final_catalog_review_packet\report.json'
$jmaReferenceEventCandidatesSummaryPath = '.dart_tool\jma_reference_event_candidates\summary.json'
$jmaReferenceCaptureAssociationReportPath = '.dart_tool\jma_reference_capture_association\report.json'
$jmaReferenceCaptureReviewPacketReportPath = '.dart_tool\jma_reference_capture_review_packet\report.json'
$hinetTruthQualityReviewReportPath = '.dart_tool\hinet_truth_quality_review\report.json'
$hinetCaptureProvenanceReviewReportPath = '.dart_tool\hinet_capture_provenance_review\report.json'
$hinetCaptureExclusionTemplatesReportPath = '.dart_tool\hinet_capture_exclusion_templates\report.json'
$hinetCaptureExclusionReviewPacketReportPath = '.dart_tool\hinet_capture_exclusion_review_packet\report.json'
$hinetCaptureRepairProbeReportPath = '.dart_tool\hinet_capture_repair_probe\report.json'
$hinetTruthQualityReviewQueueReportPath = '.dart_tool\hinet_truth_quality_review_queue\report.json'
$hinetExternalEvidenceTargetsPath = 'docs\data\hinet_external_evidence_targets.json'
$hinetAuthenticatedExportRequestPath = 'docs\data\hinet_authenticated_export_request.json'
$hinetAuthenticatedExportRowsPath = 'docs\data\hinet_authenticated_export_rows.json'
$hinetAuthenticatedExportReviewReportPath = '.dart_tool\hinet_authenticated_export_review\report.json'
$hinetAuthenticatedExportRowTemplatesReportPath = '.dart_tool\hinet_authenticated_export_row_templates\report.json'
$hinetAuthenticatedExportReviewPacketReportPath = '.dart_tool\hinet_authenticated_export_review_packet\report.json'
$externalInputQueueReportPath = '.dart_tool\source_estimation_external_input_queue\report.json'
$externalInputTemplatesReportPath = '.dart_tool\source_estimation_external_input_templates\report.json'
$externalInputDeltaReportPath = '.dart_tool\source_estimation_external_input_delta\report.json'
$externalInputAttemptsReportPath = '.dart_tool\source_estimation_external_input_attempts\report.json'
$externalInputWorklistReportPath = '.dart_tool\source_estimation_external_input_worklist\report.json'
$sourceTriggerThresholdReviewReportPath = '.dart_tool\source_trigger_threshold_review\report.json'
$plumReplayCaptureGapReportPath = '.dart_tool\plum_replay_capture_gap\report.json'
$splitAssignmentPatchReportPath = '.dart_tool\source_estimation_split_assignment_patch\report.json'
$candidateRegionSummaryPath = '.dart_tool\source_candidate_region_suite\summary.json'
$splitAuditReport = Get-Content -Raw -Encoding UTF8 -Path $splitAuditReportPath | ConvertFrom-Json
$splitAssignmentReadinessReport = Get-Content -Raw -Encoding UTF8 -Path $splitAssignmentReadinessReportPath | ConvertFrom-Json
$splitBlockerQueueReport = Get-Content -Raw -Encoding UTF8 -Path $splitBlockerQueueReportPath | ConvertFrom-Json
$finalCatalogOrHinetRevisionReviewPacketReport = Get-Content -Raw -Encoding UTF8 -Path $finalCatalogOrHinetRevisionReviewPacketReportPath | ConvertFrom-Json
$jmaCatalogAvailabilityReport = Get-Content -Raw -Encoding UTF8 -Path $jmaCatalogAvailabilityReportPath | ConvertFrom-Json
$jmaFinalCatalogReviewPacketReport = Get-Content -Raw -Encoding UTF8 -Path $jmaFinalCatalogReviewPacketReportPath | ConvertFrom-Json
$jmaReferenceEventCandidatesSummary = Get-Content -Raw -Encoding UTF8 -Path $jmaReferenceEventCandidatesSummaryPath | ConvertFrom-Json
$jmaReferenceCaptureAssociationReport = Get-Content -Raw -Encoding UTF8 -Path $jmaReferenceCaptureAssociationReportPath | ConvertFrom-Json
$jmaReferenceCaptureReviewPacketReport = Get-Content -Raw -Encoding UTF8 -Path $jmaReferenceCaptureReviewPacketReportPath | ConvertFrom-Json
$hinetTruthQualityReviewReport = Get-Content -Raw -Encoding UTF8 -Path $hinetTruthQualityReviewReportPath | ConvertFrom-Json
$hinetCaptureProvenanceReviewReport = Get-Content -Raw -Encoding UTF8 -Path $hinetCaptureProvenanceReviewReportPath | ConvertFrom-Json
$hinetCaptureExclusionTemplatesReport = Get-Content -Raw -Encoding UTF8 -Path $hinetCaptureExclusionTemplatesReportPath | ConvertFrom-Json
$hinetCaptureExclusionReviewPacketReport = Get-Content -Raw -Encoding UTF8 -Path $hinetCaptureExclusionReviewPacketReportPath | ConvertFrom-Json
$hinetCaptureRepairProbeReport = Get-Content -Raw -Encoding UTF8 -Path $hinetCaptureRepairProbeReportPath | ConvertFrom-Json
$hinetTruthQualityReviewQueueReport = Get-Content -Raw -Encoding UTF8 -Path $hinetTruthQualityReviewQueueReportPath | ConvertFrom-Json
$hinetExternalEvidenceTargets = Get-Content -Raw -Encoding UTF8 -Path $hinetExternalEvidenceTargetsPath | ConvertFrom-Json
$hinetAuthenticatedExportRequest = Get-Content -Raw -Encoding UTF8 -Path $hinetAuthenticatedExportRequestPath | ConvertFrom-Json
$hinetAuthenticatedExportRows = Get-Content -Raw -Encoding UTF8 -Path $hinetAuthenticatedExportRowsPath | ConvertFrom-Json
$hinetAuthenticatedExportReviewReport = Get-Content -Raw -Encoding UTF8 -Path $hinetAuthenticatedExportReviewReportPath | ConvertFrom-Json
$hinetAuthenticatedExportRowTemplatesReport = Get-Content -Raw -Encoding UTF8 -Path $hinetAuthenticatedExportRowTemplatesReportPath | ConvertFrom-Json
$hinetAuthenticatedExportReviewPacketReport = Get-Content -Raw -Encoding UTF8 -Path $hinetAuthenticatedExportReviewPacketReportPath | ConvertFrom-Json
$externalInputQueueReport = Get-Content -Raw -Encoding UTF8 -Path $externalInputQueueReportPath | ConvertFrom-Json
$externalInputTemplatesReport = Get-Content -Raw -Encoding UTF8 -Path $externalInputTemplatesReportPath | ConvertFrom-Json
$externalInputDeltaReport = Get-Content -Raw -Encoding UTF8 -Path $externalInputDeltaReportPath | ConvertFrom-Json
$externalInputAttemptsReport = Get-Content -Raw -Encoding UTF8 -Path $externalInputAttemptsReportPath | ConvertFrom-Json
$externalInputWorklistReport = Get-Content -Raw -Encoding UTF8 -Path $externalInputWorklistReportPath | ConvertFrom-Json
$sourceTriggerThresholdReviewReport = Get-Content -Raw -Encoding UTF8 -Path $sourceTriggerThresholdReviewReportPath | ConvertFrom-Json
$plumReplayCaptureGapReport = Get-Content -Raw -Encoding UTF8 -Path $plumReplayCaptureGapReportPath | ConvertFrom-Json
$splitAssignmentPatchReport = Get-Content -Raw -Encoding UTF8 -Path $splitAssignmentPatchReportPath | ConvertFrom-Json
$candidateRegionSummary = Get-Content -Raw -Encoding UTF8 -Path $candidateRegionSummaryPath | ConvertFrom-Json

$splitAuditErrors = @($splitAuditReport.errors)
if ($splitAuditReport.status -ne 'pass' -or $splitAuditErrors.Count -ne 0) {
  Write-Error "source_estimation_split_audit_validation_failed"
  exit 1
}

$splitAssignmentReadinessErrors = @($splitAssignmentReadinessReport.errors)
if ($splitAssignmentReadinessReport.status -ne 'pass' -or $splitAssignmentReadinessErrors.Count -ne 0) {
  Write-Error "source_estimation_split_assignment_readiness_validation_failed"
  exit 1
}

$splitBlockerQueueErrors = @($splitBlockerQueueReport.errors)
if ($splitBlockerQueueReport.status -ne 'pass' -or $splitBlockerQueueErrors.Count -ne 0) {
  Write-Error "source_estimation_split_blocker_queue_validation_failed"
  exit 1
}

$finalCatalogOrHinetRevisionReviewPacketErrors = @($finalCatalogOrHinetRevisionReviewPacketReport.errors)
if ($finalCatalogOrHinetRevisionReviewPacketReport.status -ne 'pass' -or $finalCatalogOrHinetRevisionReviewPacketErrors.Count -ne 0) {
  Write-Error "final_catalog_or_hinet_revision_review_packet_validation_failed"
  exit 1
}

$jmaCatalogAvailabilityErrors = @($jmaCatalogAvailabilityReport.errors)
if ($jmaCatalogAvailabilityReport.status -ne 'pass' -or $jmaCatalogAvailabilityErrors.Count -ne 0) {
  Write-Error "jma_catalog_availability_validation_failed"
  exit 1
}

$jmaFinalCatalogReviewPacketErrors = @($jmaFinalCatalogReviewPacketReport.errors)
if ($jmaFinalCatalogReviewPacketReport.status -ne 'pass' -or $jmaFinalCatalogReviewPacketErrors.Count -ne 0) {
  Write-Error "jma_final_catalog_review_packet_validation_failed"
  exit 1
}

$jmaReferenceEventCandidatesErrors = @($jmaReferenceEventCandidatesSummary.errors)
if ($jmaReferenceEventCandidatesSummary.status -ne 'pass' -or $jmaReferenceEventCandidatesErrors.Count -ne 0) {
  Write-Error "jma_reference_event_candidates_validation_failed"
  exit 1
}

$jmaReferenceCaptureAssociationErrors = @($jmaReferenceCaptureAssociationReport.errors)
if ($jmaReferenceCaptureAssociationReport.status -ne 'pass' -or $jmaReferenceCaptureAssociationErrors.Count -ne 0) {
  Write-Error "jma_reference_capture_association_validation_failed"
  exit 1
}

$jmaReferenceCaptureReviewPacketErrors = @($jmaReferenceCaptureReviewPacketReport.errors)
if ($jmaReferenceCaptureReviewPacketReport.status -ne 'pass' -or $jmaReferenceCaptureReviewPacketErrors.Count -ne 0) {
  Write-Error "jma_reference_capture_review_packet_validation_failed"
  exit 1
}

$hinetTruthQualityReviewErrors = @($hinetTruthQualityReviewReport.errors)
if ($hinetTruthQualityReviewReport.status -ne 'pass' -or $hinetTruthQualityReviewErrors.Count -ne 0) {
  Write-Error "hinet_truth_quality_review_validation_failed"
  exit 1
}

$hinetCaptureProvenanceReviewErrors = @($hinetCaptureProvenanceReviewReport.errors)
if ($hinetCaptureProvenanceReviewReport.status -ne 'pass' -or $hinetCaptureProvenanceReviewErrors.Count -ne 0) {
  Write-Error "hinet_capture_provenance_review_validation_failed"
  exit 1
}

$hinetCaptureExclusionTemplateErrors = @($hinetCaptureExclusionTemplatesReport.errors)
if ($hinetCaptureExclusionTemplatesReport.status -ne 'pass' -or $hinetCaptureExclusionTemplateErrors.Count -ne 0) {
  Write-Error "hinet_capture_exclusion_templates_validation_failed"
  exit 1
}

$hinetCaptureExclusionReviewPacketErrors = @($hinetCaptureExclusionReviewPacketReport.errors)
if ($hinetCaptureExclusionReviewPacketReport.status -ne 'pass' -or $hinetCaptureExclusionReviewPacketErrors.Count -ne 0) {
  Write-Error "hinet_capture_exclusion_review_packet_validation_failed"
  exit 1
}

$hinetCaptureRepairProbeErrors = @($hinetCaptureRepairProbeReport.errors)
if ($hinetCaptureRepairProbeReport.status -ne 'pass' -or $hinetCaptureRepairProbeErrors.Count -ne 0) {
  Write-Error "hinet_capture_repair_probe_validation_failed"
  exit 1
}

$hinetTruthQualityReviewQueueErrors = @($hinetTruthQualityReviewQueueReport.errors)
if ($hinetTruthQualityReviewQueueReport.status -ne 'pass' -or $hinetTruthQualityReviewQueueErrors.Count -ne 0) {
  Write-Error "hinet_truth_quality_review_queue_validation_failed"
  exit 1
}

$hinetAuthenticatedExportReviewErrors = @($hinetAuthenticatedExportReviewReport.errors)
if ($hinetAuthenticatedExportReviewReport.status -ne 'pass' -or $hinetAuthenticatedExportReviewErrors.Count -ne 0) {
  Write-Error "hinet_authenticated_export_review_validation_failed"
  exit 1
}

$hinetAuthenticatedExportRowTemplateErrors = @($hinetAuthenticatedExportRowTemplatesReport.errors)
if ($hinetAuthenticatedExportRowTemplatesReport.status -ne 'pass' -or $hinetAuthenticatedExportRowTemplateErrors.Count -ne 0) {
  Write-Error "hinet_authenticated_export_row_templates_validation_failed"
  exit 1
}

$hinetAuthenticatedExportReviewPacketErrors = @($hinetAuthenticatedExportReviewPacketReport.errors)
if ($hinetAuthenticatedExportReviewPacketReport.status -ne 'pass' -or $hinetAuthenticatedExportReviewPacketErrors.Count -ne 0) {
  Write-Error "hinet_authenticated_export_review_packet_validation_failed"
  exit 1
}

$externalInputQueueErrors = @($externalInputQueueReport.errors)
if ($externalInputQueueReport.status -ne 'pass' -or $externalInputQueueErrors.Count -ne 0) {
  Write-Error "source_estimation_external_input_queue_validation_failed"
  exit 1
}

$externalInputTemplatesErrors = @($externalInputTemplatesReport.errors)
if ($externalInputTemplatesReport.status -ne 'pass' -or $externalInputTemplatesErrors.Count -ne 0) {
  Write-Error "source_estimation_external_input_templates_validation_failed"
  exit 1
}

$externalInputDeltaErrors = @($externalInputDeltaReport.errors)
if ($externalInputDeltaReport.status -ne 'pass' -or $externalInputDeltaErrors.Count -ne 0) {
  Write-Error "source_estimation_external_input_delta_validation_failed"
  exit 1
}

$externalInputAttemptsErrors = @($externalInputAttemptsReport.errors)
if ($externalInputAttemptsReport.status -ne 'pass' -or $externalInputAttemptsErrors.Count -ne 0) {
  Write-Error "source_estimation_external_input_attempts_validation_failed"
  exit 1
}

$externalInputWorklistErrors = @($externalInputWorklistReport.errors)
if ($externalInputWorklistReport.status -ne 'pass' -or $externalInputWorklistErrors.Count -ne 0) {
  Write-Error "source_estimation_external_input_worklist_validation_failed"
  exit 1
}

$sourceTriggerThresholdReviewErrors = @($sourceTriggerThresholdReviewReport.errors)
if ($sourceTriggerThresholdReviewReport.status -ne 'pass' -or $sourceTriggerThresholdReviewErrors.Count -ne 0) {
  Write-Error "source_trigger_threshold_review_validation_failed"
  exit 1
}

$plumReplayCaptureGapErrors = @($plumReplayCaptureGapReport.errors)
if ($plumReplayCaptureGapReport.status -ne 'pass' -or $plumReplayCaptureGapErrors.Count -ne 0) {
  Write-Error "plum_replay_capture_gap_validation_failed"
  exit 1
}

$splitAssignmentPatchErrors = @($splitAssignmentPatchReport.errors)
if ($splitAssignmentPatchReport.status -ne 'pass' -or $splitAssignmentPatchErrors.Count -ne 0) {
  Write-Error "source_estimation_split_assignment_patch_validation_failed"
  exit 1
}

if ($candidateRegionSummary.status -ne 'pass') {
  Write-Error "source_candidate_region_suite_validation_failed"
  exit 1
}

$summary = [ordered]@{
  schemaVersion = 'source_estimation_validation_suite_v1'
  createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  status = 'pass'
  splitAuditReport = $splitAuditReportPath
  splitAssignmentReadinessReport = $splitAssignmentReadinessReportPath
  splitBlockerQueueReport = $splitBlockerQueueReportPath
  finalCatalogOrHinetRevisionReviewPacketReport = $finalCatalogOrHinetRevisionReviewPacketReportPath
  jmaCatalogAvailabilityReport = $jmaCatalogAvailabilityReportPath
  jmaFinalCatalogReviewPacketReport = $jmaFinalCatalogReviewPacketReportPath
  jmaReferenceEventCandidatesSummary = $jmaReferenceEventCandidatesSummaryPath
  jmaReferenceCaptureAssociationReport = $jmaReferenceCaptureAssociationReportPath
  jmaReferenceCaptureReviewPacketReport = $jmaReferenceCaptureReviewPacketReportPath
  hinetTruthQualityReviewReport = $hinetTruthQualityReviewReportPath
  hinetCaptureProvenanceReviewReport = $hinetCaptureProvenanceReviewReportPath
  hinetCaptureExclusionTemplatesReport = $hinetCaptureExclusionTemplatesReportPath
  hinetCaptureExclusionReviewPacketReport = $hinetCaptureExclusionReviewPacketReportPath
  hinetCaptureRepairProbeReport = $hinetCaptureRepairProbeReportPath
  hinetTruthQualityReviewQueueReport = $hinetTruthQualityReviewQueueReportPath
  hinetExternalEvidenceTargets = $hinetExternalEvidenceTargetsPath
  hinetAuthenticatedExportRequest = $hinetAuthenticatedExportRequestPath
  hinetAuthenticatedExportRows = $hinetAuthenticatedExportRowsPath
  hinetAuthenticatedExportReviewReport = $hinetAuthenticatedExportReviewReportPath
  hinetAuthenticatedExportRowTemplatesReport = $hinetAuthenticatedExportRowTemplatesReportPath
  hinetAuthenticatedExportReviewPacketReport = $hinetAuthenticatedExportReviewPacketReportPath
  externalInputQueueReport = $externalInputQueueReportPath
  externalInputTemplatesReport = $externalInputTemplatesReportPath
  externalInputDeltaReport = $externalInputDeltaReportPath
  externalInputAttemptsReport = $externalInputAttemptsReportPath
  externalInputWorklistReport = $externalInputWorklistReportPath
  sourceTriggerThresholdReviewReport = $sourceTriggerThresholdReviewReportPath
  plumReplayCaptureGapReport = $plumReplayCaptureGapReportPath
  splitAssignmentPatchReport = $splitAssignmentPatchReportPath
  candidateRegionSuiteSummary = $candidateRegionSummaryPath
  validations = @(
    [ordered]@{
      name = 'source_estimation_split_audit'
      command = 'tools\validate_source_estimation_split_audit.ps1'
      status = 'pass'
      reportStatus = $splitAuditReport.status
      reportErrors = $splitAuditErrors
      reportWarnings = @($splitAuditReport.warnings)
    },
    [ordered]@{
      name = 'source_estimation_split_assignment_readiness'
      command = 'tools\validate_source_estimation_split_assignment_readiness.ps1'
      status = 'pass'
      reportStatus = $splitAssignmentReadinessReport.status
      reportErrors = $splitAssignmentReadinessErrors
      reportWarnings = @($splitAssignmentReadinessReport.warnings)
      readyForFrozenSplitCount = $splitAssignmentReadinessReport.summary.readyForFrozenSplitCount
      readyForManualSplitAssignmentCount = $splitAssignmentReadinessReport.summary.readyForManualSplitAssignmentCount
      blockedByManualSplitAssignmentCount = $splitAssignmentReadinessReport.summary.blockedByManualSplitAssignmentCount
      datasetUseTierCounts = $splitAssignmentReadinessReport.summary.datasetUseTierCounts
    },
    [ordered]@{
      name = 'source_estimation_split_blocker_queue'
      command = 'tools\validate_source_estimation_split_blocker_queue.ps1 -UseExistingReadiness'
      status = 'pass'
      reportStatus = $splitBlockerQueueReport.status
      reportErrors = $splitBlockerQueueErrors
      reportWarnings = @($splitBlockerQueueReport.warnings)
      blockedCaseCount = $splitBlockerQueueReport.summary.blockedCaseCount
      completedSplitAssignmentCount = $splitBlockerQueueReport.summary.completedSplitAssignmentCount
      readyForManualSplitAssignmentCount = $splitBlockerQueueReport.summary.readyForManualSplitAssignmentCount
    },
    [ordered]@{
      name = 'final_catalog_or_hinet_revision_review_packet'
      command = 'tools\build_final_catalog_or_hinet_revision_review_packet.dart'
      status = 'pass'
      reportStatus = $finalCatalogOrHinetRevisionReviewPacketReport.status
      reportErrors = $finalCatalogOrHinetRevisionReviewPacketErrors
      reportWarnings = @($finalCatalogOrHinetRevisionReviewPacketReport.warnings)
      packetCount = $finalCatalogOrHinetRevisionReviewPacketReport.summary.packetCount
      manualReviewRequiredCount = $finalCatalogOrHinetRevisionReviewPacketReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $finalCatalogOrHinetRevisionReviewPacketReport.summary.automaticClearanceCount
      fixtureMutationCount = $finalCatalogOrHinetRevisionReviewPacketReport.summary.fixtureMutationCount
      splitManifestMutationCount = $finalCatalogOrHinetRevisionReviewPacketReport.summary.splitManifestMutationCount
      truthPromotionCount = $finalCatalogOrHinetRevisionReviewPacketReport.summary.truthPromotionCount
      negativeAttemptOnlyCount = $finalCatalogOrHinetRevisionReviewPacketReport.summary.negativeAttemptOnlyCount
      resolutionAllowedByPacketCount = $finalCatalogOrHinetRevisionReviewPacketReport.summary.resolutionAllowedByPacketCount
    },
    [ordered]@{
      name = 'jma_catalog_availability'
      command = 'tools\validate_jma_catalog_availability.ps1 -UseExistingReadiness'
      status = 'pass'
      reportStatus = $jmaCatalogAvailabilityReport.status
      reportErrors = $jmaCatalogAvailabilityErrors
      reportWarnings = @($jmaCatalogAvailabilityReport.warnings)
      jmaCatalogBlockerCount = $jmaCatalogAvailabilityReport.summary.jmaCatalogBlockerCount
      externalCatalogNotYetAvailableCount = $jmaCatalogAvailabilityReport.summary.externalCatalogNotYetAvailableCount
      catalogAvailableLinkMissingCount = $jmaCatalogAvailabilityReport.summary.catalogAvailableLinkMissingCount
    },
    [ordered]@{
      name = 'jma_final_catalog_review_packet'
      command = 'tools\build_jma_final_catalog_review_packet.dart'
      status = 'pass'
      reportStatus = $jmaFinalCatalogReviewPacketReport.status
      reportErrors = $jmaFinalCatalogReviewPacketErrors
      reportWarnings = @($jmaFinalCatalogReviewPacketReport.warnings)
      packetCount = $jmaFinalCatalogReviewPacketReport.summary.packetCount
      manualReviewRequiredCount = $jmaFinalCatalogReviewPacketReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $jmaFinalCatalogReviewPacketReport.summary.automaticClearanceCount
      fixtureMutationCount = $jmaFinalCatalogReviewPacketReport.summary.fixtureMutationCount
      catalogTruthWriteCount = $jmaFinalCatalogReviewPacketReport.summary.catalogTruthWriteCount
      writeLinkAllowedCount = $jmaFinalCatalogReviewPacketReport.summary.writeLinkAllowedCount
      externalCatalogNotYetAvailableCount = $jmaFinalCatalogReviewPacketReport.summary.externalCatalogNotYetAvailableCount
    },
    [ordered]@{
      name = 'jma_reference_event_candidates'
      command = 'tools\validate_jma_reference_event_candidates.ps1'
      status = 'pass'
      reportStatus = $jmaReferenceEventCandidatesSummary.status
      reportErrors = $jmaReferenceEventCandidatesErrors
      eventCount = $jmaReferenceEventCandidatesSummary.summary.eventCount
      pendingCaptureCount = $jmaReferenceEventCandidatesSummary.summary.pendingCaptureCount
      captureAssociatedCount = $jmaReferenceEventCandidatesSummary.summary.captureAssociatedCount
      referenceOnlyCount = $jmaReferenceEventCandidatesSummary.summary.referenceOnlyCount
      finalCatalogPendingCount = $jmaReferenceEventCandidatesSummary.summary.finalCatalogPendingCount
      eqscFinalReportCount = $jmaReferenceEventCandidatesSummary.summary.eqscFinalReportCount
      equakeFinalReportCount = $jmaReferenceEventCandidatesSummary.summary.equakeFinalReportCount
      equakeNonFinalSnapshotCount = $jmaReferenceEventCandidatesSummary.summary.equakeNonFinalSnapshotCount
    },
    [ordered]@{
      name = 'jma_reference_capture_association'
      command = 'tools\validate_jma_reference_capture_association.ps1'
      status = 'pass'
      reportStatus = $jmaReferenceCaptureAssociationReport.status
      reportErrors = $jmaReferenceCaptureAssociationErrors
      reportWarnings = @($jmaReferenceCaptureAssociationReport.warnings)
      eventCount = $jmaReferenceCaptureAssociationReport.summary.eventCount
      pendingCaptureCount = $jmaReferenceCaptureAssociationReport.summary.pendingCaptureCount
      captureAssociatedCount = $jmaReferenceCaptureAssociationReport.summary.captureAssociatedCount
      captureAssociationMissingCount = $jmaReferenceCaptureAssociationReport.summary.captureAssociationMissingCount
      localCaptureCandidateMatchCount = $jmaReferenceCaptureAssociationReport.summary.localCaptureCandidateMatchCount
      localFixtureCandidateMatchCount = $jmaReferenceCaptureAssociationReport.summary.localFixtureCandidateMatchCount
      captureDirectoryMissingCount = $jmaReferenceCaptureAssociationReport.summary.captureDirectoryMissingCount
      captureReplayManifestMissingCount = $jmaReferenceCaptureAssociationReport.summary.captureReplayManifestMissingCount
    },
    [ordered]@{
      name = 'jma_reference_capture_review_packet'
      command = 'tools\build_jma_reference_capture_review_packet.dart'
      status = 'pass'
      reportStatus = $jmaReferenceCaptureReviewPacketReport.status
      reportErrors = $jmaReferenceCaptureReviewPacketErrors
      reportWarnings = @($jmaReferenceCaptureReviewPacketReport.warnings)
      packetCount = $jmaReferenceCaptureReviewPacketReport.summary.packetCount
      manualReviewRequiredCount = $jmaReferenceCaptureReviewPacketReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $jmaReferenceCaptureReviewPacketReport.summary.automaticClearanceCount
      manifestMutationCount = $jmaReferenceCaptureReviewPacketReport.summary.manifestMutationCount
      captureAssociationClearedByPacketCount = $jmaReferenceCaptureReviewPacketReport.summary.captureAssociationClearedByPacketCount
      finalCatalogTruthCount = $jmaReferenceCaptureReviewPacketReport.summary.finalCatalogTruthCount
      localCandidateMatchCount = $jmaReferenceCaptureReviewPacketReport.summary.localCandidateMatchCount
    },
    [ordered]@{
      name = 'hinet_truth_quality_review'
      command = 'tools\validate_hinet_truth_quality_review.ps1 -UseExistingReadiness'
      status = 'pass'
      reportStatus = $hinetTruthQualityReviewReport.status
      reportErrors = $hinetTruthQualityReviewErrors
      reportWarnings = @($hinetTruthQualityReviewReport.warnings)
      hinetReviewCaseCount = $hinetTruthQualityReviewReport.summary.hinetReviewCaseCount
      decisionCaseCount = $hinetTruthQualityReviewReport.summary.decisionCaseCount
      pendingDecisionCount = $hinetTruthQualityReviewReport.summary.pendingDecisionCount
      acceptedForConstrainedReferenceSplitCount = $hinetTruthQualityReviewReport.summary.acceptedForConstrainedReferenceSplitCount
      blockingEvidenceCaseCount = $hinetTruthQualityReviewReport.summary.blockingEvidenceCaseCount
      blockingEvidenceCount = $hinetTruthQualityReviewReport.summary.blockingEvidenceCount
      captureDirectoryExistsCount = $hinetTruthQualityReviewReport.summary.captureDirectoryExistsCount
      captureManifestExistsCount = $hinetTruthQualityReviewReport.summary.captureManifestExistsCount
      captureProvenanceCompleteCount = $hinetTruthQualityReviewReport.summary.captureProvenanceCompleteCount
      captureManifestFailureCount = $hinetTruthQualityReviewReport.summary.captureManifestFailureCount
      referenceIsolatedCount = $hinetTruthQualityReviewReport.summary.referenceIsolatedCount
      catalogTruthFlagMismatchCount = $hinetTruthQualityReviewReport.summary.catalogTruthFlagMismatchCount
      manualReviewReadyCount = $hinetTruthQualityReviewReport.summary.manualReviewReadyCount
    },
    [ordered]@{
      name = 'hinet_capture_provenance_review'
      command = 'tools\validate_hinet_capture_provenance_review.ps1 -UseExistingTruthReview'
      status = 'pass'
      reportStatus = $hinetCaptureProvenanceReviewReport.status
      reportErrors = $hinetCaptureProvenanceReviewErrors
      reportWarnings = @($hinetCaptureProvenanceReviewReport.warnings)
      caseCount = $hinetCaptureProvenanceReviewReport.summary.caseCount
      pendingRepairOrExclusionCount = $hinetCaptureProvenanceReviewReport.summary.pendingRepairOrExclusionCount
      exclusionApprovedCount = $hinetCaptureProvenanceReviewReport.summary.exclusionApprovedCount
      readyAfterExclusionCount = $hinetCaptureProvenanceReviewReport.summary.readyAfterExclusionCount
      unresolvedCaptureIssueCount = $hinetCaptureProvenanceReviewReport.summary.unresolvedCaptureIssueCount
      failedGifCount = $hinetCaptureProvenanceReviewReport.summary.failedGifCount
      missingFrameCount = $hinetCaptureProvenanceReviewReport.summary.missingFrameCount
      blockingEvidenceCount = $hinetCaptureProvenanceReviewReport.summary.blockingEvidenceCount
    },
    [ordered]@{
      name = 'hinet_capture_exclusion_templates'
      command = 'tools\build_hinet_capture_exclusion_template_report.dart'
      status = 'pass'
      reportStatus = $hinetCaptureExclusionTemplatesReport.status
      reportErrors = $hinetCaptureExclusionTemplateErrors
      reportWarnings = @($hinetCaptureExclusionTemplatesReport.warnings)
      exclusionTemplateCount = $hinetCaptureExclusionTemplatesReport.summary.exclusionTemplateCount
      manualReviewRequiredCount = $hinetCaptureExclusionTemplatesReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $hinetCaptureExclusionTemplatesReport.summary.automaticClearanceCount
      ledgerMutationCount = $hinetCaptureExclusionTemplatesReport.summary.ledgerMutationCount
      affectedFileCount = $hinetCaptureExclusionTemplatesReport.summary.affectedFileCount
    },
    [ordered]@{
      name = 'hinet_capture_exclusion_review_packet'
      command = 'tools\build_hinet_capture_exclusion_review_packet.dart'
      status = 'pass'
      reportStatus = $hinetCaptureExclusionReviewPacketReport.status
      reportErrors = $hinetCaptureExclusionReviewPacketErrors
      reportWarnings = @($hinetCaptureExclusionReviewPacketReport.warnings)
      packetCount = $hinetCaptureExclusionReviewPacketReport.summary.packetCount
      manualReviewRequiredCount = $hinetCaptureExclusionReviewPacketReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $hinetCaptureExclusionReviewPacketReport.summary.automaticClearanceCount
      ledgerMutationCount = $hinetCaptureExclusionReviewPacketReport.summary.ledgerMutationCount
      readyAfterExclusionCount = $hinetCaptureExclusionReviewPacketReport.summary.readyAfterExclusionCount
      missingGifArchiveCopyCount = $hinetCaptureExclusionReviewPacketReport.summary.missingGifArchiveCopyCount
    },
    [ordered]@{
      name = 'hinet_capture_repair_probe'
      command = 'tools\validate_hinet_capture_repair_probe.ps1 -UseExistingProvenanceReview'
      status = 'pass'
      reportStatus = $hinetCaptureRepairProbeReport.status
      reportErrors = $hinetCaptureRepairProbeErrors
      reportWarnings = @($hinetCaptureRepairProbeReport.warnings)
      caseCount = $hinetCaptureRepairProbeReport.summary.caseCount
      affectedFileCount = $hinetCaptureRepairProbeReport.summary.affectedFileCount
      repairInputTemplateCount = $hinetCaptureRepairProbeReport.summary.repairInputTemplateCount
      manualReviewRequiredCount = $hinetCaptureRepairProbeReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $hinetCaptureRepairProbeReport.summary.automaticClearanceCount
      localCandidateCount = $hinetCaptureRepairProbeReport.summary.localCandidateCount
      validGifCandidateCount = $hinetCaptureRepairProbeReport.summary.validGifCandidateCount
      remoteHintCount = $hinetCaptureRepairProbeReport.summary.remoteHintCount
      invalidCandidateCount = $hinetCaptureRepairProbeReport.summary.invalidCandidateCount
      repairCandidateReadyCount = $hinetCaptureRepairProbeReport.summary.repairCandidateReadyCount
      unresolvedRepairCaseCount = $hinetCaptureRepairProbeReport.summary.unresolvedRepairCaseCount
    },
    [ordered]@{
      name = 'hinet_truth_quality_review_queue'
      command = 'tools\validate_hinet_truth_quality_review_queue.ps1 -UseExistingTruthReview'
      status = 'pass'
      reportStatus = $hinetTruthQualityReviewQueueReport.status
      reportErrors = $hinetTruthQualityReviewQueueErrors
      reportWarnings = @($hinetTruthQualityReviewQueueReport.warnings)
      caseCount = $hinetTruthQualityReviewQueueReport.summary.caseCount
      priorityExternalEvidenceReviewCount = $hinetTruthQualityReviewQueueReport.summary.priorityExternalEvidenceReviewCount
      captureRepairBlockedCount = $hinetTruthQualityReviewQueueReport.summary.captureRepairBlockedCount
      catalogFlagMismatchBlockedCount = $hinetTruthQualityReviewQueueReport.summary.catalogFlagMismatchBlockedCount
      externalEvidenceMissingCount = $hinetTruthQualityReviewQueueReport.summary.externalEvidenceMissingCount
      acceptedForConstrainedReferenceSplitCount = $hinetTruthQualityReviewQueueReport.summary.acceptedForConstrainedReferenceSplitCount
    },
    [ordered]@{
      name = 'hinet_external_evidence_targets'
      command = 'tools\validate_hinet_external_evidence_targets.ps1'
      status = 'pass'
      schemaVersion = $hinetExternalEvidenceTargets.schemaVersion
      targetCount = @($hinetExternalEvidenceTargets.targets).Count
      pendingExternalEvidenceCount = @(
        $hinetExternalEvidenceTargets.targets |
          Where-Object { $_.status -eq 'pending_external_evidence' }
      ).Count
      hinetAvailabilityCheckCount = @(
        $hinetExternalEvidenceTargets.sourceAvailabilityChecks
      ).Count
      hinetLoginRequiredCheckCount = @(
        $hinetExternalEvidenceTargets.sourceAvailabilityChecks |
          Where-Object { $_.accessStatus -eq 'login_required' }
      ).Count
      hinetAcceptedEventEvidenceCheckCount = @(
        $hinetExternalEvidenceTargets.sourceAvailabilityChecks |
          Where-Object { $_.catalogAcceptance -eq 'accepted_event_evidence' }
      ).Count
      jmaDailyFindingCount = @(
        $hinetExternalEvidenceTargets.targets |
          ForEach-Object { @($_.externalEvidenceFindings) } |
          Where-Object { $_.sourceType -eq 'jma_daily_hypocenter_list' }
      ).Count
      sufficientExternalEvidenceCount = @(
        $hinetExternalEvidenceTargets.targets |
          ForEach-Object { @($_.externalEvidenceFindings) } |
          Where-Object {
            $_.catalogAcceptance -ne `
              'not_sufficient_final_catalog_or_hinet_revised_source'
          }
      ).Count
      authenticatedExportRequestCount = @(
        $hinetAuthenticatedExportRequest.requests
      ).Count
      pendingAuthenticatedExportCount = @(
        $hinetAuthenticatedExportRequest.requests |
          Where-Object { $_.status -eq 'pending_authenticated_export' }
      ).Count
      authenticatedExportRowCount = @(
        $hinetAuthenticatedExportRows.rows
      ).Count
      pendingAuthenticatedExportRowCount = @(
        $hinetAuthenticatedExportRows.rows |
          Where-Object { $_.status -eq 'pending_export' }
      ).Count
      submittedAuthenticatedExportRowCount = @(
        $hinetAuthenticatedExportRows.rows |
          Where-Object { $_.status -eq 'submitted_for_review' }
      ).Count
      rejectedAuthenticatedExportRowCount = @(
        $hinetAuthenticatedExportRows.rows |
          Where-Object { $_.status -eq 'rejected' }
      ).Count
    },
    [ordered]@{
      name = 'hinet_authenticated_export_review'
      command = 'tools\validate_hinet_authenticated_export_review.ps1 -UseExistingExternalEvidenceTargets'
      status = 'pass'
      reportStatus = $hinetAuthenticatedExportReviewReport.status
      reportErrors = $hinetAuthenticatedExportReviewErrors
      reportWarnings = @($hinetAuthenticatedExportReviewReport.warnings)
      rowCount = $hinetAuthenticatedExportReviewReport.summary.rowCount
      pendingExportCount = $hinetAuthenticatedExportReviewReport.summary.pendingExportCount
      submittedForReviewCount = $hinetAuthenticatedExportReviewReport.summary.submittedForReviewCount
      rejectedCount = $hinetAuthenticatedExportReviewReport.summary.rejectedCount
      validSubmittedRowCount = $hinetAuthenticatedExportReviewReport.summary.validSubmittedRowCount
      decisionEvidenceReadyCount = $hinetAuthenticatedExportReviewReport.summary.decisionEvidenceReadyCount
      pendingDecisionCount = $hinetAuthenticatedExportReviewReport.summary.pendingDecisionCount
      acceptedDecisionCount = $hinetAuthenticatedExportReviewReport.summary.acceptedDecisionCount
      validationErrorCount = $hinetAuthenticatedExportReviewReport.summary.validationErrorCount
    },
    [ordered]@{
      name = 'hinet_authenticated_export_row_templates'
      command = 'tools\build_hinet_authenticated_export_row_templates.dart'
      status = 'pass'
      reportStatus = $hinetAuthenticatedExportRowTemplatesReport.status
      reportErrors = $hinetAuthenticatedExportRowTemplateErrors
      reportWarnings = @($hinetAuthenticatedExportRowTemplatesReport.warnings)
      rowTemplateCount = $hinetAuthenticatedExportRowTemplatesReport.summary.rowTemplateCount
      manualReviewRequiredCount = $hinetAuthenticatedExportRowTemplatesReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $hinetAuthenticatedExportRowTemplatesReport.summary.automaticClearanceCount
      credentialFieldCount = $hinetAuthenticatedExportRowTemplatesReport.summary.credentialFieldCount
    },
    [ordered]@{
      name = 'hinet_authenticated_export_review_packet'
      command = 'tools\build_hinet_authenticated_export_review_packet.dart'
      status = 'pass'
      reportStatus = $hinetAuthenticatedExportReviewPacketReport.status
      reportErrors = $hinetAuthenticatedExportReviewPacketErrors
      reportWarnings = @($hinetAuthenticatedExportReviewPacketReport.warnings)
      packetCount = $hinetAuthenticatedExportReviewPacketReport.summary.packetCount
      manualReviewRequiredCount = $hinetAuthenticatedExportReviewPacketReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $hinetAuthenticatedExportReviewPacketReport.summary.automaticClearanceCount
      ledgerMutationCount = $hinetAuthenticatedExportReviewPacketReport.summary.ledgerMutationCount
      submittedForReviewCount = $hinetAuthenticatedExportReviewPacketReport.summary.submittedForReviewCount
      decisionEvidenceReadyCount = $hinetAuthenticatedExportReviewPacketReport.summary.decisionEvidenceReadyCount
      credentialFieldCount = $hinetAuthenticatedExportReviewPacketReport.summary.credentialFieldCount
    },
    [ordered]@{
      name = 'source_estimation_external_input_queue'
      command = 'tools\validate_source_estimation_external_input_queue.ps1 -UseExistingDependencies'
      status = 'pass'
      reportStatus = $externalInputQueueReport.status
      reportErrors = $externalInputQueueErrors
      reportWarnings = @($externalInputQueueReport.warnings)
      inputItemCount = $externalInputQueueReport.summary.inputItemCount
      automaticClearanceCount = $externalInputQueueReport.summary.automaticClearanceCount
      inputTypeCounts = $externalInputQueueReport.summary.inputTypeCounts
    },
    [ordered]@{
      name = 'source_estimation_external_input_templates'
      command = 'tools\validate_source_estimation_external_input_templates.ps1 -UseExistingQueue'
      status = 'pass'
      reportStatus = $externalInputTemplatesReport.status
      reportErrors = $externalInputTemplatesErrors
      reportWarnings = @($externalInputTemplatesReport.warnings)
      templateCount = $externalInputTemplatesReport.summary.templateCount
      manualReviewRequiredCount = $externalInputTemplatesReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $externalInputTemplatesReport.summary.automaticClearanceCount
      ledgerMutationCount = $externalInputTemplatesReport.summary.ledgerMutationCount
      inputTypeCounts = $externalInputTemplatesReport.summary.inputTypeCounts
    },
    [ordered]@{
      name = 'source_estimation_external_input_delta'
      command = 'tools\validate_source_estimation_external_input_delta.ps1 -UseExistingQueue -UseExistingTemplates'
      status = 'pass'
      reportStatus = $externalInputDeltaReport.status
      reportErrors = $externalInputDeltaErrors
      reportWarnings = @($externalInputDeltaReport.warnings)
      deltaRowCount = $externalInputDeltaReport.summary.deltaRowCount
      matchedTemplateCount = $externalInputDeltaReport.summary.matchedTemplateCount
      missingTemplateCount = $externalInputDeltaReport.summary.missingTemplateCount
      staleTemplateCount = $externalInputDeltaReport.summary.staleTemplateCount
      priorityMismatchCount = $externalInputDeltaReport.summary.priorityMismatchCount
      nonManualReviewTemplateCount = $externalInputDeltaReport.summary.nonManualReviewTemplateCount
      automaticClearanceTemplateCount = $externalInputDeltaReport.summary.automaticClearanceTemplateCount
      coverageComplete = $externalInputDeltaReport.summary.coverageComplete
      safeTemplateSemantics = $externalInputDeltaReport.summary.safeTemplateSemantics
    },
    [ordered]@{
      name = 'source_estimation_external_input_attempts'
      command = 'tools\validate_source_estimation_external_input_attempts.ps1 -UseExistingQueue'
      status = 'pass'
      reportStatus = $externalInputAttemptsReport.status
      reportErrors = $externalInputAttemptsErrors
      reportWarnings = @($externalInputAttemptsReport.warnings)
      attemptCount = $externalInputAttemptsReport.summary.attemptCount
      automaticClearanceCount = $externalInputAttemptsReport.summary.automaticClearanceCount
      negativeAttemptOnlyCount = $externalInputAttemptsReport.summary.negativeAttemptOnlyCount
      inputTypeCounts = $externalInputAttemptsReport.summary.inputTypeCounts
    },
    [ordered]@{
      name = 'source_estimation_external_input_worklist'
      command = 'tools\validate_source_estimation_external_input_worklist.ps1 -UseExistingQueue -UseExistingTemplates -UseExistingAttempts -UseExistingRepairProbe -UseExistingAuthenticatedExportPacket -UseExistingJmaReferenceCapturePacket -UseExistingJmaFinalCatalogPacket -UseExistingFinalCatalogOrHinetRevisionPacket'
      status = 'pass'
      reportStatus = $externalInputWorklistReport.status
      reportErrors = $externalInputWorklistErrors
      reportWarnings = @($externalInputWorklistReport.warnings)
      openInputCount = $externalInputWorklistReport.summary.openInputCount
      attemptedInputCount = $externalInputWorklistReport.summary.attemptedInputCount
      unattemptedInputCount = $externalInputWorklistReport.summary.unattemptedInputCount
      manualReviewRequiredCount = $externalInputWorklistReport.summary.manualReviewRequiredCount
      automaticClearanceCount = $externalInputWorklistReport.summary.automaticClearanceCount
      operationArtifactCount = $externalInputWorklistReport.summary.operationArtifactCount
      highestPriority = $externalInputWorklistReport.summary.highestPriority
      nextInputType = $externalInputWorklistReport.summary.nextInputType
      nextCaseId = $externalInputWorklistReport.summary.nextCaseId
      nextHasAttempts = $externalInputWorklistReport.summary.nextHasAttempts
      inputTypeCounts = $externalInputWorklistReport.summary.inputTypeCounts
      attemptedInputTypeCounts = $externalInputWorklistReport.summary.attemptedInputTypeCounts
    },
    [ordered]@{
      name = 'source_trigger_threshold_review'
      command = 'tools\validate_source_trigger_threshold_review.ps1'
      status = 'pass'
      reportStatus = $sourceTriggerThresholdReviewReport.status
      reportErrors = $sourceTriggerThresholdReviewErrors
      reportWarnings = @($sourceTriggerThresholdReviewReport.warnings)
      captureProvenanceLocallyCompleteCount = $sourceTriggerThresholdReviewReport.summary.captureProvenanceLocallyCompleteCount
      historicalFetchCaptureCount = $sourceTriggerThresholdReviewReport.summary.historicalFetchCaptureCount
      sourceTriggerMissedEventCount = $sourceTriggerThresholdReviewReport.summary.sourceTriggerMissedEventCount
      quietWindowCount = $sourceTriggerThresholdReviewReport.summary.quietWindowCount
      quietWindowPassedCount = $sourceTriggerThresholdReviewReport.summary.quietWindowPassedCount
      quietWindowCandidateFrameCount = $sourceTriggerThresholdReviewReport.summary.quietWindowCandidateFrameCount
      quietWindowConfirmedFrameCount = $sourceTriggerThresholdReviewReport.summary.quietWindowConfirmedFrameCount
      quietWindowFalseEstimateFrameCount = $sourceTriggerThresholdReviewReport.summary.quietWindowFalseEstimateFrameCount
      thresholdReviewClearedCount = $sourceTriggerThresholdReviewReport.summary.thresholdReviewClearedCount
      noiseWindowValidationRequiredCount = $sourceTriggerThresholdReviewReport.summary.noiseWindowValidationRequiredCount
    },
    [ordered]@{
      name = 'plum_replay_capture_gap'
      command = 'tools\validate_plum_replay_capture_gap.ps1'
      status = 'pass'
      reportStatus = $plumReplayCaptureGapReport.status
      reportErrors = $plumReplayCaptureGapErrors
      reportWarnings = @($plumReplayCaptureGapReport.warnings)
      caseCount = $plumReplayCaptureGapReport.summary.caseCount
      completeCaseCount = $plumReplayCaptureGapReport.summary.completeCaseCount
      totalGapCaseCount = $plumReplayCaptureGapReport.summary.totalGapCaseCount
      gapCaseCount = $plumReplayCaptureGapReport.summary.gapCaseCount
      excludedGapCaseCount = $plumReplayCaptureGapReport.summary.excludedGapCaseCount
      failedGifCount = $plumReplayCaptureGapReport.summary.failedGifCount
      excludedFailedGifCount = $plumReplayCaptureGapReport.summary.excludedFailedGifCount
      totalFailedGifCount = $plumReplayCaptureGapReport.summary.totalFailedGifCount
    },
    [ordered]@{
      name = 'source_estimation_split_assignment_patch'
      command = 'tools\validate_source_estimation_split_assignment_patch.ps1'
      status = 'pass'
      reportStatus = $splitAssignmentPatchReport.status
      reportErrors = $splitAssignmentPatchErrors
      reportWarnings = @($splitAssignmentPatchReport.warnings)
      applyRequested = $splitAssignmentPatchReport.applyRequested
      readyToApplyCount = $splitAssignmentPatchReport.summary.readyToApplyCount
      alreadyAppliedCount = $splitAssignmentPatchReport.summary.alreadyAppliedCount
    },
    [ordered]@{
      name = 'source_candidate_region_suite'
      command = 'tools\validate_source_candidate_region_suite.ps1'
      status = 'pass'
      reportStatus = $candidateRegionSummary.status
    }
  )
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path "$summaryDirectory\summary.json"

flutter test test\source_estimation_validation_suite_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
