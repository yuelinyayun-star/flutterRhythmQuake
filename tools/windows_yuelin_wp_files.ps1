$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$r='C:\wwwroot\yuelinrhythm.top'
$v=Get-Content -Encoding UTF8 (Join-Path $r 'wp-includes\version.php')|Where-Object{$_ -match '^\s*\$wp_version\s*='}|Select-Object -First 1
$t=@(Get-ChildItem -LiteralPath (Join-Path $r 'wp-content\themes') -Directory|Select-Object -ExpandProperty Name)
$p=@(Get-ChildItem -LiteralPath (Join-Path $r 'wp-content\plugins') -Directory|Select-Object -ExpandProperty Name)
[pscustomobject]@{Version=$v;Themes=$t;Plugins=$p}|ConvertTo-Json -Depth 4 -Compress
