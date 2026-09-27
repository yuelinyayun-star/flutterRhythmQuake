$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$keyRoot='C:\Users\Administrator\AppData\Local\Temp\rq-yuelin-migration-20260911'
$migrationRoot='C:\Users\Administrator\AppData\Local\Temp\rq-relay-migration-20260911'
$key=Join-Path $keyRoot 'transfer_ed25519'
$known=Join-Path $keyRoot 'target_known_hosts'
$archive=Join-Path $migrationRoot 'relay-services.tar.gz'
if(-not(Test-Path -LiteralPath $archive)){throw 'migration archive missing'}
& scp.exe -B -i $key -o ('UserKnownHostsFile='+$known) -o 'StrictHostKeyChecking=yes' -o 'IdentitiesOnly=yes' $archive 'root@64.90.20.78:/var/backups/rq-migration/'
if($LASTEXITCODE){throw ('scp failed '+$LASTEXITCODE)}
[pscustomobject]@{Transferred=$true;Name=(Get-Item $archive).Name;Length=(Get-Item $archive).Length;SHA256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash}|ConvertTo-Json -Compress
