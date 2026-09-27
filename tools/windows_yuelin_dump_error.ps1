$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$p='C:\Users\Administrator\AppData\Local\Temp\rq-yuelin-migration-20260911\dump-error.txt'
[pscustomobject]@{Exists=(Test-Path $p);Lines=if(Test-Path $p){@(Get-Content -LiteralPath $p -Encoding UTF8)}else{@()}}|ConvertTo-Json -Depth 3 -Compress
