$ErrorActionPreference = 'Stop'

$manifestPath = 'docs\data\jma_reference_event_candidates.json'
$summaryDirectory = '.dart_tool\jma_reference_event_candidates'
$summaryPath = "$summaryDirectory\summary.json"

New-Item -ItemType Directory -Force -Path $summaryDirectory | Out-Null

$manifest = Get-Content -Raw -Encoding UTF8 -Path $manifestPath | ConvertFrom-Json
$events = @($manifest.events)
$errors = New-Object System.Collections.Generic.List[string]

if ($manifest.schemaVersion -ne 1) {
  $errors.Add('unexpected_schema_version')
}
if ($manifest.datasetId -ne 'jma_reference_event_candidates_v1') {
  $errors.Add('unexpected_dataset_id')
}
if ($events.Count -eq 0) {
  $errors.Add('missing_jma_reference_event_candidates')
}

$pendingCaptureCount = 0
$captureAssociatedCount = 0
$referenceOnlyCount = 0
$finalCatalogPendingCount = 0
$eqscFinalReportCount = 0
$equakeFinalReportCount = 0
$equakeNonFinalSnapshotCount = 0
$p2pquakeReferenceReportCount = 0

foreach ($event in $events) {
  $eventId = $event.eventId
  if ([string]::IsNullOrWhiteSpace($eventId)) {
    $errors.Add('candidate_missing_event_id')
    continue
  }

  if ($event.source -ne 'jma_source_and_intensity_information') {
    $errors.Add("${eventId}:unexpected_source")
  }
  if ($event.status -like '*pending_capture*') {
    $pendingCaptureCount += 1
  }
  if ($null -ne $event.captureDirectory) {
    $captureAssociatedCount += 1
  }
  if ($event.truthQuality -like '*pending_final_catalog*') {
    $finalCatalogPendingCount += 1
  }

  $labels = @($event.eventLabels)
  if ($labels -contains 'reference_only') {
    $referenceOnlyCount += 1
  } else {
    $errors.Add("${eventId}:missing_reference_only_label")
  }
  $hasCapture = $event.captureDirectory -ne $null
  if ($event.status -like '*pending_capture*' -and $hasCapture) {
    $errors.Add("${eventId}:pending_capture_has_capture_directory")
  }
  if ($event.status -notlike '*pending_capture*' -and -not $hasCapture) {
    $errors.Add("${eventId}:non_pending_capture_missing_capture_directory")
  }
  if ($event.truthQuality -notlike '*pending_final_catalog*') {
    $errors.Add("${eventId}:truth_quality_not_pending_final_catalog")
  }
  if (-not $hasCapture -and $labels -notcontains 'pending_capture') {
    $errors.Add("${eventId}:missing_pending_capture_label")
  }
  if ($hasCapture -and $labels -notcontains 'capture_associated') {
    $errors.Add("${eventId}:missing_capture_associated_label")
  }

  if ($null -ne $event.eqscReport) {
    if ($event.eqscReport.isFinal -eq $true) {
      $eqscFinalReportCount += 1
    } else {
      $errors.Add("${eventId}:eqsc_report_not_final")
    }
  }
  if ($null -ne $event.equakeReport) {
    if ($event.equakeReport.isFinal -eq $true) {
      $equakeFinalReportCount += 1
    } elseif ($event.equakeReport.isFinal -eq $false) {
      $equakeNonFinalSnapshotCount += 1
    } else {
      $errors.Add("${eventId}:equake_report_missing_final_flag")
    }
  }
  if ($null -ne $event.p2pquakeReport) {
    $p2pquakeReferenceReportCount += 1
  }
  if ($null -eq $event.eqscReport -and
      $null -eq $event.equakeReport -and
      $null -eq $event.p2pquakeReport) {
    $errors.Add("${eventId}:missing_final_reference_report")
  }
}

$status = if ($errors.Count -eq 0) { 'pass' } else { 'fail' }
$summary = [ordered]@{
  schemaVersion = 'jma_reference_event_candidates_validation_v1'
  createdAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  status = $status
  manifestPath = $manifestPath
  errors = @($errors)
  summary = [ordered]@{
    eventCount = $events.Count
    pendingCaptureCount = $pendingCaptureCount
    captureAssociatedCount = $captureAssociatedCount
    referenceOnlyCount = $referenceOnlyCount
    finalCatalogPendingCount = $finalCatalogPendingCount
    eqscFinalReportCount = $eqscFinalReportCount
    equakeFinalReportCount = $equakeFinalReportCount
    equakeNonFinalSnapshotCount = $equakeNonFinalSnapshotCount
    p2pquakeReferenceReportCount = $p2pquakeReferenceReportCount
  }
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $summaryPath

if ($status -ne 'pass') {
  Write-Error "jma_reference_event_candidates_validation_failed"
  exit 1
}

flutter test test\jma_reference_event_candidates_test.dart
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
