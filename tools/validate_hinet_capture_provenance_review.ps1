param(
  [switch]$UseExistingTruthReview
)

$ErrorActionPreference = 'Stop'

if (-not $UseExistingTruthReview) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_hinet_truth_quality_review.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

dart run tools\build_hinet_capture_provenance_review_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_hinet_capture_exclusion_template_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_hinet_capture_exclusion_review_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_capture_provenance_review_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_capture_exclusion_template_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_capture_exclusion_review_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_capture_exclusion_decision_import_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
