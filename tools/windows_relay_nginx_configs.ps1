$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$files=@('C:\BtSoft\nginx\conf\vhost\quake.yuelinrhythm.top.conf','C:\BtSoft\nginx\conf\vhost\ws.yuelinrhythm.top.conf')
$rows=@()
foreach($file in $files){
  $rows+=[pscustomobject]@{File=$file;Lines=@(Get-Content -LiteralPath $file -Encoding UTF8|ForEach-Object{
    if($_ -match '^\s*ssl_certificate_key\s+'){'    ssl_certificate_key [configured];'}else{[string]$_}
  })}
}
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Configs=$rows}|ConvertTo-Json -Depth 5 -Compress
