param(
  [switch]$UseExistingQueue,
  [switch]$UseExistingTemplates
)

$ErrorActionPreference = 'Stop'

if (-not $UseExistingQueue) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_source_estimation_external_input_queue.ps1
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not $UseExistingTemplates) {
  powershell -NoProfile -ExecutionPolicy Bypass -File `
    tools\validate_source_estimation_external_input_templates.ps1 `
    -UseExistingQueue
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

dart run tools\build_source_estimation_external_input_delta_report.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_estimation_external_input_delta_report_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
