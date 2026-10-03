param(
    [Parameter(Mandatory=$true)][int]$TargetPid,
    [int]$Samples = 30,
    [int]$IntervalSeconds = 2,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$rows = [System.Collections.Generic.List[object]]::new()
$previous = $null
for ($i = 0; $i -le $Samples; $i++) {
    $p = Get-Process -Id $TargetPid -ErrorAction Stop
    $io = Get-CimInstance Win32_Process -Filter "ProcessId=$TargetPid"
    $now = [DateTimeOffset]::UtcNow
    $current = [pscustomobject]@{
        timestamp = $now.ToString('o')
        cpuSeconds = $p.TotalProcessorTime.TotalSeconds
        workingSetBytes = $p.WorkingSet64
        privateBytes = $p.PrivateMemorySize64
        readBytes = [double]$io.ReadTransferCount
        writeBytes = [double]$io.WriteTransferCount
        responding = $p.Responding
    }
    if ($previous) {
        $elapsed = ($now - [DateTimeOffset]::Parse($previous.timestamp)).TotalSeconds
        $rows.Add([pscustomobject]@{
            raw = $current
            cpuPercent = ($current.cpuSeconds - $previous.cpuSeconds) / $elapsed / $cores * 100
            ioReadBytesPerSecond = ($current.readBytes - $previous.readBytes) / $elapsed
            ioWriteBytesPerSecond = ($current.writeBytes - $previous.writeBytes) / $elapsed
        })
    }
    $previous = $current
    if ($i -lt $Samples) { Start-Sleep -Seconds $IntervalSeconds }
}
# Process I/O includes network/device operations; do not label this physical disk I/O.
$result = [ordered]@{ pid=$TargetPid; logicalProcessors=$cores; samples=$rows }
$json = $result | ConvertTo-Json -Depth 7
[IO.File]::WriteAllText($OutputPath, $json, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    samples=$rows.Count
    cpuMean=($rows.cpuPercent | Measure-Object -Average).Average
    cpuMax=($rows.cpuPercent | Measure-Object -Maximum).Maximum
    workingSetMeanMB=(($rows | ForEach-Object {$_.raw.workingSetBytes} | Measure-Object -Average).Average / 1MB)
    workingSetMaxMB=(($rows | ForEach-Object {$_.raw.workingSetBytes} | Measure-Object -Maximum).Maximum / 1MB)
    ioWriteMeanBytesPerSecond=($rows.ioWriteBytesPerSecond | Measure-Object -Average).Average
} | ConvertTo-Json
