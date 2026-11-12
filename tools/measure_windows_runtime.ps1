param([Parameter(Mandatory=$true)][int]$TargetProcessId,[int]$Seconds=70,[Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$cores=(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$rows=[Collections.Generic.List[object]]::new()
$gpuRows=[Collections.Generic.List[object]]::new()
$members=@($TargetProcessId)
$previousCpu=@{}
$previousGpu=@{}
$privateWorkingSet=$null
$watch=[Diagnostics.Stopwatch]::StartNew()
$previousTime=$null
$nextGpu=0.0
$root=Get-Process -Id $TargetProcessId
$identity=@{pid=$root.Id;path=$root.Path;started=$root.StartTime.ToString('o');mode='Profile';logicalProcessors=$cores}
while($watch.Elapsed.TotalSeconds -lt $Seconds) {
    $now=$watch.Elapsed.TotalSeconds
    $root=Get-Process -Id $TargetProcessId -ErrorAction Stop
    if($now -ge $nextGpu) {
        $processes=@(Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId)
        $members=@($TargetProcessId)
        do {
            $added=@($processes | Where-Object {$_.ParentProcessId -in $members -and $_.ProcessId -notin $members} | Select-Object -ExpandProperty ProcessId)
            $members+= $added
        } while($added.Count)
        try {$privateWorkingSet=(Get-CimInstance Win32_PerfRawData_PerfProc_Process -Filter "IDProcess=$TargetProcessId").WorkingSetPrivate} catch {$privateWorkingSet=$null}
        $engines=@()
        try {
            $engines=@(Get-CimInstance Win32_PerfRawData_GPUPerformanceCounters_GPUEngine | Where-Object {
                $_.Name -match '^pid_(\d+)_' -and [int]$Matches[1] -in $members
            })
        } catch {}
        $currentGpu=@{}
        $loads=@()
        foreach($engine in $engines) {
            $key=$engine.Name
            $currentGpu[$key]=@{running=[double]$engine.RunningTime;timestamp=[double]$engine.Timestamp_Sys100NS}
            if($previousGpu.ContainsKey($key)) {
                $elapsed=[double]$engine.Timestamp_Sys100NS-$previousGpu[$key].timestamp
                $running=[double]$engine.RunningTime-$previousGpu[$key].running
                if($elapsed -gt 0 -and $running -ge 0) {
                    $loads+=@{engine=$key;percent=[math]::Min([double]100,[double](100*$running/$elapsed))}
                }
            }
        }
        $previousGpu=$currentGpu
        $memory=@()
        try {
            $memory=@(Get-CimInstance Win32_PerfRawData_GPUPerformanceCounters_GPUProcessMemory | Where-Object {
                $_.Name -match '^pid_(\d+)_' -and [int]$Matches[1] -in $members
            } | ForEach-Object {@{name=$_.Name;dedicatedBytes=[double]$_.DedicatedUsage;sharedBytes=[double]$_.SharedUsage}})
        } catch {}
        $gpuRows.Add(@{seconds=$watch.Elapsed.TotalSeconds;loads=$loads;memory=$memory;counters=$currentGpu})
        $nextGpu=$watch.Elapsed.TotalSeconds+5
    }
    $now=$watch.Elapsed.TotalSeconds
    $currentCpu=@{}
    $usage=@()
    foreach($member in $members) {
        $p=Get-Process -Id $member -ErrorAction SilentlyContinue
        if($null -eq $p){continue}
        $cpu=$p.TotalProcessorTime.TotalSeconds
        $currentCpu[$member]=$cpu
        $percent=$null
        if($null -ne $previousTime -and $previousCpu.ContainsKey($member)) {
            $percent=100*($cpu-$previousCpu[$member])/($now-$previousTime)/$cores
        }
        $usage+=@{pid=$member;cpuPercent=$percent;cpuSeconds=$cpu;workingSetBytes=$p.WorkingSet64;privateBytes=$p.PrivateMemorySize64;threads=$p.Threads.Count;handles=$p.HandleCount;name=$p.ProcessName}
    }
    $rows.Add(@{seconds=$now;utc=[DateTimeOffset]::UtcNow.ToString('o');processes=$usage;rootPrivateWorkingSetBytes=$privateWorkingSet;rootPeakWorkingSetBytes=$root.PeakWorkingSet64;responding=$root.Responding})
    $previousCpu=$currentCpu
    $previousTime=$now
    Start-Sleep -Milliseconds 950
}
$result=@{identity=$identity;durationSeconds=$watch.Elapsed.TotalSeconds;samples=$rows;gpu=$gpuRows}
[IO.File]::WriteAllText($OutputPath,($result|ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false))
$main=@($rows | ForEach-Object {$_.processes | Where-Object pid -eq $TargetProcessId})
@{samples=$rows.Count;seconds=$watch.Elapsed.TotalSeconds;cpuMean=($main.cpuPercent|Measure-Object -Average).Average;cpuMax=($main.cpuPercent|Measure-Object -Maximum).Maximum;rssMeanMiB=($main.workingSetBytes|Measure-Object -Average).Average/1MB;rssMaxMiB=($main.workingSetBytes|Measure-Object -Maximum).Maximum/1MB;privateMeanMiB=($main.privateBytes|Measure-Object -Average).Average/1MB} | ConvertTo-Json
