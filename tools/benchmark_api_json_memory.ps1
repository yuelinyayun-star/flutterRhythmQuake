param([int]$Rounds=3)
$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$repo=Split-Path $PSScriptRoot -Parent
$stage=Join-Path $repo 'build/performance/api-json-memory-profile-20261015'
$exe=Join-Path $stage 'flutterrhythmquake.exe'
$oldMode=$env:RQ_API_MEMORY_MODE
$oldOutput=$env:RQ_API_MEMORY_OUTPUT
$oldLibrary=$env:RQ_STATION_CORE_LIBRARY
Push-Location $repo
try {
 $env:RQ_STATION_CORE_LIBRARY=Join-Path $stage 'rq_station_core.dll'
 $rows=@()
 for($round=1;$round -le $Rounds;$round++) {
  $modes=if($round%2){@('dart','rust')}else{@('rust','dart')}
  foreach($mode in $modes) {
   $output=Join-Path $repo "build/performance/api-json-memory-$mode-$round-$([Guid]::NewGuid().ToString('N')).json"
   $env:RQ_API_MEMORY_MODE=$mode
   $env:RQ_API_MEMORY_OUTPUT=$output
   $child=Start-Process -FilePath $exe -WorkingDirectory $repo -WindowStyle Hidden -PassThru
   if(!$child.WaitForExit(60000)) {
    Stop-Process -Id $child.Id
    throw 'Isolated memory diagnostic timed out'
   }
   $row=Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
   if($row.error -or $row.frames -ne 100){throw "Diagnostic failed: $($row|ConvertTo-Json -Compress)"}
   $row|Add-Member -NotePropertyName round -NotePropertyValue $round
   $rows+=$row
  }
 }
 $report=@{dll_sha256=(Get-FileHash (Join-Path $stage 'rq_station_core.dll')).Hash;measurements=$rows}
 [IO.File]::WriteAllText((Join-Path $repo 'build/performance/api_json_memory_20261015.json'),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 $rows|Select-Object mode,round,processing_ms,live_rss_mb,live_native_sessions,live_native_bytes,released_rss_mb,released_native_sessions,released_native_bytes|ConvertTo-Json
}finally{
 $env:RQ_API_MEMORY_MODE=$oldMode
 $env:RQ_API_MEMORY_OUTPUT=$oldOutput
 $env:RQ_STATION_CORE_LIBRARY=$oldLibrary
 Pop-Location
}
