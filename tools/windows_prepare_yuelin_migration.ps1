$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$root='C:\wwwroot\yuelinrhythm.top'
$stage='C:\Users\Administrator\AppData\Local\Temp\rq-yuelin-migration-20260911'
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$cfg=Get-Content -Encoding UTF8 (Join-Path $root 'wp-config.php')
$d=@{}
foreach($line in $cfg){if($line -match "define\(\s*'(?<k>DB_[A-Z]+)'\s*,\s*'(?<v>[^']*)'"){$d[$matches.k]=$matches.v}}
foreach($k in 'DB_NAME','DB_USER','DB_PASSWORD','DB_HOST'){if(-not $d[$k]){throw "Missing $k"}}
$dump='C:\BtSoft\mysql\MySQL5.5\bin\mysqldump.exe'
$sql=Join-Path $stage 'database.sql'
$err=Join-Path $stage 'dump-error.txt'
Remove-Item -LiteralPath $sql,$err -Force -ErrorAction SilentlyContinue
$psi=[Diagnostics.ProcessStartInfo]::new()
$psi.FileName=$dump
$psi.Arguments='--user="'+$d.DB_USER+'" --host="'+$d.DB_HOST+'" --single-transaction --quick --routines --events --triggers --hex-blob --default-character-set=utf8mb4 "'+$d.DB_NAME+'"'
$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$psi.EnvironmentVariables['MYSQL_PWD']=$d.DB_PASSWORD
$p=[Diagnostics.Process]::new();$p.StartInfo=$psi;[void]$p.Start()
$f=[IO.File]::Create($sql);$p.StandardOutput.BaseStream.CopyTo($f);$f.Close()
$errorText=$p.StandardError.ReadToEnd();$p.WaitForExit();$errorText|Set-Content -LiteralPath $err -Encoding UTF8
if($p.ExitCode -ne 0){throw ('mysqldump failed '+$p.ExitCode)}
$ssl=Join-Path $stage 'ssl';New-Item -ItemType Directory -Path $ssl -Force|Out-Null
Copy-Item 'C:\BtSoft\nginx\conf\ssl\yuelinrhythm.top\fullchain.pem' (Join-Path $ssl 'fullchain.pem') -Force
Copy-Item 'C:\BtSoft\nginx\conf\ssl\yuelinrhythm.top\privkey.pem' (Join-Path $ssl 'privkey.pem') -Force
$siteArc=Join-Path $stage 'site.tar.gz';$metaArc=Join-Path $stage 'database-and-ssl.tar.gz'
& tar.exe -czf $siteArc -C $root .
if($LASTEXITCODE){throw 'site tar failed'}
& tar.exe -czf $metaArc -C $stage 'database.sql' 'ssl'
if($LASTEXITCODE){throw 'meta tar failed'}
$result=@($siteArc,$metaArc)|ForEach-Object{$i=Get-Item -LiteralPath $_;[pscustomobject]@{Path=$_.ToString();Bytes=$i.Length;SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}}
Remove-Item -LiteralPath $sql,$err -Force -ErrorAction SilentlyContinue
$result|ConvertTo-Json -Depth 3 -Compress
