$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$scan=Get-Command ssh-keyscan.exe -ErrorAction SilentlyContinue
$gen=Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
if(-not $scan -or -not $gen){[pscustomobject]@{Available=$false}|ConvertTo-Json -Compress;exit}
$p=Join-Path $env:TEMP 'rq_target_hostkey.pub'
& $env:ComSpec /d /c ('"'+$scan.Source+'" -T 10 -p 22 64.90.20.78 2>nul > "'+$p+'"')
$fp=@(& $gen.Source -lf $p -E sha256 2>$null)
Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
[pscustomobject]@{Available=$true;Fingerprints=$fp}|ConvertTo-Json -Depth 3 -Compress
