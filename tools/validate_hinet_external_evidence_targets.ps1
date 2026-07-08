$ErrorActionPreference = 'Stop'

flutter test test\hinet_external_evidence_targets_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
