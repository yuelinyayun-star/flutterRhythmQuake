$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$path='C:\Users\Administrator\AppData\Local\Temp\rq-relay-migration-20260911'
if($path -ne 'C:\Users\Administrator\AppData\Local\Temp\rq-relay-migration-20260911'){throw 'unexpected cleanup path'}
Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
[pscustomobject]@{Cleaned=-not(Test-Path -LiteralPath $path);Path=$path}|ConvertTo-Json -Compress
