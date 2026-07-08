$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_hinet_priority_evidence_templates.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_hinet_no_row_found_review_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_hinet_no_row_found_review_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_hinet_no_row_found_finding_import_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
