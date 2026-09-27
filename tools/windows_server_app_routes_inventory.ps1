$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$apps = @(
    [pscustomobject]@{Name='KMA PEWS Relay';Path='D:\KmaPewsRelay\app\kma_pews_relay.py'},
    [pscustomobject]@{Name='WAuth Gateway';Path='D:\WAuthGateway\wauth_gateway.py'}
) | ForEach-Object {
    $path = $_.Path
    $lines = if (Test-Path -LiteralPath $path) {
        @(Get-Content -LiteralPath $path -Encoding UTF8 | Where-Object {
            $_ -match '^\s*@(?:app|router)\.(?:get|post|put|delete|patch|websocket|route)\s*\(' -or
            $_ -match '^\s*(?:async\s+)?def\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
        } | ForEach-Object { $_.Trim() })
    } else { @() }
    [pscustomobject]@{Name=$_.Name;Path=$path;Exists=Test-Path -LiteralPath $path;Routes=$lines}
}
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Apps=$apps} |
    ConvertTo-Json -Depth 6 -Compress
