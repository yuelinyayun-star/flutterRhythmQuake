# Inject short-interval JMA EEW reports for 2026 Kumamoto M7.1.
# Same EventID / OriginTime within one run; EventID is unique per run so
# QuakeProvider report-dedup does not swallow a re-test.
#
# Usage:
#   .\tools\inject_eew_burst.ps1                      # ~3s for all 20+ reports
#   .\tools\inject_eew_burst.ps1 -DurationMs 3000
#   .\tools\inject_eew_burst.ps1 -IntervalMs 50        # fixed gap (overrides DurationMs)

param(
  [string]$JsonFile = 'tools/fixtures/kumamoto_20260728_eew_burst.json',
  [string]$BaseUrl = 'http://127.0.0.1:8765',
  [int]$IntervalMs = -1,
  [int]$DurationMs = 3000,
  [int]$FreshOriginSeconds = 0,
  [string]$EventId = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $JsonFile)) {
  $JsonFile = Join-Path $root $JsonFile
}
if (-not (Test-Path -LiteralPath $JsonFile)) {
  throw "JSON not found: $JsonFile"
}

$doc = Get-Content -LiteralPath $JsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
$count = @($doc.reports).Count
if ($count -lt 1) { throw 'No reports in fixture' }

if ($FreshOriginSeconds -le 0) {
  $FreshOriginSeconds = if ($doc.meta.freshOriginSeconds) { [int]$doc.meta.freshOriginSeconds } else { 6 }
}

# Default: spread all reports evenly across DurationMs (3s for 20+ reports).
if ($IntervalMs -lt 0) {
  if ($count -le 1) {
    $IntervalMs = 0
  } else {
    $IntervalMs = [int][Math]::Floor($DurationMs / ($count - 1))
  }
}

# Shared JST wall clock for OriginTime (UTC+9), matching production JMA path.
$originStamp = (Get-Date).ToUniversalTime().AddHours(9).AddSeconds(-1 * $FreshOriginSeconds)
$originText = $originStamp.ToString('yyyy-MM-dd HH:mm:ss')

# Fresh EventID each run — otherwise reportNum <= stored max is dropped silently.
if ([string]::IsNullOrWhiteSpace($EventId)) {
  $EventId = $originStamp.ToString('yyyyMMddHHmmss')
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "Kumamoto EEW burst: $count reports over ~${DurationMs}ms (gap=${IntervalMs}ms)"
Write-Host "EventID=$EventId OriginTime(JST)=$originText"

$i = 0
foreach ($report in $doc.reports) {
  $i++
  $map = @{}
  foreach ($p in $report.PSObject.Properties) {
    $map[$p.Name] = $p.Value
  }
  $map['EventID'] = $EventId
  $map['OriginTime'] = $originText
  $announced = $originStamp.AddSeconds([Math]::Max(1, [int]$map['Serial']))
  $map['AnnouncedTime'] = $announced.ToString('yyyy-MM-dd HH:mm:ss')
  $body = ($map | ConvertTo-Json -Compress -Depth 8)

  # Do NOT use fresh=1 — that would rewrite OriginTime every Serial.
  $resp = Invoke-RestMethod -Method Post -Uri "$BaseUrl/inject/eew" `
    -ContentType 'application/json; charset=utf-8' -Body $body
  Write-Host ("[{0}/{1}] Serial={2} M={3} depth={4} I={5} -> injected={6}" -f `
    $i, $count, $map['Serial'], $map['Magunitude'], $map['Depth'], $map['MaxIntensity'], $resp.injected)

  if ($IntervalMs -gt 0 -and $i -lt $count) {
    Start-Sleep -Milliseconds $IntervalMs
  }
}

$sw.Stop()
$rate = $count * 1000.0 / [Math]::Max(1, $sw.ElapsedMilliseconds)
Write-Host ("DONE in {0}ms ({1:N1} reports/s) EventID={2}" -f $sw.ElapsedMilliseconds, $rate, $EventId)
