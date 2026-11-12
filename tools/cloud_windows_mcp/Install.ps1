$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$source = $PSScriptRoot
$destination = Join-Path $env:LOCALAPPDATA 'RhythmQuakeCloudMCP'
$taskName = 'RhythmQuake-Cloud-MCP'
$marker = 'rhythmquake-cloud-windows-mcp-v1'

if (-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'))) {
    throw 'Windows OpenSSH Client is missing. Install the Windows OpenSSH Client optional feature first.'
}
if (-not [Environment]::UserInteractive) { throw 'Run this once inside the cloud computer logged-in desktop.' }
if (Test-Path -LiteralPath $destination) {
    $existingMarker = Join-Path $destination 'package.id'
    if (-not (Test-Path -LiteralPath $existingMarker) -or (Get-Content -LiteralPath $existingMarker -Raw -Encoding UTF8).Trim() -ne $marker) {
        throw 'Destination already exists and is not this MCP deployment. No files were changed.'
    }
}
Write-Host '[1/4] Verifying the deployment package...'
$manifest = Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$verified = 0
$total = $manifest.files.Count
foreach ($entry in $manifest.files) {
    $file = [IO.Path]::GetFullPath((Join-Path $source $entry.path))
    if (-not $file.StartsWith(([IO.Path]::GetFullPath($source).TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid manifest path.' }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw ('Package hash mismatch: ' + $entry.path) }
    $verified++
    if ($verified % 250 -eq 0 -or $verified -eq $total) { Write-Host ("`rVerified {0}/{1} files ({2}%)   " -f $verified, $total, [math]::Floor(100 * $verified / $total)) -NoNewline }
}
Write-Host ''
Write-Host '[2/4] Installing runtime and files...'
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    & (Join-Path $destination 'Stop.ps1')
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $destination '/inheritance:r' '/grant:r' ('*' + $sid + ':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to protect MCP credentials.' }
if ([IO.Path]::GetFullPath($source).TrimEnd('\') -ne [IO.Path]::GetFullPath($destination).TrimEnd('\')) {
    foreach ($item in Get-ChildItem -LiteralPath $source -Force) { Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force }
}
& icacls.exe (Join-Path $destination 'private\cloud_ed25519') '/inheritance:r' '/grant:r' ('*' + $sid + ':F') '*S-1-5-18:F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to protect the SSH private key.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Host '[3/4] Registering the background task...'
$action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'powershell.exe') -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $destination 'Supervise.ps1') + '"') -WorkingDirectory $destination
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description 'Authenticated Windows MCP and restricted outbound tunnel for RhythmQuake cloud testing.' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host '[4/4] Waiting for MCP and the outbound tunnel (up to 120 seconds)...'
$deadline = [DateTime]::UtcNow.AddSeconds(120)
$ready = $false
while ([DateTime]::UtcNow -lt $deadline) {
    $authenticatedService = $false
    try { Invoke-WebRequest -Uri 'http://127.0.0.1:18770/mcp' -UseBasicParsing -TimeoutSec 2 | Out-Null } catch {
        if ($null -ne $_.Exception.Response) { $authenticatedService = ([int]$_.Exception.Response.StatusCode -eq 401) }
    }
    $sshLog = Join-Path $destination 'logs\ssh.err.log'
    $tunnelReady = (Test-Path -LiteralPath $sshLog) -and (Select-String -LiteralPath $sshLog -Pattern 'remote forward success for: listen 127.0.0.1:18769' -SimpleMatch -Quiet)
    Write-Host ("`rMCP: {0}; tunnel: {1}; task: {2}              " -f $authenticatedService, $tunnelReady, (Get-ScheduledTask -TaskName $taskName).State) -NoNewline
    if ($authenticatedService -and $tunnelReady) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
Write-Host ''
if (-not $ready) {
    foreach ($name in @('supervisor.log', 'mcp.err.log', 'ssh.err.log')) {
        $log = Join-Path (Join-Path $destination 'logs') $name
        if (Test-Path -LiteralPath $log) { Write-Host $name; Get-Content -LiteralPath $log -Encoding UTF8 -Tail 8 }
    }
    throw ('MCP or the outbound tunnel did not become ready. See ' + (Join-Path $destination 'logs'))
}
Write-Host ('MCP installed and started: ' + $destination)
Write-Host 'Keep the Windows desktop signed in and unlocked during the test.'
Write-Host 'Tell Codex that Cloud MCP has started. Do not send private keys or the package to others.'
