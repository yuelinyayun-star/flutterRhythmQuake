$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_metric_readiness_triage.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_truth_quality_review_queue.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_hinet_truth_quality_triage_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_hinet_truth_quality_triage_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
