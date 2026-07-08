$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_hinet_reviewer_decision_staging.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_hinet_reviewer_decision_template_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test `
  test\source_hinet_reviewer_decision_template_packet_test.dart `
  test\source_hinet_reviewer_decision_import_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
