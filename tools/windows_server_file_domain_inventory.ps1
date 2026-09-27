$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$path='C:\BtSoft\nginx\conf\nginx.conf'
$lines=@(Get-Content -LiteralPath $path -Encoding UTF8)
$indexes=@(for($i=0;$i -lt $lines.Count;$i++){if($lines[$i] -match 'file\.yuelinrhythm\.top'){ $i }})
$blocks=@()
foreach($index in $indexes){
  $start=[Math]::Max(0,$index-20)
  $end=[Math]::Min($lines.Count-1,$index+35)
  $blocks+=@($lines[$start..$end] | Where-Object {$_ -notmatch '^\s*(#|$)'})
}
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Path=$path;Blocks=$blocks}|ConvertTo-Json -Depth 4 -Compress
