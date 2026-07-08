param(
  [switch]$UseExistingExternalEvidenceTargets
)

$ErrorActionPreference = 'Stop'

if (-not $UseExistingExternalEvidenceTargets) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_hinet_external_evidence_targets.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

dart run tools\build_hinet_authenticated_export_review_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_hinet_authenticated_export_row_templates.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_hinet_authenticated_export_review_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_authenticated_export_review_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_authenticated_export_row_import_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_authenticated_export_row_template_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\hinet_authenticated_export_review_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
