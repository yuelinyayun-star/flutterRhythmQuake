param([int]$Rounds=3)
$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$repo=Split-Path $PSScriptRoot -Parent
$backup=Join-Path $repo 'build/performance/backups/station-json-deep-20261015-094441'
$oldExe=Join-Path $backup 'build/performance/station_json_benchmark.exe'
$oldDll=Join-Path $backup 'build/windows/x64/runner/Profile/rq_station_core.dll'
$newExe=Join-Path $repo 'build/performance/station_json_benchmark.exe'
$newDll=Join-Path $repo 'build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll'
$previousLibrary=$env:RQ_STATION_CORE_LIBRARY
Push-Location $repo
try {
 & dart compile exe --packages=.dart_tool/package_config.json tools/benchmark_station_json.dart -o $newExe
 if($LASTEXITCODE -ne 0){throw 'AOT compile failed'}
 $rows=@()
 foreach($retain in @($false,$true)) {
  for($round=1;$round -le $Rounds;$round++) {
   $implementations=if($round%2){@('dart','before-rust','rust')}else{@('rust','before-rust','dart')}
   foreach($implementation in $implementations) {
    $exe=if($implementation -eq 'before-rust'){$oldExe}else{$newExe}
    $env:RQ_STATION_CORE_LIBRARY=if($implementation -eq 'before-rust'){$oldDll}else{$newDll}
    $mode=if($implementation -eq 'dart'){'dart'}else{'rust'}
    # The prior executable has no retain option; retained comparisons use the
    # frozen original Dart and the current format only, never mismatched binaries.
    if($retain -and $implementation -eq 'before-rust'){continue}
    $iterations=if($retain){1000}else{3000}
    $arguments=@($mode,'observations',"$iterations")
    if($retain){$arguments+='retain'}
    $row=& $exe @arguments | ConvertFrom-Json
    if($LASTEXITCODE -ne 0){throw "Benchmark failed: $implementation"}
    $row | Add-Member -NotePropertyName implementation -NotePropertyValue $implementation
    $row | Add-Member -NotePropertyName round -NotePropertyValue $round
    $row | Add-Member -NotePropertyName retention -NotePropertyValue $retain
    $rows+=$row
    $row | ConvertTo-Json -Compress
   }
  }
 }
 $report=[ordered]@{fixture_sha256=(Get-FileHash test/fixtures/whews_nied/observations.json).Hash.ToLowerInvariant();dll_sha256=(Get-FileHash $newDll).Hash.ToLowerInvariant();before_dll_sha256=(Get-FileHash $oldDll).Hash.ToLowerInvariant();measurements=$rows}
 [IO.File]::WriteAllText((Join-Path $repo 'build/performance/station_json_deep_comparison_20261015.json'),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}finally{$env:RQ_STATION_CORE_LIBRARY=$previousLibrary;Pop-Location}
