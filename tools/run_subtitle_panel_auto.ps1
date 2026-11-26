$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PanelScript = Join-Path $ProjectRoot 'tmp\subtitle-panel-60943.mjs'
function Find-VmServiceUri {
    try {
        $payload = Invoke-RestMethod -Uri 'http://127.0.0.1:8768/debug/vm-service' -TimeoutSec 2
        if ($payload.vmServiceWebSocketUri) {
            return [string]$payload.vmServiceWebSocketUri
        }
    } catch {
        return $null
    }
    return $null
}

while ($true) {
    $vmUri = $null
    for ($attempt = 0; $attempt -lt 60 -and -not $vmUri; $attempt++) {
        $vmUri = Find-VmServiceUri
        if (-not $vmUri) {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $vmUri) {
        Write-Output '等待 Flutter Windows Debug APP 的 Dart VM Service...'
        Start-Sleep -Seconds 1
        continue
    }

    Write-Output "连接字幕测试面板：$vmUri"
    & node $PanelScript $vmUri
    $exitCode = $LASTEXITCODE
    Write-Output "字幕测试面板已断开，等待 APP 重启（退出码 $exitCode）"
    Start-Sleep -Milliseconds 300
}
