$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$root = Join-Path $env:LOCALAPPDATA 'RhythmQuakeCloudMCP'
$task = Get-ScheduledTask -TaskName 'RhythmQuake-Cloud-MCP' -ErrorAction SilentlyContinue
if ($null -ne $task) {
    Disable-ScheduledTask -InputObject $task | Out-Null
    Stop-ScheduledTask -InputObject $task
}
$statePath = Join-Path $root 'private\processes.json'
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in @($state.supervisor, $state.tunnel, $state.mcp)) {
        if ($null -eq $entry) { continue }
        $process = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
        if ($null -ne $process -and $process.Path -eq $entry.path -and $process.StartTime.ToUniversalTime().Ticks.ToString() -eq $entry.startedUtcTicks) { Stop-Process -InputObject $process -Force }
    }
}
Write-Host 'Cloud MCP stopped. Automatic startup is disabled. Run Start.cmd to enable it again.'
