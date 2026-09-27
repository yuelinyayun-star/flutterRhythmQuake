$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$out=@()
foreach($d in @('C:\BtSoft\nginx\conf\rewrite\yuelinrhythm.top','C:\BtSoft\nginx\conf\proxy\yuelinrhythm.top')){if(Test-Path $d){$out+=Get-ChildItem -LiteralPath $d -File|ForEach-Object{[pscustomobject]@{Directory=$d;Name=$_.Name;Length=$_.Length;Lines=@(Get-Content -Encoding UTF8 $_.FullName|Where-Object{$_ -notmatch '^\s*(#|$)'})}}}}
$out|ConvertTo-Json -Depth 4 -Compress
