$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
$env:ANONYMIZED_TELEMETRY = 'false'
$root = $PSScriptRoot
$settings = Get-Content -LiteralPath (Join-Path $root 'private\connection.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$env:WINDOWS_MCP_AUTH_KEY = $settings.authKey
$python = Join-Path $root 'runtime\python.exe'
$ssh = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
$logs = Join-Path $root 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$mcp = $null
$tunnel = $null

function Write-Status([string]$text) {
    $path = Join-Path $logs 'supervisor.log'
    if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 1MB) {
        Move-Item -LiteralPath $path -Destination ($path + '.previous') -Force
    }
    [IO.File]::AppendAllText($path, ([DateTime]::UtcNow.ToString('o') + ' ' + $text + "`r`n"), [Text.UTF8Encoding]::new($false))
}

function Process-Identity($process) {
    if ($null -eq $process -or $process.HasExited) { return $null }
    try { return @{ pid = $process.Id; startedUtcTicks = $process.StartTime.ToUniversalTime().Ticks.ToString(); path = $process.Path } } catch { return $null }
}

function Save-State {
    $state = @{ supervisor = (Process-Identity (Get-Process -Id $PID)); mcp = (Process-Identity $mcp); tunnel = (Process-Identity $tunnel) }
    [IO.File]::WriteAllText((Join-Path $root 'private\processes.json'), ($state | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
}

function Rotate-Log([string]$name) {
    $path = Join-Path $logs $name
    if (Test-Path -LiteralPath $path) { Move-Item -LiteralPath $path -Destination ($path + '.previous') -Force }
}

try {
    Write-Status 'Starting authenticated Windows MCP and outbound SSH tunnel.'
    while ($true) {
        if ($null -eq $mcp -or $mcp.HasExited) {
            if ($null -ne $mcp) { Write-Status ('MCP exited: ' + $mcp.ExitCode) }
            Rotate-Log 'mcp.out.log'
            Rotate-Log 'mcp.err.log'
            $mcp = Start-Process -FilePath $python -ArgumentList @('-m', 'windows_mcp', 'serve', '--transport', 'streamable-http', '--host', '127.0.0.1', '--port', '18770', '--stateless-http') -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'mcp.out.log') -RedirectStandardError (Join-Path $logs 'mcp.err.log')
            Write-Status ('MCP pid ' + $mcp.Id)
        }
        if ($null -eq $tunnel -or $tunnel.HasExited) {
            if ($null -ne $tunnel) { Write-Status ('SSH tunnel exited: ' + $tunnel.ExitCode) }
            Rotate-Log 'ssh.out.log'
            Rotate-Log 'ssh.err.log'
            $arguments = @('-N', '-T', '-v', '-i', ('"' + (Join-Path $root 'private\cloud_ed25519') + '"'), '-o', ('UserKnownHostsFile="' + (Join-Path $root 'private\known_hosts') + '"'), '-o', 'StrictHostKeyChecking=yes', '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=20', '-o', 'ServerAliveCountMax=3', '-o', 'ConnectTimeout=10', '-R', '127.0.0.1:18769:127.0.0.1:18770', 'rq-mcp-cloud@64.90.20.78')
            $tunnel = Start-Process -FilePath $ssh -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'ssh.out.log') -RedirectStandardError (Join-Path $logs 'ssh.err.log')
            Write-Status ('SSH tunnel pid ' + $tunnel.Id)
        }
        Save-State
        Start-Sleep -Seconds 10
        foreach ($pair in @(@($mcp, 'mcp.err.log'), @($mcp, 'mcp.out.log'), @($tunnel, 'ssh.err.log'))) {
            $log = Join-Path $logs $pair[1]
            if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 4MB -and -not $pair[0].HasExited) {
                Write-Status ('Restarting process to rotate ' + $pair[1])
                $pair[0].Kill()
                $pair[0].WaitForExit()
            }
        }
    }
} finally {
    foreach ($child in @($tunnel, $mcp)) {
        if ($null -ne $child -and -not $child.HasExited) { $child.Kill() }
    }
}
