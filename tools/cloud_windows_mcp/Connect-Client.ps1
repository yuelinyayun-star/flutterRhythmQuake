$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$clientRoot = Join-Path $env:LOCALAPPDATA 'RhythmQuakeMCPClient'
$stateFile = Join-Path $clientRoot 'reader-process.json'
if (Test-Path -LiteralPath $stateFile) {
    $previous = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $existing = Get-Process -Id $previous.pid -ErrorAction SilentlyContinue
    if ($existing -and $existing.Path -eq $previous.path -and $existing.StartTime.ToUniversalTime().Ticks.ToString() -eq $previous.startedUtcTicks) { Write-Output ('Client tunnel already running: ' + $existing.Id); return }
}
if (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18771 -State Listen -ErrorAction SilentlyContinue) { throw 'Local port 18771 is occupied by another process.' }
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
$arguments = @('-N', '-T', '-i', ('"' + (Join-Path $clientRoot 'reader_ed25519') + '"'), '-o', ('UserKnownHostsFile="' + (Join-Path $clientRoot 'known_hosts') + '"'), '-o', 'StrictHostKeyChecking=yes', '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=3', '-o', 'ConnectTimeout=10', '-L', '127.0.0.1:18771:127.0.0.1:18769', 'rq-mcp-reader@64.90.20.78')
$process = Start-Process -FilePath $ssh -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $clientRoot 'reader.log')
$state = @{ pid = $process.Id; startedUtcTicks = $process.StartTime.ToUniversalTime().Ticks.ToString(); path = $process.Path }
[IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Start-Sleep -Seconds 3
if ($process.HasExited) { throw ('Client tunnel exited. See ' + (Join-Path $clientRoot 'reader.log')) }
Write-Output ('Client tunnel started: ' + $process.Id + '. Refresh rq_cloud_windows MCP after the cloud computer connects.')
