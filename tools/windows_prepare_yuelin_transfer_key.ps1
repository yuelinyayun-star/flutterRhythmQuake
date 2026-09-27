$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$d='C:\Users\Administrator\AppData\Local\Temp\rq-yuelin-migration-20260911'
$k=Join-Path $d 'transfer_ed25519';$h=Join-Path $d 'target_known_hosts'
Remove-Item -LiteralPath $k,($k+'.pub'),$h -Force -ErrorAction SilentlyContinue
& ssh-keygen.exe -q -t ed25519 -N '""' -C 'rq-yuelin-migration-20260911' -f $k
if($LASTEXITCODE){throw 'ssh-keygen failed'}
& icacls.exe $k /inheritance:r /grant:r 'Administrator:F' 'SYSTEM:F'|Out-Null
& $env:ComSpec /d /c ('ssh-keyscan.exe -T 10 -t ed25519 -p 22 64.90.20.78 2>nul > "'+$h+'"')
$fp=[string](& ssh-keygen.exe -lf $h -E sha256)
if($fp -notmatch 'SHA256:c3XvPjgSy6QN5WT2RzlyJuLR6C6p8/WksJ2wYyfcuDw'){throw 'target fingerprint mismatch'}
[pscustomobject]@{PublicKey=[string](Get-Content -Raw -Encoding ascii ($k+'.pub'));Fingerprint=$fp}|ConvertTo-Json -Depth 3 -Compress
