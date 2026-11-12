param([int]$Rounds=3)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Console]::OutputEncoding
$repo=Split-Path $PSScriptRoot -Parent
Push-Location $repo
$oldLibrary=$env:RQ_STATION_CORE_LIBRARY
try {
  $stamp=Get-Date -Format yyyyMMdd-HHmmss
  $directory=Join-Path $repo "build/performance/replay_archive_$stamp"
  [IO.Directory]::CreateDirectory($directory) | Out-Null
  $exe=Join-Path $directory 'benchmark.exe'
  & 'D:/flutter_windows_3.41.1-stable/flutter/bin/dart.bat' compile exe --packages=.dart_tool/package_config.json tools/benchmark_replay_archive.dart -o $exe
  if($LASTEXITCODE -ne 0){throw 'Archive benchmark compilation failed'}
  $env:RQ_STATION_CORE_LIBRARY=(Resolve-Path build/windows/x64/runner/Profile/rq_station_core.dll).ProviderPath
  $rows=@()
  for($round=1;$round -le $Rounds;$round++) {
    $modes=if($round%2){@('dart','native')}else{@('native','dart')}
    foreach($mode in $modes) {
      $row=& $exe $mode (Join-Path $directory "$round-$mode") | ConvertFrom-Json
      if($LASTEXITCODE -ne 0){throw "Archive benchmark failed: $round $mode"}
      $row | Add-Member -NotePropertyName round -NotePropertyValue $round
      $rows+=$row;$row | ConvertTo-Json -Compress
    }
  }
  $report=@{measurements=$rows;dllSha256=(Get-FileHash $env:RQ_STATION_CORE_LIBRARY).Hash;scope='20320 original records, one unchanged GIF creates both replay outputs; forced save every 80 records. All producer decode/bridge/serialization/IO included. Not the complete APP or full 18724-GIF capture workload.'}
  [IO.File]::WriteAllText((Join-Path $directory 'comparison.json'),($report | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
  $directory
}finally {
  if($null -eq $oldLibrary){Remove-Item Env:RQ_STATION_CORE_LIBRARY -ErrorAction SilentlyContinue}else{$env:RQ_STATION_CORE_LIBRARY=$oldLibrary}
  Pop-Location
}
