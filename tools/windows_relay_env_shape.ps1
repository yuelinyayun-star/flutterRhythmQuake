$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$files=@('D:\KmaPewsRelay\run_server.cmd','D:\WAuthGateway\run_server.cmd')
$result=@()
foreach($file in $files){
  $text=Get-Content -LiteralPath $file -Raw
  $vars=@([regex]::Matches($text,'(?im)^\s*set\s+"?([A-Z][A-Z0-9_]*)=(.*?)"?\s*$')|ForEach-Object{
    $value=$_.Groups[2].Value.TrimEnd('"')
    $bytes=[Text.Encoding]::UTF8.GetBytes($value)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=($sha.ComputeHash($bytes)|ForEach-Object{$_.ToString('x2')})-join''}finally{$sha.Dispose()}
    [pscustomobject]@{Name=$_.Groups[1].Value;Length=$value.Length;SHA256=$hash}
  })
  $result+=[pscustomobject]@{File=$file;Variables=$vars}
}
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Files=$result}|ConvertTo-Json -Depth 5 -Compress
