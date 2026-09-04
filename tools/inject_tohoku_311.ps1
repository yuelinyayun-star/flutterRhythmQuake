# 平成23年(2011)東北地方太平洋沖地震 — EEW / 情報 / 津波 注入テスト
#
# 资料来源（夹具 meta.refs）:
#   EEW 15報: JMA pub_hist 20110311144640
#   情報 M 更新: 7.9 → 8.4 → 8.8 → 9.0
#   津波: 14:49 第1報 / 15:14 第2報 / 16:08 峰值
#
# Usage:
#   .\tools\inject_tohoku_311.ps1                 # 全流程（压缩时间轴）
#   .\tools\inject_tohoku_311.ps1 -Phase eew
#   .\tools\inject_tohoku_311.ps1 -Phase info
#   .\tools\inject_tohoku_311.ps1 -Phase tsunami
#   .\tools\inject_tohoku_311.ps1 -EewDurationMs 4000 -TsunamiGapMs 2500

param(
  [ValidateSet('all', 'eew', 'info', 'tsunami')]
  [string]$Phase = 'all',
  [string]$BaseUrl = 'http://127.0.0.1:8765',
  [int]$EewDurationMs = 4000,
  [int]$InfoGapMs = 800,
  [int]$TsunamiGapMs = 2500,
  [int]$FreshOriginSeconds = 8,
  [string]$EventId = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$eewPath = Join-Path $root 'tools/fixtures/tohoku_20110311_eew_burst.json'
$infoPath = Join-Path $root 'tools/fixtures/tohoku_20110311_info.json'
$tsunamiPath = Join-Path $root 'tools/fixtures/tohoku_20110311_tsunami.json'

function Format-JstWall([DateTime]$stamp) {
  return $stamp.ToString('yyyy-MM-dd HH:mm:ss')
}

function Format-P2PTime([DateTime]$stamp) {
  return $stamp.ToString('yyyy/MM/dd HH:mm:ss')
}

function Post-Inject([string]$Body) {
  return Invoke-RestMethod -Method Post -Uri "$BaseUrl/inject/eew" `
    -ContentType 'application/json; charset=utf-8' -Body $Body
}

# Shared JST wall clock for one scenario run.
$originStamp = (Get-Date).ToUniversalTime().AddHours(9).AddSeconds(-1 * $FreshOriginSeconds)
if ([string]::IsNullOrWhiteSpace($EventId)) {
  $EventId = $originStamp.ToString('yyyyMMddHHmmss')
}
$originText = Format-JstWall $originStamp
$eqTimeP2P = Format-P2PTime $originStamp

Write-Host "=== Tohoku 311 inject ==="
Write-Host "EventID=$EventId Origin(JST)=$originText Phase=$Phase"
Write-Host ""

# ---- EEW ----
if ($Phase -eq 'all' -or $Phase -eq 'eew') {
  $doc = Get-Content -LiteralPath $eewPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $count = @($doc.reports).Count
  $gap = if ($count -le 1) { 0 } else { [int][Math]::Floor($EewDurationMs / ($count - 1)) }
  Write-Host "--- EEW $count reports over ~${EewDurationMs}ms (gap=${gap}ms) ---"
  $i = 0
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  foreach ($report in $doc.reports) {
    $i++
    $map = @{}
    foreach ($p in $report.PSObject.Properties) { $map[$p.Name] = $p.Value }
    $map['EventID'] = $EventId
    $map['OriginTime'] = $originText
    $announced = $originStamp.AddSeconds([Math]::Max(1, [int]$map['Serial']))
    $map['AnnouncedTime'] = Format-JstWall $announced
    $body = ($map | ConvertTo-Json -Compress -Depth 8)
    $resp = Post-Inject $body
    Write-Host ("[{0}/{1}] Serial={2} M={3} I={4} warn={5} -> {6}" -f `
      $i, $count, $map['Serial'], $map['Magunitude'], $map['MaxIntensity'], $map['isWarn'], $resp.injected)
    if ($gap -gt 0 -and $i -lt $count) { Start-Sleep -Milliseconds $gap }
  }
  $sw.Stop()
  Write-Host ("EEW DONE in {0}ms" -f $sw.ElapsedMilliseconds)
  Write-Host ""
}

# ---- Info (P2P 551) ----
if ($Phase -eq 'all' -or $Phase -eq 'info') {
  $doc = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $count = @($doc.reports).Count
  Write-Host "--- Info $count reports (ScalePrompt → Destination → M updates) ---"
  $i = 0
  foreach ($report in $doc.reports) {
    $i++
    # Deep-ish clone via JSON roundtrip so we can mutate times.
    $map = $report | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    $issueOffsetSec = switch ($i) {
      1 { 130 }   # ScalePrompt ~2min
      2 { 160 }   # Destination / tsunami basis
      3 { 740 }   # M8.4 (~16:00 relative compressed)
      4 { 1640 }  # Mw8.8
      default { 2000 + $i * 30 }
    }
    $issueStamp = $originStamp.AddSeconds($issueOffsetSec)
    $map.issue.time = Format-P2PTime $issueStamp
    $map.earthquake.time = $eqTimeP2P
    # Keep one shared eventId via earthquake.time for Destination+ updates.
    $body = ($map | ConvertTo-Json -Compress -Depth 12)
    $resp = Post-Inject $body
    $mag = $map.earthquake.hypocenter.magnitude
    $itype = $map.issue.type
    Write-Host ("[{0}/{1}] {2} M={3} maxScale={4} -> {5}" -f `
      $i, $count, $itype, $mag, $map.earthquake.maxScale, $resp.injected)
    if ($InfoGapMs -gt 0 -and $i -lt $count) { Start-Sleep -Milliseconds $InfoGapMs }
  }
  Write-Host "Info DONE"
  Write-Host ""
}

# ---- Tsunami (P2P 552) ----
if ($Phase -eq 'all' -or $Phase -eq 'tsunami') {
  $doc = Get-Content -LiteralPath $tsunamiPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $count = @($doc.reports).Count
  Write-Host "--- Tsunami $count reports (r1 → r2 → peak) ---"
  $i = 0
  foreach ($report in $doc.reports) {
    $i++
    $map = $report | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $issueOffsetSec = switch ($i) {
      1 { 180 }   # +3min (14:49)
      2 { 1680 }  # compressed stand-in for +28min (15:14)
      default { 4920 } # stand-in for 16:08
    }
    $issueStamp = $originStamp.AddSeconds($issueOffsetSec)
    $map.issue.time = Format-P2PTime $issueStamp
    $map.id = "tohoku311_${EventId}_t$i"
    $areaCount = @($map.areas).Count
    $body = ($map | ConvertTo-Json -Compress -Depth 12)
    $resp = Post-Inject $body
    Write-Host ("[{0}/{1}] id={2} areas={3} -> {4}" -f `
      $i, $count, $map.id, $areaCount, $resp.injected)
    if ($TsunamiGapMs -gt 0 -and $i -lt $count) { Start-Sleep -Milliseconds $TsunamiGapMs }
  }
  Write-Host "Tsunami DONE"
  Write-Host ""
}

Write-Host "=== ALL DONE EventID=$EventId ==="
