$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$php='C:\BtSoft\php\83\php.exe'
$version=[string](& $php -r 'echo PHP_VERSION;')
$modules=@(& $php -m|ForEach-Object{[string]$_}|Where-Object{$_ -and $_ -notmatch '^\['}|Sort-Object -Unique)
[pscustomobject]@{Version=$version;Modules=$modules}|ConvertTo-Json -Depth 3 -Compress
