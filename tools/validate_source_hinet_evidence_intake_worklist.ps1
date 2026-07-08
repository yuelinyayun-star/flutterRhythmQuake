$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_hinet_reviewer_decision_templates.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_hinet_evidence_intake_worklist.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_hinet_evidence_intake_worklist_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
