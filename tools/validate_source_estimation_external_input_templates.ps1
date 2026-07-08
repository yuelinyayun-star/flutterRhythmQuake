param(
  [switch]$UseExistingQueue
)

$ErrorActionPreference = 'Stop'

if (-not $UseExistingQueue) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_source_estimation_external_input_queue.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

dart run tools\build_source_estimation_external_input_template_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_estimation_external_input_template_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
