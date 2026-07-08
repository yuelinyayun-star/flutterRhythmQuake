$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_residual_delayed_recovery.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_residual_decision_matrix_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_residual_decision_matrix_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
