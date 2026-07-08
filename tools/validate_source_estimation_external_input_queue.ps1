param(
  [switch]$UseExistingDependencies,
  [switch]$UseExistingBlockerQueue,
  [switch]$UseExistingJmaCapture,
  [switch]$UseExistingHinetRepair,
  [switch]$UseExistingHinetExport
)

$ErrorActionPreference = 'Stop'

if (-not ($UseExistingDependencies -or $UseExistingBlockerQueue)) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_source_estimation_split_blocker_queue.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not ($UseExistingDependencies -or $UseExistingJmaCapture)) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_jma_reference_capture_association.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not ($UseExistingDependencies -or $UseExistingHinetRepair)) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_hinet_capture_repair_probe.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not ($UseExistingDependencies -or $UseExistingHinetExport)) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_hinet_authenticated_export_review.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

dart run tools\build_source_estimation_external_input_queue_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_estimation_external_input_queue_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
