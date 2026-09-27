$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$names=@('WAUTH_CLIENT_SECRET','WAUTH_CLIENT_ID','WAUTH_REDIRECT_URI','WAUTH_STATE_TTL_SECONDS','WAUTH_MAX_PENDING','KMA_RELAY_TOKEN')
$rows=@()
foreach($name in $names){
  $value=[Environment]::GetEnvironmentVariable($name,'Machine')
  if($null -eq $value){$value=[Environment]::GetEnvironmentVariable($name,'User')}
  $hash=$null
  if($null -ne $value){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))|ForEach-Object{$_.ToString('x2')})-join''}finally{$sha.Dispose()}
  }
  $rows+=[pscustomobject]@{Name=$name;Present=$null-ne$value;Length=if($null-ne$value){$value.Length}else{0};SHA256=$hash}
}
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Variables=$rows}|ConvertTo-Json -Depth 4 -Compress
