$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_local_support_control.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_residual_delayed_recovery_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_residual_delayed_recovery_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
