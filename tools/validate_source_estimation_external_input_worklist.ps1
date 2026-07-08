param(
  [switch]$UseExistingQueue,
  [switch]$UseExistingTemplates,
  [switch]$UseExistingAttempts,
  [switch]$UseExistingRepairProbe,
  [switch]$UseExistingAuthenticatedExportPacket,
  [switch]$UseExistingJmaReferenceCapturePacket,
  [switch]$UseExistingJmaFinalCatalogPacket,
  [switch]$UseExistingFinalCatalogOrHinetRevisionPacket
)

$ErrorActionPreference = 'Stop'

if (-not $UseExistingQueue) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_source_estimation_external_input_queue.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $UseExistingTemplates) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_source_estimation_external_input_templates.ps1 `
    -UseExistingQueue
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $UseExistingAttempts) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_source_estimation_external_input_attempts.ps1 `
    -UseExistingQueue
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $UseExistingRepairProbe) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_hinet_capture_repair_probe.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $UseExistingAuthenticatedExportPacket) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_hinet_authenticated_export_review.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $UseExistingJmaReferenceCapturePacket) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_jma_reference_capture_association.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $UseExistingJmaFinalCatalogPacket) {
  dart run tools\build_jma_final_catalog_review_packet.dart
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $UseExistingFinalCatalogOrHinetRevisionPacket) {
  dart run tools\build_final_catalog_or_hinet_revision_review_packet.dart
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

dart run tools\build_source_estimation_external_input_worklist_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_estimation_external_input_worklist_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
