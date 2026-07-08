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

dart run tools\build_hinet_truth_quality_review_queue_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_truth_quality_review_queue_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
