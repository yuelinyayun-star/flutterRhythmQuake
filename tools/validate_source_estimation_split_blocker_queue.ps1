param(
  [switch]$UseExistingReadiness
)

$ErrorActionPreference = 'Stop'

if (-not $UseExistingReadiness) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_source_estimation_split_assignment_readiness.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

dart run tools\build_source_estimation_split_blocker_queue_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_final_catalog_or_hinet_revision_review_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test `
  test\source_estimation_split_blocker_queue_report_test.dart `
  test\final_catalog_or_hinet_revision_review_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
