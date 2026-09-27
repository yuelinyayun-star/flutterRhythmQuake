$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$r='C:\wwwroot\yuelinrhythm.top'
$names=@('index.php','index.html','composer.json','package.json','artisan','wp-load.php','wp-config.php','think','application','app','public','vendor')
$known=@(foreach($n in $names){$p=Join-Path $r $n;if(Test-Path -LiteralPath $p){$i=Get-Item -LiteralPath $p;[pscustomobject]@{Name=$n;Type=if($i.PSIsContainer){'dir'}else{'file'};Length=if($i.PSIsContainer){$null}else{$i.Length};Modified=$i.LastWriteTimeUtc}}})
$top=@(Get-ChildItem -LiteralPath $r -Force|ForEach-Object{[pscustomobject]@{Name=$_.Name;Type=if($_.PSIsContainer){'dir'}else{'file'};Length=if($_.PSIsContainer){$null}else{$_.Length};Modified=$_.LastWriteTimeUtc}})
$framework=[ordered]@{WordPress=(Test-Path (Join-Path $r 'wp-load.php'));Laravel=(Test-Path (Join-Path $r 'artisan'));Composer=(Test-Path (Join-Path $r 'composer.json'));Node=(Test-Path (Join-Path $r 'package.json'));ThinkPHP=(Test-Path (Join-Path $r 'think'))}
$manifest=@()
foreach($n in @('composer.json','package.json')){$p=Join-Path $r $n;if(Test-Path $p){try{$j=Get-Content -Raw -Encoding UTF8 $p|ConvertFrom-Json;$manifest+=[pscustomobject]@{File=$n;Name=$j.name;Description=$j.description;Dependencies=@($j.require.psobject.Properties.Name+$j.dependencies.psobject.Properties.Name)|Where-Object{$_}}}catch{}}}
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Root=$r;Framework=$framework;Known=$known;Top=$top;Manifest=$manifest}|ConvertTo-Json -Depth 6 -Compress
