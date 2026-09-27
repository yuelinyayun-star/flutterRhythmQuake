$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$d='C:\Users\Administrator\AppData\Local\Temp\rq-yuelin-migration-20260911'
Remove-Item -LiteralPath (Join-Path $d 'transfer_ed25519'),(Join-Path $d 'transfer_ed25519.pub'),(Join-Path $d 'target_known_hosts') -Force -ErrorAction SilentlyContinue
[pscustomobject]@{Cleaned=$true}|ConvertTo-Json -Compress
