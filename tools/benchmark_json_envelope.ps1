param([int]$Rounds=3,[string]$LibraryPath='')
$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $repo 'build/performance/json_envelope_benchmark.exe'
$dll=if($LibraryPath){(Resolve-Path -LiteralPath $LibraryPath).ProviderPath}else{Join-Path $repo 'build/native_station_core/release/rq_station_core.dll'}
$workloads=@(
 @{path='test/fixtures/cma_radar/radar_list_20260921.jsonp';kind=0;name='readRadarList';frames=2000},
 @{path='test/fixtures/cma_precipitation/rain_list.jsonp';kind=0;name='getPreObs1h';frames=2000},
 @{path='test/fixtures/china_weather_hourly/beijing_location.jsonp';kind=3;name='getData';frames=2000},
 @{path='test/fixtures/china_weather_hourly/beijing.js';kind=1;name='fc1h_24';frames=400},
 @{path='test/fixtures/china_weather_hourly/yiwu_outlook.js';kind=1;name='fc40';frames=400},
 @{path='test/fixtures/china_weather_hourly/yiwu_outlook.js';kind=1;name='index3d';frames=400}
)
$oldLibrary=$env:RQ_STATION_CORE_LIBRARY
Push-Location $repo
try {
 $env:RQ_STATION_CORE_LIBRARY=$dll
 & D:/flutter_windows_3.41.1-stable/flutter/bin/dart.bat compile exe --packages=.dart_tool/package_config.json tools/benchmark_json_envelope.dart -o $exe
 if($LASTEXITCODE -ne 0){throw 'AOT compile failed'}
 $rows=@()
 foreach($workload in $workloads) {
  for($round=1;$round -le $Rounds;$round++) {
   $modes=if($round%2){@('reference','bytes','string')}else{@('string','bytes','reference')}
   foreach($mode in $modes) {
    $row=& $exe $mode $workload.path $workload.kind $workload.name $workload.frames | ConvertFrom-Json
    if($LASTEXITCODE -ne 0){throw 'Benchmark process failed'}
    $row | Add-Member -NotePropertyName round -NotePropertyValue $round
    $rows+=$row
   }
  }
  $group=@($rows | Where-Object { $_.fixture -eq $workload.path -and $_.selector -eq $workload.name })
  if(@($group.checksum | Select-Object -Unique).Count -ne 1){throw 'Checksum differs'}
 }
 $report=@{dll_sha256=(Get-FileHash -LiteralPath $dll).Hash;measurements=$rows;fixtures=@($workloads.path | Select-Object -Unique | ForEach-Object {Get-FileHash -LiteralPath $_})}
 [IO.File]::WriteAllText((Join-Path $repo 'build/performance/json_envelope_comparison_20261015.json'),($report|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
 $rows | Group-Object fixture,selector,mode | ForEach-Object {
  $times=@($_.Group.ms|Sort-Object);$rss=@($_.Group.rss_mib|Sort-Object)
  [PSCustomObject]@{group=$_.Name;ms=$times[[int][Math]::Floor($times.Count/2)];rss_mib=$rss[[int][Math]::Floor($rss.Count/2)]}
 } | ConvertTo-Json
}finally{$env:RQ_STATION_CORE_LIBRARY=$oldLibrary;Pop-Location}
