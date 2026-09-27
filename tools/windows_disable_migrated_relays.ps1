$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$names=@('KMA PEWS Relay','WAuth Gateway')
$before=@(Get-ScheduledTask -TaskName $names|ForEach-Object{[pscustomobject]@{Name=$_.TaskName;State=[string]$_.State}})
foreach($name in $names){
  Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
  Disable-ScheduledTask -TaskName $name|Out-Null
}
Start-Sleep -Seconds 5
$after=@(Get-ScheduledTask -TaskName $names|ForEach-Object{[pscustomobject]@{Name=$_.TaskName;State=[string]$_.State;Enabled=$_.Settings.Enabled}})
$listeners=@(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue|Where-Object{$_.LocalPort -in 8765,8787}|Select-Object LocalAddress,LocalPort,OwningProcess)
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Before=$before;After=$after;Listeners=$listeners}|ConvertTo-Json -Depth 5 -Compress
