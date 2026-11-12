param([int]$Rounds=3)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$OutputEncoding=[Console]::OutputEncoding
$repo=Split-Path $PSScriptRoot -Parent
Push-Location $repo
$previousLibrary=$env:RQ_STATION_CORE_LIBRARY
try {
  $output=Join-Path $repo 'build/performance'
  [IO.Directory]::CreateDirectory($output) | Out-Null
  $exe=Join-Path $output 'tcp_ingress_benchmark.exe'
  & 'D:/flutter_windows_3.41.1-stable/flutter/bin/dart.bat' compile exe --packages=.dart_tool/package_config.json tools/benchmark_tcp_ingress.dart -o $exe
  if($LASTEXITCODE -ne 0){throw 'TCP benchmark compile failed'}
  $env:RQ_STATION_CORE_LIBRARY=(Resolve-Path build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll).ProviderPath
  $rows=@()
  foreach($count in @(1,32)) {
    for($round=1;$round -le $Rounds;$round++) {
      $modes=if($round % 2){@('dart','native')}else{@('native','dart')}
      foreach($mode in $modes) {
        $row=& $exe $mode $count | ConvertFrom-Json
        if($LASTEXITCODE -ne 0){throw "TCP benchmark failed: $mode $count"}
        $row | Add-Member -NotePropertyName round -NotePropertyValue $round
        $rows+=$row
        $row | ConvertTo-Json -Compress
      }
    }
  }
  $report=@{measurements=$rows;dllSha256=(Get-FileHash $env:RQ_STATION_CORE_LIBRARY).Hash;input='test/fixtures/global_quake/stream_20260921.bin';scope='TCP receiving plus unchanged-byte SHA256; local server isolate included, no Flutter engine or source processing'}
  [IO.File]::WriteAllText((Join-Path $output 'tcp_ingress_comparison_20261016.json'),($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}finally{
  if($null -eq $previousLibrary){Remove-Item Env:RQ_STATION_CORE_LIBRARY -ErrorAction SilentlyContinue}else{$env:RQ_STATION_CORE_LIBRARY=$previousLibrary}
  Pop-Location
}
