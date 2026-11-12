param([int]$Repeats = 15000, [int]$Rounds = 3)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
$previousLibrary = $env:RQ_STATION_CORE_LIBRARY
try {
  $utf8 = [System.Text.UTF8Encoding]::new($false)
  $outputDir = Join-Path $repo 'build/performance'
  [System.IO.Directory]::CreateDirectory($outputDir) | Out-Null
  $service = [System.IO.File]::ReadAllText((Join-Path $repo 'lib/services/sources/global_quake_service_io.dart'), $utf8)
  $part = [System.IO.File]::ReadAllText((Join-Path $repo 'lib/services/sources/global_quake_native_decoder.dart'), $utf8)
  $decoder = $service.Substring($service.IndexOf('class _JavaObjectStreamDecoder {'))
  $native = $part.Substring($part.IndexOf('typedef _GqAddNative'))
  $generated = "part of '../../tools/benchmark_global_quake_stream.dart';`n" + $decoder + "`n" + $native
  [System.IO.File]::WriteAllText((Join-Path $outputDir 'global_quake_decoder_under_test.dart'), $generated, $utf8)
  $exe = Join-Path $outputDir 'global_quake_stream_benchmark.exe'
  & dart compile exe --packages=.dart_tool/package_config.json tools/benchmark_global_quake_stream.dart -o $exe
  if ($LASTEXITCODE -ne 0) { throw 'AOT compile failed' }
  $env:RQ_STATION_CORE_LIBRARY = Join-Path $repo 'build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll'
  $results = @()
  foreach ($workload in @('fresh', 'fragmented', 'stream')) {
    for ($round = 1; $round -le $Rounds; $round++) {
      $modes = if ($round % 2) { @('dart', 'rust') } else { @('rust', 'dart') }
      foreach ($mode in $modes) {
        $row = & $exe $mode $workload $Repeats | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw "Benchmark failed: $mode $workload" }
        $row | Add-Member -NotePropertyName round -NotePropertyValue $round
        $results += $row
        $row | ConvertTo-Json -Compress
      }
    }
  }
  $report = [ordered]@{
    capture_sha256 = (Get-FileHash test/fixtures/global_quake/stream_20260921.bin).Hash.ToLowerInvariant()
    dll_sha256 = (Get-FileHash $env:RQ_STATION_CORE_LIBRARY).Hash.ToLowerInvariant()
    sdk = (& dart --version 2>&1 | Out-String).Trim()
    measurements = $results
  }
  [System.IO.File]::WriteAllText((Join-Path $outputDir 'global_quake_stream_comparison_20261015.json'), ($report | ConvertTo-Json -Depth 8), $utf8)
} finally {
  $env:RQ_STATION_CORE_LIBRARY = $previousLibrary
  Pop-Location
}
