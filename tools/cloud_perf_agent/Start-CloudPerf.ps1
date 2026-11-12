param(
  [int]$TargetProcessId = 0,
  [ValidateRange(1024,65535)][int]$Port = 18769,
  [ValidateRange(1024,65535)][int]$AppPort = 8765,
  [string]$SshTarget = '',
  [ValidateRange(1024,65535)][int]$RemotePort = 18769,
  [ValidateRange(30,86400)][int]$DurationSeconds = 3600
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if (!$TargetProcessId) {
  $candidates = @(Get-Process -Name flutterrhythmquake -ErrorAction SilentlyContinue)
  if ($candidates.Count -ne 1) {
    throw 'Start one RhythmQuake instance first, or specify -TargetProcessId.'
  }
  $TargetProcessId = $candidates[0].Id
}
$exe = Join-Path $PSScriptRoot 'rq_perf_agent.exe'
if (!(Test-Path -LiteralPath $exe)) { throw 'rq_perf_agent.exe is missing.' }
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$outputDir = Join-Path $PSScriptRoot ('captures\' + $stamp)
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$arguments = @('--pid', $TargetProcessId, '--port', $Port, '--app-port', $AppPort,
  '--duration-seconds', $DurationSeconds, '--output', ('"' + $outputDir + '"'))
$agent = Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput (Join-Path $outputDir 'agent.stdout.log') `
  -RedirectStandardError (Join-Path $outputDir 'agent.stderr.log')
$connectionPath = Join-Path $outputDir 'connection.json'
try {
  for ($attempt=0; $attempt -lt 50; $attempt++) {
    if ((Test-Path -LiteralPath $connectionPath) -or $agent.HasExited) { break }
    Start-Sleep -Milliseconds 100
  }
  if (!(Test-Path -LiteralPath $connectionPath)) {
    throw ('Agent startup failed. Inspect ' + (Join-Path $outputDir 'agent.stderr.log'))
  }
  Write-Host ('Capture folder: ' + $outputDir)
  Write-Host 'Keep this window open during the test. Ctrl+C stops the tunnel.'
  if ($SshTarget) {
    # Only temporary connection metadata goes to the relay. No APP source,
    # credentials, source telegrams or process dumps are uploaded.
    $remoteFile = '.rq-perf-connection-' + $RemotePort + '.json'
    $remoteScript = 'umask 077; cat > "FILE"; trap ''rm -f "FILE"'' EXIT; while :; do sleep 30; done'
    $remoteScript = $remoteScript.Replace('FILE', $remoteFile)
    Write-Host ('Remote loopback port: ' + $RemotePort)
    [IO.File]::ReadAllText($connectionPath,[Text.Encoding]::UTF8) | & ssh.exe -T `
      -o ExitOnForwardFailure=yes -o ServerAliveInterval=20 -o ServerAliveCountMax=3 `
      -R ("127.0.0.1:${RemotePort}:127.0.0.1:${Port}") $SshTarget $remoteScript
    if ($LASTEXITCODE -ne 0) { throw 'SSH tunnel ended with an error.' }
  } else {
    Write-Host 'Local capture is running. Use -SshTarget user@relay to make a reverse SSH connection.'
    Read-Host 'Press Enter to stop' | Out-Null
  }
} finally {
  if ((Test-Path -LiteralPath $connectionPath) -and !$agent.HasExited) {
    try {
      $connection = [IO.File]::ReadAllText($connectionPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
      Invoke-RestMethod -Method Post -Uri ($connection.url + '/shutdown') `
        -Headers @{Authorization=('Bearer ' + $connection.token)} -TimeoutSec 3 | Out-Null
    } catch { Write-Warning 'Agent will stop automatically at its configured time limit.' }
  }
}
