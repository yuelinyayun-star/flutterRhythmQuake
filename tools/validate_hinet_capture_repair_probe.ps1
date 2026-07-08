param(
  [switch]$UseExistingProvenanceReview
)

$ErrorActionPreference = 'Stop'

if (-not $UseExistingProvenanceReview) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_hinet_capture_provenance_review.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

dart run tools\build_hinet_capture_repair_probe_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test `
  test\hinet_capture_repair_probe_report_test.dart `
  test\hinet_capture_repair_candidate_import_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
