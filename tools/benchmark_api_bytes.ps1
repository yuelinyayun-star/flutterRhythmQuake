param([int]$Rounds=3)
$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $repo 'build/performance/api_bytes_benchmark.exe'
$dll=Join-Path $repo 'build/windows/x64/runner/Release/rq_station_core.dll'
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
 & D:/flutter_windows_3.41.1-stable/flutter/bin/dart.bat compile exe --packages=.dart_tool/package_config.json tools/benchmark_api_bytes.dart -o $exe
 if($LASTEXITCODE -ne 0){throw 'AOT compile failed'}
 $rows=@()
 foreach($workload in $workloads){
  for($round=1;$round -le $Rounds;$round++){
   $modes=if($round%2){@('string','bytes')}else{@('bytes','string')}
   foreach($mode in $modes){
    $arguments=@($mode,$workload.path,"$($workload.frames)")
    if($workload.retain){$arguments+='retain'}
    $row=& $exe @arguments | ConvertFrom-Json
    if($LASTEXITCODE -ne 0){throw "Benchmark failed: $mode $($workload.path)"}
    $row | Add-Member -NotePropertyName round -NotePropertyValue $round
    $rows+=$row
   }
  }
  $checksums=@($rows | Where-Object fixture -eq $workload.path | Select-Object -ExpandProperty checksum -Unique)
  if($checksums.Count -ne 1){throw "Checksum mismatch: $($workload.path)"}
 }
 $report=@{dll_sha256=(Get-FileHash -LiteralPath $dll).Hash;fixtures=@($workloads | ForEach-Object {Get-FileHash -LiteralPath $_.path});measurements=$rows}
 [IO.File]::WriteAllText((Join-Path $repo 'build/performance/api_bytes_comparison_20261015.json'),($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 $rows | Group-Object fixture,mode | ForEach-Object {
  $times=@($_.Group.processing_ms | Sort-Object);$rss=@($_.Group.rss_mib | Sort-Object)
  [PSCustomObject]@{group=$_.Name;ms=$times[[int][Math]::Floor($times.Count/2)];rss_mib=$rss[[int][Math]::Floor($rss.Count/2)]}
 } | ConvertTo-Json
}finally{$env:RQ_STATION_CORE_LIBRARY=$previousLibrary;Pop-Location}
