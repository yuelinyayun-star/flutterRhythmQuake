param([int]$Frames = 1000, [int]$Rounds = 3, [switch]$Retain)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$repo = Split-Path $PSScriptRoot -Parent
$stage = Join-Path $repo 'build/performance/station-receiver-profile-20261015'
$exe = Join-Path $stage 'flutterrhythmquake.exe'
if (!(Test-Path -LiteralPath $exe)) { throw 'Build and stage tool/station_receiver_benchmark.dart first' }
$previousLibrary = $env:RQ_STATION_CORE_LIBRARY
try {
  $env:RQ_STATION_CORE_LIBRARY = Join-Path $stage 'rq_station_core.dll'
  $env:RQ_RECEIVER_FRAMES = "$Frames"
  $env:RQ_RECEIVER_RETAIN = if($Retain){'1'}else{'0'}
  $rows=@()
  for($round=1;$round -le $Rounds;$round++) {
    $modes=if($round%2){@('dart','rust')}else{@('rust','dart')}
    foreach($mode in $modes) {
      $env:RQ_RECEIVER_MODE=$mode
      $runKey=Get-Date -Format yyyyMMddHHmmssfff
      $env:RQ_RECEIVER_OUTPUT=Join-Path $stage "$mode-$round-$runKey.json"
      $process=Start-Process -FilePath $exe -WorkingDirectory $repo -WindowStyle Hidden -PassThru
      if(!$process.WaitForExit(60000)){ Stop-Process -Id $process.Id; throw "Benchmark timeout: $mode" }
      $row=Get-Content -LiteralPath $env:RQ_RECEIVER_OUTPUT -Encoding UTF8 -Raw | ConvertFrom-Json
      if($row.error){throw $row.error}
      if($row.frames -ne $Frames){throw 'Incomplete frame count'}
      $row | Add-Member -NotePropertyName round -NotePropertyValue $round
      $rows+=$row
      $row | ConvertTo-Json -Compress
    }
  }
  $report=[ordered]@{dll_sha256=(Get-FileHash $env:RQ_STATION_CORE_LIBRARY).Hash.ToLowerInvariant();fixture_sha256=(Get-FileHash (Join-Path $repo 'test/fixtures/whews_nied/observations.json')).Hash.ToLowerInvariant();measurements=$rows}
  $reportFile=if($Retain){'build/performance/station_receiver_retention_20261015.json'}else{'build/performance/station_receiver_comparison_20261015.json'}
  [IO.File]::WriteAllText((Join-Path $repo $reportFile),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
} finally {
  $env:RQ_STATION_CORE_LIBRARY=$previousLibrary
  Remove-Item Env:RQ_RECEIVER_MODE,Env:RQ_RECEIVER_OUTPUT,Env:RQ_RECEIVER_FRAMES,Env:RQ_RECEIVER_RETAIN -ErrorAction SilentlyContinue
}
