param(
  [int]$Port = 8791,
  [string]$HostName = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scriptPath = Join-Path $repoRoot "tools\fdsn_seedlink_relay.py"

$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
  $python = Get-Command py -ErrorAction SilentlyContinue
}

if ($null -eq $python) {
  Write-Error "Python is not available. Install Python, then run: pip install obspy websockets numpy"
  exit 1
}

$env:FDSN_RELAY_PORT = "$Port"
$env:FDSN_RELAY_HOST = "$HostName"

Write-Host "Starting FDSN SeedLink relay at ws://$HostName`:$Port/fdsn-motion"
Write-Host "If imports fail, install dependencies: pip install obspy websockets numpy"
& $python.Source $scriptPath
