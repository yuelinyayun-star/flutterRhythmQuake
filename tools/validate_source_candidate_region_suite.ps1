$ErrorActionPreference = 'Stop'

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_candidate_promotion_matrix.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_source_candidate_region_timeline.ps1
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

flutter test test\source_candidate_validation_scripts_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$summaryDirectory = '.dart_tool\source_candidate_region_suite'
New-Item -ItemType Directory -Force -Path $summaryDirectory | Out-Null

$promotionMatrixReport = '.dart_tool\source_candidate_promotion_report\matrix.json'
$candidateRegionTimelineReport = '.dart_tool\source_candidate_region_timeline_report\report.json'
$promotionMatrix = Get-Content -Raw -Path $promotionMatrixReport | ConvertFrom-Json
$candidateRegionTimeline = Get-Content -Raw -Path $candidateRegionTimelineReport | ConvertFrom-Json
$promotionValidationStatus = $promotionMatrix.validation.status
$promotionValidationViolations = @($promotionMatrix.validation.violations)
$timelineValidationStatus = $candidateRegionTimeline.validation.status
$timelineValidationViolations = @($candidateRegionTimeline.validation.violations)

if ($promotionValidationStatus -ne 'pass' -or $promotionValidationViolations.Count -ne 0) {
  Write-Error "promotion_matrix_report_validation_failed"
  exit 1
}

if ($timelineValidationStatus -ne 'pass' -or $timelineValidationViolations.Count -ne 0) {
  Write-Error "candidate_region_timeline_report_validation_failed"
  exit 1
}

$summary = [ordered]@{
  schemaVersion = 'source_candidate_region_suite_validation_v1'
  createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  status = 'pass'
  promotionMatrixReport = $promotionMatrixReport
  candidateRegionTimelineReport = $candidateRegionTimelineReport
  validations = @(
    [ordered]@{
      name = 'residual_promotion_matrix'
      command = 'tools\validate_source_candidate_promotion_matrix.ps1'
      status = 'pass'
      reportValidationStatus = $promotionValidationStatus
      reportValidationViolations = $promotionValidationViolations
    },
    [ordered]@{
      name = 'candidate_region_timeline'
      command = 'tools\validate_source_candidate_region_timeline.ps1'
      status = 'pass'
      reportValidationStatus = $timelineValidationStatus
      reportValidationViolations = $timelineValidationViolations
    },
    [ordered]@{
      name = 'validation_script_structure'
      command = 'flutter test test\source_candidate_validation_scripts_test.dart'
      status = 'pass'
    }
  )
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -Path "$summaryDirectory\summary.json"

flutter test test\source_candidate_region_suite_summary_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
