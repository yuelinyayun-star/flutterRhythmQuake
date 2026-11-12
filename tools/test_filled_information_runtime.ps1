$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $env:RQ_STATION_CORE_LIBRARY = (Resolve-Path 'build/windows/x64/runner/Release/rq_station_core.dll').Path
    $logRoot = 'tmp/jma_info_center_20261030'
    $failures = @()
    foreach ($caseName in @('jma-1584','jma-430','shakemap-1584','shakemap-430','empty-1584','empty-430','dyfi-1584','dyfi-430','cwa-1584','cwa-430')) {
        $logPath = Join-Path $logRoot "filled-runtime-$caseName.log"
        & flutter test test/filled_information_runtime_validation_test.dart "--dart-define=FILL_CASE=$caseName" --reporter expanded *> $logPath
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $logPath -Encoding UTF8 | Select-Object -Last 45
            $failures += $caseName
            continue
        }
        $verified = Select-String -LiteralPath $logPath -Pattern 'OTHER_FILL_VERIFIED'
        if (-not $verified) { throw "No executed verification found for $caseName" }
        $verified.Line
    }
    & flutter test test/volcano_ashfall_camera_fit_test.dart --reporter expanded *> (Join-Path $logRoot 'volcano-fill-camera.log')
    if ($LASTEXITCODE -ne 0) { throw 'Failed original volcano ashfall window camera checks' }
    $rows = Get-ChildItem -LiteralPath (Join-Path $logRoot 'other-filled-runtime') -Filter '*.json' |
        Where-Object { $_.BaseName -match '^(jma-|shakemap-|dyfi-|cwa-).+-(1584|430)$' } |
        ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
    $rows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $logRoot 'other-filled-runtime/matrix-results.json') -Encoding UTF8
    if ($failures.Count) { throw ('Failed matrix members: ' + ($failures -join ', ')) }
} finally { Pop-Location }
