$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$r='C:\wwwroot\yuelinrhythm.top'
$v=(Get-Content -Encoding UTF8 (Join-Path $r 'wp-includes\version.php')|Where-Object{$_ -match '^\s*\$wp_version\s*='}|Select-Object -First 1)
$themes=@(Get-ChildItem -LiteralPath (Join-Path $r 'wp-content\themes') -Directory -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name)
$plugins=@(Get-ChildItem -LiteralPath (Join-Path $r 'wp-content\plugins') -Directory -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Name)
$cfg=Get-Content -Raw -Encoding UTF8 (Join-Path $r 'wp-config.php')
function D($n){$p='define\(\s*[''\"]'+[regex]::Escape($n)+'[''\"]\s*,\s*[''\"]([^''\"]+)[''\"]';$m=[regex]::Match($cfg,$p);if($m.Success){$m.Groups[1].Value}else{$null}}
$rewrite=@(Get-ChildItem 'C:\BtSoft\nginx\conf\rewrite\yuelinrhythm.top' -File -ErrorAction SilentlyContinue|ForEach-Object{[pscustomobject]@{Name=$_.Name;Lines=@(Get-Content -Encoding UTF8 $_.FullName|Where-Object{$_ -notmatch '^\s*(#|$)'})}})
$proxy=@(Get-ChildItem 'C:\BtSoft\nginx\conf\proxy\yuelinrhythm.top' -File -ErrorAction SilentlyContinue|Select-Object Name,Length)
[pscustomobject]@{VersionLine=$v;Themes=$themes;Plugins=$plugins;DbName=(D 'DB_NAME');DbHost=(D 'DB_HOST');Rewrite=$rewrite;Proxy=$proxy}|ConvertTo-Json -Depth 6 -Compress
