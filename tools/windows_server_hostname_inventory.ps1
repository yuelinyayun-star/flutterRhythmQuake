$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$roots=@('C:\BtSoft\nginx\conf','D:\KmaPewsRelay','D:\WAuthGateway')
$results=@()
foreach($root in $roots){
  if(-not(Test-Path -LiteralPath $root)){continue}
  Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {$_.Length -lt 2MB -and $_.Extension -in '.conf','.json','.xml','.ini','.py','.ps1','.bat','.cmd','.txt','.md'} |
    ForEach-Object {
      $file=$_.FullName
      try{$text=Get-Content -LiteralPath $file -Raw -Encoding UTF8 -ErrorAction Stop}catch{return}
      if($null -eq $text){return}
      $names=@([regex]::Matches($text,'(?i)(?:[a-z0-9*_-]+\.)*yuelinrhythm\.top') | ForEach-Object {$_.Value.ToLowerInvariant()} | Sort-Object -Unique)
      if($names.Count){$results+=[pscustomobject]@{File=$file;Names=$names}}
    }
}
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');References=$results;UniqueNames=@($results.Names|Sort-Object -Unique)}|ConvertTo-Json -Depth 5 -Compress
