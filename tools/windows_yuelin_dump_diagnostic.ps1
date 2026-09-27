$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$cfg=Get-Content -Encoding UTF8 'C:\wwwroot\yuelinrhythm.top\wp-config.php'
$d=@{}
foreach($line in $cfg){if($line -match "define\(\s*'(?<k>DB_[A-Z]+)'\s*,\s*'(?<v>[^']*)'"){$d[$matches.k]=$matches.v}}
$dump='C:\BtSoft\mysql\MySQL5.5\bin\mysqldump.exe'
$version=[string](& $dump --version)
$shape=@('DB_NAME','DB_USER','DB_PASSWORD','DB_HOST')|ForEach-Object{[pscustomobject]@{Key=$_;Length=if($d[$_]){$d[$_].Length}else{0};StartsWithDash=if($d[$_]){$d[$_].StartsWith('-')}else{$false}}}
$arg='--defaults-extra-file="C:\temp\client.ini" --single-transaction --quick --routines --events --triggers --hex-blob --default-character-set=utf8mb4 --databases "'+$d.DB_NAME+'"'
[pscustomobject]@{Version=$version;Shape=$shape;ArgumentPreview=$arg}|ConvertTo-Json -Depth 4 -Compress
