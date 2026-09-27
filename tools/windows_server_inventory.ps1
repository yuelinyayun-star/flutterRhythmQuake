$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
function ExecutableOnly([string]$command) {
    if ($command -match '^"([^"]+)"') { return $Matches[1] }
    if ($command -match '^(.*?\.(exe|com|bat|cmd|ps1))\b') { return $Matches[1] }
    return ($command -split '\s+')[0]
}
$os = Get-CimInstance Win32_OperatingSystem
$services = @(Get-CimInstance Win32_Service | ForEach-Object {
    [pscustomobject]@{Name=$_.Name;DisplayName=$_.DisplayName;State=$_.State;
        StartMode=$_.StartMode;ProcessId=$_.ProcessId;Account=$_.StartName;
        Executable=(ExecutableOnly $_.PathName)}
})
$processes = @(Get-CimInstance Win32_Process | ForEach-Object {
    $entryPoints = @([regex]::Matches([string]$_.CommandLine,
        '(?i)(?:[A-Z]:\\[^"\r\n]*?\.(?:py|ps1|js))(?=["\s]|$)|(?<=-m\s)[a-z_][a-z0-9_.]*') |
        ForEach-Object Value)
    [pscustomobject]@{Id=$_.ProcessId;ParentId=$_.ParentProcessId;Name=$_.Name;
        Executable=$_.ExecutablePath;EntryPoints=$entryPoints;
        WorkingSetMiB=[math]::Round($_.WorkingSetSize/1MB,2);Started=$_.CreationDate}
})
$listeners = @(Get-NetTCPConnection -State Listen | Sort-Object LocalPort,LocalAddress |
    ForEach-Object {
        $connection=$_
        [pscustomobject]@{Address=$_.LocalAddress;Port=$_.LocalPort;Pid=$_.OwningProcess;
            Process=($processes | Where-Object Id -eq $connection.OwningProcess | Select-Object -First 1).Name;
            Services=@($services | Where-Object ProcessId -eq $connection.OwningProcess | ForEach-Object Name)}
    })
$tasks = @(Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
    ForEach-Object {
        $task=$_
        $info=Get-ScheduledTaskInfo -InputObject $task -ErrorAction SilentlyContinue
        [pscustomobject]@{Name=$_.TaskName;Path=$_.TaskPath;State=[string]$_.State;
            Actions=@($_.Actions | ForEach-Object { [pscustomobject]@{Executable=$_.Execute;Directory=$_.WorkingDirectory} });
            LastRun=$info.LastRunTime;LastResult=$info.LastTaskResult;NextRun=$info.NextRunTime}
    })
[pscustomobject]@{
    CapturedAt=[DateTime]::UtcNow.ToString('o');Computer=$env:COMPUTERNAME;
    OS=$os.Caption;Version=$os.Version;LastBoot=$os.LastBootUpTime;
    MemoryTotalMiB=[math]::Round($os.TotalVisibleMemorySize/1024,2);
    MemoryFreeMiB=[math]::Round($os.FreePhysicalMemory/1024,2);
    ServiceCount=$services.Count;RunningServiceCount=@($services | Where-Object State -eq 'Running').Count;
    Services=$services;Processes=$processes;TcpListeners=$listeners;CustomScheduledTasks=$tasks
} | ConvertTo-Json -Depth 7 -Compress
