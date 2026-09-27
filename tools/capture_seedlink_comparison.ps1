#Requires -RunAsAdministrator
param(
    [ValidateRange(60,7200)][int]$Seconds = 1800,
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$RunName = 'comparison_capture_20260910'
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$directory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../tmp/fdsn_connection_review'))
$log = Join-Path $directory ($RunName + '.log')
$etl = Join-Path $directory ($RunName + '.etl')
$stopFile = Join-Path $directory ($RunName + '.stop')
$added = @()
$started = $false
Start-Transcript -LiteralPath $log -Force | Out-Null
try {
    if (Test-Path -LiteralPath $stopFile) { throw 'Stop marker already exists' }
    $status = (& pktmon status 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $status -notmatch '(not running|\u6ca1\u6709\u8fd0\u884c)') {
        throw "Capture is not confirmed idle: $status"
    }
    $filters = (& pktmon filter list 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $filters -notmatch '(?im)(^\s*\u65e0\s*$|no filters)') {
        throw "Existing filters will not be modified: $filters"
    }
    $addresses = @(Resolve-DnsName rtserve.earthscope.org -Type A |
        Where-Object IPAddress | Select-Object -ExpandProperty IPAddress -Unique)
    if ($addresses.Count -eq 0) { throw 'No official DNS addresses returned' }
    $index = 0
    foreach ($ip in $addresses) {
        foreach ($port in @(18000,18500,443)) {
            $name = 'RQSeedCompare' + $index++
            & pktmon filter add $name -i $ip -p $port -t TCP
            if ($LASTEXITCODE -ne 0) { throw "Could not add $name" }
            $added += $name
        }
    }
    & pktmon start --capture --comp nics --pkt-size 128 --file-name $etl --file-size 128 --log-mode circular
    if ($LASTEXITCODE -ne 0) { throw 'Could not start capture' }
    $started = $true
    Write-Output ('CAPTURE_STARTED_UTC=' + [DateTime]::UtcNow.ToString('o'))
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline -and !(Test-Path -LiteralPath $stopFile)) {
        Start-Sleep -Seconds 1
    }
} finally {
    if ($started) { & pktmon stop }
    foreach ($name in $added) { & pktmon filter remove $name }
    if ($started -and (Test-Path -LiteralPath $etl)) {
        & pktmon etl2pcap $etl --out (Join-Path $directory ($RunName + '.pcapng'))
    }
    Write-Output ('CAPTURE_FINISHED_UTC=' + [DateTime]::UtcNow.ToString('o'))
    Stop-Transcript | Out-Null
}
