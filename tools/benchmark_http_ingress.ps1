param([int]$Rounds=3, [string]$ReportName='http_ingress_comparison_20261016.json')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Console]::OutputEncoding
$repo=Split-Path $PSScriptRoot -Parent
Push-Location $repo
$previousLibrary=$env:RQ_STATION_CORE_LIBRARY
try {
  $output=Join-Path $repo 'build/performance'
  [IO.Directory]::CreateDirectory($output) | Out-Null
  $exe=Join-Path $output 'http_ingress_benchmark.exe'
  & 'D:/flutter_windows_3.41.1-stable/flutter/bin/dart.bat' compile exe --packages=.dart_tool/package_config.json tools/benchmark_http_ingress.dart -o $exe
  if($LASTEXITCODE -ne 0){throw 'HTTP benchmark compile failed'}
  $env:RQ_STATION_CORE_LIBRARY=(Resolve-Path build/windows/x64/runner/Profile/rq_station_core.dll).ProviderPath
  $rows=@()
  foreach($encoding in @('plain','gzip')) {
    foreach($count in @(1,16)) {
      for($round=1;$round -le $Rounds;$round++) {
        $modes=if($round % 2){@('dart','native')}else{@('native','dart')}
        foreach($mode in $modes) {
          $row=& $exe $mode $count $encoding | ConvertFrom-Json
          if($LASTEXITCODE -ne 0){throw "HTTP benchmark failed: $mode $count $encoding"}
          $row | Add-Member -NotePropertyName round -NotePropertyValue $round
          $rows+=$row
          $row | ConvertTo-Json -Compress
        }
      }
    }
  }
  $report=@{measurements=$rows;dllSha256=(Get-FileHash $env:RQ_STATION_CORE_LIBRARY).Hash;input='test/fixtures/jma_ashfall/20260923145625_0_VFVO55_010000.xml';scope='HTTP receiving, gzip decode and unchanged-byte SHA256; local server isolate included, no Flutter engine or domain processing'}
  [IO.File]::WriteAllText((Join-Path $output $ReportName),($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}finally{
  if($null -eq $previousLibrary){Remove-Item Env:RQ_STATION_CORE_LIBRARY -ErrorAction SilentlyContinue}else{$env:RQ_STATION_CORE_LIBRARY=$previousLibrary}
  Pop-Location
}
