$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_confidence_wording_boundary.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_wording_surface_audit_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_wording_surface_audit_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
