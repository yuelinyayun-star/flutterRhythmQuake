param([int]$Iterations = 3000, [int]$Rounds = 3)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$repo = Split-Path $PSScriptRoot -Parent
$previousLibrary = $env:RQ_STATION_CORE_LIBRARY
Push-Location $repo
try {
  $exe = Join-Path $repo 'build/performance/station_json_benchmark.exe'
  & dart compile exe --packages=.dart_tool/package_config.json tools/benchmark_station_json.dart -o $exe
  if ($LASTEXITCODE -ne 0) { throw 'AOT compile failed' }
  $env:RQ_STATION_CORE_LIBRARY = Join-Path $repo 'build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll'
  $rows = @()
  for ($round=1; $round -le $Rounds; $round++) {
    $modes = if($round%2) { @('dart','rust') } else { @('rust','dart') }
    foreach ($mode in $modes) {
      $row = & $exe $mode observations $Iterations | ConvertFrom-Json
      if ($LASTEXITCODE -ne 0) { throw "Benchmark failed: $mode" }
      $row | Add-Member -NotePropertyName round -NotePropertyValue $round
      $rows += $row
      $row | ConvertTo-Json -Compress
    }
  }
  $report = [ordered]@{
    fixture_sha256 = (Get-FileHash test/fixtures/whews_nied/observations.json).Hash.ToLowerInvariant()
    dll_sha256 = (Get-FileHash $env:RQ_STATION_CORE_LIBRARY).Hash.ToLowerInvariant()
    sdk = (& dart --version 2>&1 | Out-String).Trim()
    measurements = $rows
  }
  [System.IO.File]::WriteAllText((Join-Path $repo 'build/performance/station_json_observations_20261015.json'), ($report | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
} finally {
  $env:RQ_STATION_CORE_LIBRARY = $previousLibrary
  Pop-Location
}
