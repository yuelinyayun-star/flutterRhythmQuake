param([int]$Rounds=3)
$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $repo 'build/performance/api_json_benchmark.exe'
$dll=Join-Path $repo 'build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll'
$previousLibrary=$env:RQ_STATION_CORE_LIBRARY
$workloads=@(
 @{path='test/fixtures/catalog_20260917/whews_all.json';frames=300;retain=$false},
 @{path='test/fixtures/catalog_20260917/jian_all.json';frames=300;retain=$false},
 @{path='test/fixtures/emsc_ws_20261008.original.json';frames=3000;retain=$false},
 @{path='test/fixtures/jma_voice/p2p_history_20260921.json';frames=300;retain=$false},
 @{path='test/fixtures/usgs_dyfi/ci41345415.versions.original.geojson';frames=100;retain=$true},
 @{path='test/fixtures/typhoon/zj_202625_20260921.json';frames=100;retain=$true}
)
Push-Location $repo
try {
 $env:RQ_STATION_CORE_LIBRARY=$dll
 & dart compile exe --packages=.dart_tool/package_config.json tools/benchmark_api_json.dart -o $exe
 if($LASTEXITCODE -ne 0){throw 'AOT compile failed'}
 $rows=@()
 foreach($snapshot in @($false,$true)) {
  foreach($workload in $workloads) {
   for($round=1;$round -le $Rounds;$round++) {
    $modes=if($round%2){@('dart','rust')}else{@('rust','dart')}
    foreach($mode in $modes) {
     $arguments=@($mode,$workload.path,"$($workload.frames)")
     if($snapshot){$arguments+='snapshot'}
     if($workload.retain){$arguments+='retain'}
     $row=& $exe @arguments | ConvertFrom-Json
     if($LASTEXITCODE -ne 0){throw "Benchmark failed: $mode $($workload.path)"}
     $row | Add-Member -NotePropertyName round -NotePropertyValue $round
     $rows+=$row
    }
   }
   $modes= $rows | Where-Object {$_.fixture -eq $workload.path -and $_.snapshot -eq $snapshot}
   $checksums= @($modes | Select-Object -ExpandProperty checksum -Unique)
   if($checksums.Count -ne 1){throw "Checksum mismatch: $($workload.path)"}
  }
 }
 $hashes=@($workloads | ForEach-Object {Get-FileHash -LiteralPath $_.path})
 $report=@{dll_sha256=(Get-FileHash $dll).Hash;fixtures=$hashes;measurements=$rows}
 [IO.File]::WriteAllText((Join-Path $repo 'build/performance/api_json_comparison_20261015.json'),($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 $rows | Group-Object fixture,snapshot,mode | ForEach-Object {
  $times=@($_.Group.processing_ms | Sort-Object)
  $rss=@($_.Group.rss_mb | Sort-Object)
  [PSCustomObject]@{group=$_.Name;ms=$times[[int][Math]::Floor($times.Count/2)];rss_mb=$rss[[int][Math]::Floor($rss.Count/2)]}
 } | ConvertTo-Json
}finally{$env:RQ_STATION_CORE_LIBRARY=$previousLibrary;Pop-Location}
