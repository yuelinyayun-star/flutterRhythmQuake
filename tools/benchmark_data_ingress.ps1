param([int]$Rounds=3)
$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=Split-Path $PSScriptRoot -Parent
$exe=Join-Path $repo 'build/performance/data_ingress_benchmark.exe'
$dll=Join-Path $repo 'build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll'
$oldLibrary=$env:RQ_STATION_CORE_LIBRARY
Push-Location $repo
try {
  $env:RQ_STATION_CORE_LIBRARY=$dll
  & dart compile exe --packages=.dart_tool/package_config.json tools/benchmark_data_ingress.dart -o $exe
  if($LASTEXITCODE -ne 0){throw 'AOT compile failed'}
  $workloads=@(
    @{kind='sse';path='test/fixtures/api_ingress_20261016/trem_stream.original.bytes';count=600},
    @{kind='weather';path='test/fixtures/api_ingress_20261016/weather_alarm_full.original.bytes';count=60},
    @{kind='json';path='assets/maps/ka/medium.global.modified.topo.json';count=100},
    @{kind='json';path='assets/maps/cn.fault.topo.json';count=100}
  )
  $rows=@()
  foreach($workload in $workloads){
    for($round=1;$round -le $Rounds;$round++){
      $modes=if($round%2){@('reference','native')}else{@('native','reference')}
      foreach($mode in $modes){
        $row=& $exe $mode $workload.kind $workload.path $workload.count | ConvertFrom-Json
        if($LASTEXITCODE -ne 0){throw 'Benchmark process failed'}
        $row | Add-Member -NotePropertyName round -NotePropertyValue $round
        $rows+=$row
      }
    }
    $group=@($rows | Where-Object {$_.fixture -eq $workload.path})
    if(@($group.output_sha256 | Select-Object -Unique).Count -ne 1){throw 'Output differs'}
    if(@($group.input_sha256 | Select-Object -Unique).Count -ne 1){throw 'Input differs'}
  }
  $report=@{dll_sha256=(Get-FileHash -LiteralPath $dll).Hash;measurements=$rows}
  [IO.File]::WriteAllText((Join-Path $repo 'build/performance/data_ingress_comparison_20261016.json'),($report|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
  $rows | Group-Object fixture,mode | ForEach-Object {
    $times=@($_.Group.ms | Sort-Object)
    [PSCustomObject]@{group=$_.Name;median_ms=$times[[int][Math]::Floor($times.Count/2)]}
  } | ConvertTo-Json
} finally {
  $env:RQ_STATION_CORE_LIBRARY=$oldLibrary
  Pop-Location
}
