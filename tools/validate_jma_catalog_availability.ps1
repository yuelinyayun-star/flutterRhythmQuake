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

dart run tools\build_jma_catalog_availability_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_jma_final_catalog_review_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\jma_catalog_availability_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\jma_final_catalog_review_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
