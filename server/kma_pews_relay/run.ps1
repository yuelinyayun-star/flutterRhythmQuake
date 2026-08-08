$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root '.venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $Python)) {
    throw '尚未安装运行环境，请先执行 .\install.ps1'
}

if (-not $env:KMA_RELAY_HOST) { $env:KMA_RELAY_HOST = '0.0.0.0' }
if (-not $env:KMA_RELAY_PORT) { $env:KMA_RELAY_PORT = '8765' }

& $Python (Join-Path $Root 'kma_pews_relay.py')
