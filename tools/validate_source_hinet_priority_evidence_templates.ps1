$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_hinet_truth_quality_triage.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_authenticated_export_review.ps1 -UseExistingExternalEvidenceTargets
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_hinet_priority_evidence_template_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_hinet_priority_evidence_template_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
