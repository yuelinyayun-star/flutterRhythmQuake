$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()
$previousLibrary = $env:RQ_STATION_CORE_LIBRARY
$previousOutput = $env:RQ_FILL_OUTPUT
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $env:RQ_STATION_CORE_LIBRARY = (Resolve-Path 'build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll').Path
    $root = 'tmp/information_fill_extent_20261030'
    $env:RQ_FILL_OUTPUT = Join-Path $root 'runtime'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    foreach ($member in @('cenc-modeled-1584','cenc-modeled-430','cwa-modeled-1584','cwa-modeled-430','cwa-1584','cwa-430','jma-1584','jma-430','shared-1584','shared-430')) {
        $log = Join-Path $root "$member.log"
        & flutter test test/filled_information_runtime_validation_test.dart "--dart-define=FILL_CASE=$member" --reporter expanded *> $log
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $log -Encoding UTF8 | Select-Object -Last 40
            throw "Information fill verification failed: $member"
        }
        $evidence = Select-String -LiteralPath $log -Pattern 'OTHER_FILL_VERIFIED'
        if (-not $evidence) { throw "No executed verification: $member" }
        $evidence.Line
    }
} finally {
    Pop-Location
    $env:RQ_STATION_CORE_LIBRARY = $previousLibrary
    $env:RQ_FILL_OUTPUT = $previousOutput
}
