$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_metric_readiness_triage.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_jma_catalog_availability.ps1 -UseExistingReadiness
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

dart run tools\build_source_jma_catalog_link_triage_packet.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_jma_catalog_link_triage_packet_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
