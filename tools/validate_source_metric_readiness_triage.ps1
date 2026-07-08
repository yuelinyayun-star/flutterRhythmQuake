$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_estimation_split_blocker_queue.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_metric_readiness_triage_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_metric_readiness_triage_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
