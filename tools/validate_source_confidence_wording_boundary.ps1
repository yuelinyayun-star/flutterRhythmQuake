$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_residual_decision_matrix.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_confidence_wording_boundary_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_confidence_wording_boundary_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
