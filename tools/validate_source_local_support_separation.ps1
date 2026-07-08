$ErrorActionPreference = 'Stop'

flutter test test\fukushima_offshore_reference_replay_test.dart `
  test\iwate_offshore_m32_reference_replay_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_candidate_rejection_residual_report.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_local_support_separation_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_local_support_separation_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
