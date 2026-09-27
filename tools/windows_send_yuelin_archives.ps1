$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$d='C:\Users\Administrator\AppData\Local\Temp\rq-yuelin-migration-20260911'
$k=Join-Path $d 'transfer_ed25519';$h=Join-Path $d 'target_known_hosts'
$files=@((Join-Path $d 'site.tar.gz'),(Join-Path $d 'database-and-ssl.tar.gz'))
& scp.exe -B -v -i $k -o ('UserKnownHostsFile='+$h) -o 'StrictHostKeyChecking=yes' -o 'IdentitiesOnly=yes' @files 'root@64.90.20.78:/var/backups/rq-migration/'
if($LASTEXITCODE){throw ('scp failed '+$LASTEXITCODE)}
[pscustomobject]@{Transferred=$true;Files=@($files|ForEach-Object{(Get-Item $_).Name})}|ConvertTo-Json -Depth 3 -Compress
