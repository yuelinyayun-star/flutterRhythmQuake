$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $Python)) {
    throw "Python virtual environment not found: $Python"
}
if ([string]::IsNullOrWhiteSpace($env:WAUTH_CLIENT_SECRET)) {
    throw 'WAUTH_CLIENT_SECRET is not configured.'
}

& $Python (Join-Path $Root 'wauth_gateway.py')
