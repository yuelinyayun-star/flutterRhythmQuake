param(
  [ValidateSet('A', 'B')]
  [string]$Event = 'A'
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$now = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8))
$isA = $Event -eq 'A'
# Synthetic, local-only information bulletins; no observed data is altered.
$payload = [ordered]@{
  source = 'cenc'
  eventId = "SIM-CAMERA-$Event-$($now.ToString('yyyyMMddHHmmss'))"
  shockTime = $now.AddSeconds(-30).ToString('yyyy-MM-dd HH:mm:ss')
  createTime = $now.ToString('yyyy-MM-dd HH:mm:ss')
  placeName = "SIMULATION $Event - NOT A REAL EARTHQUAKE"
  latitude = $(if ($isA) { 30.6 } else { 30.85 })
  longitude = $(if ($isA) { 103.9 } else { 104.15 })
  magnitude = $(if ($isA) { 5.0 } else { 5.2 })
  depth = 10
  maxIntensity = 5
  reviewType = 'reviewed'
}
$json = $payload | ConvertTo-Json -Compress
Set-Clipboard -Value $json
Write-Output $json
