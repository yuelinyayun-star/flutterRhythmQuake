$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$roots=@('D:\KmaPewsRelay','D:\WAuthGateway')
$projects=@()
foreach($root in $roots){
  $files=@(Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop |
    Where-Object {$_.FullName -notmatch '\\(?:venv|\.venv|__pycache__|backup|logs?|acme|win-acme)(?:\\|$)'} |
    ForEach-Object {
      [pscustomobject]@{
        Relative=$_.FullName.Substring($root.Length).TrimStart('\')
        Length=$_.Length
        Modified=$_.LastWriteTimeUtc.ToString('o')
        SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
      }
    })
  $envNames=@(Get-ChildItem -LiteralPath $root -File -Recurse -Include '*.cmd','*.bat','*.ps1','.env','*.ini' |
    Where-Object {$_.FullName -notmatch '\\(?:venv|\.venv|backup)(?:\\|$)'} |
    ForEach-Object {
      $text=Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
      if($text){[regex]::Matches($text,'(?im)^\s*(?:set\s+|\$env:)?([A-Z][A-Z0-9_]{2,})\s*=')|ForEach-Object{$_.Groups[1].Value}}
    }|Sort-Object -Unique)
  $projects+=[pscustomobject]@{Root=$root;Files=$files;EnvironmentNames=$envNames}
}
$tasks=@(Get-ScheduledTask -TaskName 'KMA PEWS Relay','WAuth Gateway'|ForEach-Object{
  $task=$_;$info=Get-ScheduledTaskInfo -InputObject $task
  [pscustomobject]@{Name=$_.TaskName;State=[string]$_.State;LastRun=$info.LastRunTime;LastResult=$info.LastTaskResult;
    Actions=@($_.Actions|ForEach-Object{[pscustomobject]@{Executable=$_.Execute;WorkingDirectory=$_.WorkingDirectory;
      ArgumentFiles=@([regex]::Matches([string]$_.Arguments,'(?i)[A-Z]:\\[^"\r\n]+?\.(?:cmd|bat|ps1|py)')|ForEach-Object{$_.Value})}})}
})
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Projects=$projects;Tasks=$tasks}|ConvertTo-Json -Depth 7 -Compress
