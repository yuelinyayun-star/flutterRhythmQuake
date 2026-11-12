param([int]$Rounds=3,[int]$Cycles=500,[string]$LibraryPath='')
$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $repo 'build/performance/palert_levels_benchmark.exe'
$dll=if($LibraryPath){(Resolve-Path -LiteralPath $LibraryPath).ProviderPath}else{Join-Path $repo 'build/native_station_core/release/rq_station_core.dll'}
$previousLibrary=$env:RQ_STATION_CORE_LIBRARY
Push-Location $repo
try {
 $env:RQ_STATION_CORE_LIBRARY=$dll
 & dart compile exe --packages=.dart_tool/package_config.json tools/benchmark_palert_levels.dart -o $exe
 if($LASTEXITCODE -ne 0){throw 'AOT compile failed'}
 $rows=@()
 for($round=1;$round -le $Rounds;$round++) {
  $modes=if($round%2){@('reference','dart','native')}else{@('native','dart','reference')}
  foreach($mode in $modes) {
   $row=& $exe $mode $Cycles | ConvertFrom-Json
   if($LASTEXITCODE -ne 0){throw 'Benchmark failed'}
   $row | Add-Member -NotePropertyName round -NotePropertyValue $round
   $rows+=$row
  }
 }
 if(@($rows.checksum|Select-Object -Unique).Count -ne 1){throw 'Checksum mismatch'}
 $report=@{dll_sha256=(Get-FileHash -LiteralPath $dll).Hash;measurements=$rows;fixtures=@(Get-ChildItem -LiteralPath test/fixtures/palert_cadence_20261014 -Filter '*.json'|Get-FileHash)}
 [IO.File]::WriteAllText((Join-Path $repo 'build/performance/palert_levels_comparison_20261015.json'),($report|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
 $rows|Group-Object mode|ForEach-Object {
  $times=@($_.Group.ms|Sort-Object);$rss=@($_.Group.rss_mib|Sort-Object)
  [PSCustomObject]@{mode=$_.Name;median_ms=$times[[int][Math]::Floor($times.Count/2)];median_rss_mib=$rss[[int][Math]::Floor($rss.Count/2)]}
 }|ConvertTo-Json
} finally {$env:RQ_STATION_CORE_LIBRARY=$previousLibrary;Pop-Location}
