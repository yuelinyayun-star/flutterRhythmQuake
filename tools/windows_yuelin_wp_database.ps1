$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$cfg=Get-Content -Encoding UTF8 'C:\wwwroot\yuelinrhythm.top\wp-config.php'
$d=@{}
foreach($line in $cfg){if($line -match "define\(\s*'(?<k>DB_[A-Z]+)'\s*,\s*'(?<v>[^']*)'"){$d[$matches.k]=$matches.v}}
$tools=@()
foreach($x in Get-ChildItem -LiteralPath 'C:\BtSoft\mysql' -Directory -ErrorAction SilentlyContinue){$p=Join-Path $x.FullName 'bin\mysqldump.exe';if(Test-Path -LiteralPath $p){$tools+=$p}}
[pscustomobject]@{DbName=$d.DB_NAME;DbHost=$d.DB_HOST;HasUser=[bool]$d.DB_USER;HasPassword=[bool]$d.DB_PASSWORD;DumpTools=$tools}|ConvertTo-Json -Depth 3 -Compress
