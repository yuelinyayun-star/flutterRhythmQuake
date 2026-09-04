# Local inject API for EEW / NIED camera testing
#
# App listens on http://127.0.0.1:8765 when enabled in Debug → 调试工具 → Local Inject API,
# or with: flutter run -d windows --dart-define=LOCAL_INJECT=true
#
# From another machine:
#   ssh -L 8765:127.0.0.1:8765 user@windows-host

param(
  [ValidateSet('health', 'eew', 'gif', 'knet', 'replay', 'scenario', 'stop', 'help')]
  [string]$Action = 'help',
  [string]$Path = '',
  [string]$JsonFile = 'tools/fixtures/sample_jma_eew.json',
  [string]$BaseUrl = 'http://127.0.0.1:8765',
  [string]$StartJst = '2026-05-30 23:34:00',
  [int]$StepSeconds = 1,
  [int]$DelayMs = 800,
  [int]$FreshOriginSeconds = 15
)

$ErrorActionPreference = 'Stop'

function Invoke-JsonPost([string]$Url, [string]$Body) {
  Invoke-RestMethod -Method Post -Uri $Url -ContentType 'application/json; charset=utf-8' -Body $Body
}

switch ($Action) {
  'help' {
    Invoke-RestMethod -Method Get -Uri "$BaseUrl/"
  }
  'health' {
    Invoke-RestMethod -Method Get -Uri "$BaseUrl/health"
  }
  'eew' {
    if (-not (Test-Path -LiteralPath $JsonFile)) {
      throw "JSON file not found: $JsonFile"
    }
    $raw = Get-Content -LiteralPath $JsonFile -Raw -Encoding UTF8
    Invoke-RestMethod -Method Post -Uri "$BaseUrl/inject/eew?fresh=1&freshOriginSeconds=$FreshOriginSeconds" -ContentType 'application/json; charset=utf-8' -Body $raw
  }
  'gif' {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Pass -Path to a NIED GIF file or directory' }
    $body = @{ path = (Resolve-Path -LiteralPath $Path).Path } | ConvertTo-Json -Compress
    Invoke-JsonPost "$BaseUrl/inject/nied-gif" $body
  }
  'stop' {
    Invoke-RestMethod -Method Post -Uri "$BaseUrl/inject/stop"
  }
  'knet' {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Pass -Path to a K-NET zip' }
    $body = @{ path = (Resolve-Path -LiteralPath $Path).Path } | ConvertTo-Json -Compress
    Invoke-JsonPost "$BaseUrl/inject/knet" $body
  }
  'replay' {
    $body = @{
      enabled = $true
      startJst = $StartJst
      stepSeconds = $StepSeconds
    } | ConvertTo-Json -Compress
    Invoke-JsonPost "$BaseUrl/nied/replay" $body
  }
  'scenario' {
    if (-not (Test-Path -LiteralPath $JsonFile)) {
      throw "JSON file not found: $JsonFile"
    }
    $eew = Get-Content -LiteralPath $JsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $payload = @{
      eew = $eew
      delayMs = $DelayMs
      freshOriginSeconds = $FreshOriginSeconds
    }
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
      $payload.niedGifPath = (Resolve-Path -LiteralPath $Path).Path
    }
    $body = $payload | ConvertTo-Json -Depth 8 -Compress
    Invoke-JsonPost "$BaseUrl/inject/scenario" $body
  }
}
