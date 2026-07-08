param(
    [Parameter(Mandatory = $true)]
    [string]$CaseId,

    [int]$DurationSeconds = 900,
    [int]$DataLagSeconds = 3,
    [int]$FrameAvailabilityTimeoutSeconds = 15,
    [int]$PollIntervalMs = 250,
    [int]$LateThresholdMs = 5000,
    [string]$DecoderVersion = "nied_gif_layered_v2",
    [string]$StationDbVersion = "kanameishi_niedsitepub_1749_v1",
    [string]$SensorSelectionPolicy = "surface_jma_s_primary_v1",
    [string[]]$Layers = @(
        "jma_s", "jma_b",
        "acmap_s", "acmap_b",
        "vcmap_s", "vcmap_b",
        "dcmap_s", "dcmap_b"
    ),
    [string]$OutputRoot = "tmp/captures"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

if ($CaseId -notmatch "^[A-Za-z0-9_-]+$") {
    throw "CaseId may contain only letters, numbers, underscores, and hyphens."
}
if ($DurationSeconds -le 0) {
    throw "DurationSeconds must be positive."
}
if ($DataLagSeconds -lt 0) {
    throw "DataLagSeconds must be non-negative."
}
if ($FrameAvailabilityTimeoutSeconds -le 0) {
    throw "FrameAvailabilityTimeoutSeconds must be positive."
}
if ($PollIntervalMs -lt 50) {
    throw "PollIntervalMs must be at least 50."
}
$allowedLayers = @(
    "jma_s", "jma_b",
    "acmap_s", "acmap_b",
    "vcmap_s", "vcmap_b",
    "dcmap_s", "dcmap_b",
    "rsp0125_s", "rsp0125_b",
    "rsp0250_s", "rsp0250_b",
    "rsp0500_s", "rsp0500_b",
    "rsp1000_s", "rsp1000_b",
    "rsp2000_s", "rsp2000_b",
    "rsp4000_s", "rsp4000_b"
)
$layerList = @(
    ($Layers -join ",") -split "[,\s]+" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
foreach ($layer in $layerList) {
    if ($allowedLayers -notcontains $layer) {
        throw "Unsupported NIED layer: $layer"
    }
}

$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outputBase = if ([IO.Path]::IsPathRooted($OutputRoot)) {
    [IO.Path]::GetFullPath($OutputRoot)
} else {
    [IO.Path]::GetFullPath((Join-Path $workspace $OutputRoot))
}
$outputDirectory = [IO.Path]::GetFullPath((Join-Path $outputBase $CaseId))

if (-not $outputDirectory.StartsWith($outputBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Resolved output directory escaped OutputRoot."
}
if (Test-Path -LiteralPath $outputDirectory) {
    $existingItems = @(Get-ChildItem -LiteralPath $outputDirectory -Force)
    if ($existingItems.Count -gt 0) {
        throw "Live capture requires a new or empty output directory: $outputDirectory"
    }
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$jstOffset = [TimeSpan]::FromHours(9)
$nowJst = [DateTimeOffset]::UtcNow.ToOffset($jstOffset)
$alignedNowJst = [DateTimeOffset]::new(
    $nowJst.Year,
    $nowJst.Month,
    $nowJst.Day,
    $nowJst.Hour,
    $nowJst.Minute,
    $nowJst.Second,
    $jstOffset
)
$startTime = $alignedNowJst.AddSeconds(-$DataLagSeconds)
$endTime = $startTime.AddSeconds($DurationSeconds - 1)
$captureStartedAt = [DateTimeOffset]::UtcNow
$records = [Collections.Generic.List[object]]::new()
$downloaded = 0
$failed = 0
$completedTimestamps = 0
$captureInProgress = $true
$captureError = $null
$layers = $layerList

$client = [Net.WebClient]::new()
$client.Headers["User-Agent"] = "Mozilla/5.0"
$httpClient = [Net.Http.HttpClient]::new()
$httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0")
$perRequestTimeoutSeconds = [math]::Max(
    1,
    [math]::Min(5, $FrameAvailabilityTimeoutSeconds)
)
$httpClient.Timeout = [TimeSpan]::FromSeconds($perRequestTimeoutSeconds)

function Write-CaptureManifest {
    param([bool]$InProgress)

    $manifest = [ordered]@{
        schemaVersion = 3
        captureMode = "live"
        capturedAt = [DateTimeOffset]::UtcNow.ToString("o")
        captureStartedAt = $captureStartedAt.ToString("o")
        captureInProgress = $InProgress
        captureError = $captureError
        caseId = $CaseId
        startTimeJst = $startTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
        endTimeJst = $endTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
        expectedTimestampCount = $DurationSeconds
        completedTimestampCount = $completedTimestamps
        expectedGifCount = ($DurationSeconds * $layers.Count)
        expectedFrameIntervalMs = 1000
        decoderVersion = $DecoderVersion
        stationDbVersion = $StationDbVersion
        sensorSelectionPolicy = $SensorSelectionPolicy
        layers = $layers
        receivedAtStatus = "observed_live_fetch_completion"
        dataLagSeconds = $DataLagSeconds
        frameAvailabilityTimeoutSeconds = $FrameAvailabilityTimeoutSeconds
        pollIntervalMs = $PollIntervalMs
        lateThresholdMs = $LateThresholdMs
        clock = [ordered]@{
            source = "local_system_clock"
            synchronized = $false
            offsetCorrectionMs = $null
        }
        downloadedGifCount = $downloaded
        failedGifCount = $failed
        records = $records
    }

    $temporaryPath = Join-Path $outputDirectory "capture_manifest.json.tmp"
    $manifest |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath `
        -Destination (Join-Path $outputDirectory "capture_manifest.json") `
        -Force
}

function Repair-FailedRecords {
    for ($index = 0; $index -lt $records.Count; $index++) {
        $record = $records[$index]
        if ($record.ok) {
            continue
        }

        $lastError = $record.error
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $requestStartedAt = [DateTimeOffset]::UtcNow
            try {
                $bytes = $client.DownloadData($record.url)
                $receivedAt = [DateTimeOffset]::UtcNow
                $signature = if ($bytes.Length -ge 6) {
                    [Text.Encoding]::ASCII.GetString($bytes, 0, 6)
                } else {
                    ""
                }
                if ($signature -notlike "GIF8*") {
                    throw "Downloaded content is not a GIF."
                }

                $filePath = Join-Path $outputDirectory $record.file
                [IO.File]::WriteAllBytes($filePath, $bytes)
                $observedAt = [DateTimeOffset]::Parse($record.observedAt)
                $receiveDelayMs = [math]::Round(
                    ($receivedAt - $observedAt.ToUniversalTime()).TotalMilliseconds,
                    3
                )
                $qualityFlags = [Collections.Generic.List[string]]::new()
                $qualityFlags.Add("clock_unsynchronized")
                $qualityFlags.Add("repaired_after_initial_failure")
                if ($receiveDelayMs -gt $LateThresholdMs) {
                    $qualityFlags.Add("late")
                }

                $record.requestStartedAt = $requestStartedAt.ToString("o")
                $record.receivedAt = $receivedAt.ToString("o")
                $record.retrievedAt = $receivedAt.ToString("o")
                $record.retrievalDurationMs = [math]::Round(
                    ($receivedAt - $requestStartedAt).TotalMilliseconds,
                    3
                )
                $record.receiveDelayMs = $receiveDelayMs
                $record.attempts = $record.attempts + $attempt
                $record.cacheStatus = "downloaded_live_repair"
                $record.bytes = $bytes.Length
                $record.sha256 = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
                $record.ok = $true
                $record.qualityFlags = $qualityFlags
                $record.error = $null
                $downloaded++
                $failed--
                break
            } catch {
                $lastError = $_.Exception.Message
                $record.error = $lastError
                if ($attempt -lt 3) {
                    Start-Sleep -Milliseconds $PollIntervalMs
                }
            }
        }
    }
}

try {
    try {
        $client.DownloadFile(
            "https://weather-kyoshin.east.edge.storage-yahoo.jp/SiteList/sitelist.json",
            (Join-Path $outputDirectory "sitelist.json")
        )
    } catch {
        Write-Warning "Failed to download Yahoo sitelist: $($_.Exception.Message)"
    }

    Write-CaptureManifest -InProgress $true

    for ($time = $startTime; $time -le $endTime; $time = $time.AddSeconds(1)) {
        $stamp = $time.ToString("yyyyMMddHHmmss")
        $date = $time.ToString("yyyyMMdd")
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds($FrameAvailabilityTimeoutSeconds)
        $pending = [Collections.Generic.HashSet[string]]::new([string[]]$layers)
        $state = @{}

        foreach ($layer in $layers) {
            $fileName = "$stamp.$layer.gif"
            $state[$layer] = [ordered]@{
                fileName = $fileName
                filePath = Join-Path $outputDirectory $fileName
                url = "https://smi.lmoniexp.bosai.go.jp/data/map_img/RealTimeImg/$layer/$date/$fileName"
                attempts = 0
                firstRequestStartedAt = $null
                lastError = $null
            }
        }

        while ($pending.Count -gt 0 -and [DateTimeOffset]::UtcNow -le $deadline) {
            $requests = @()
            foreach ($layer in @($pending)) {
                $layerState = $state[$layer]
                $requestStartedAt = [DateTimeOffset]::UtcNow
                $layerState.attempts++
                if ($null -eq $layerState.firstRequestStartedAt) {
                    $layerState.firstRequestStartedAt = $requestStartedAt
                }
                $requests += [pscustomobject]@{
                    layer = $layer
                    requestStartedAt = $requestStartedAt
                    task = $httpClient.GetByteArrayAsync($layerState.url)
                }
            }

            $remainingMs = [math]::Max(
                1,
                [int][math]::Ceiling(($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
            )
            $taskArray = [Threading.Tasks.Task[]]@($requests | ForEach-Object { $_.task })
            try {
                [void][Threading.Tasks.Task]::WaitAll($taskArray, $remainingMs)
            } catch [AggregateException] {
                # Individual task errors are recorded below; the timestamp-level
                # retry window remains open until the deadline.
            }

            foreach ($request in $requests) {
                if (-not $pending.Contains($request.layer)) {
                    continue
                }
                $task = $request.task
                $layerState = $state[$request.layer]
                if ($task.Status -ne [Threading.Tasks.TaskStatus]::RanToCompletion) {
                    if ($task.IsFaulted -and $task.Exception) {
                        $layerState.lastError = $task.Exception.GetBaseException().Message
                    } elseif ($task.IsCanceled) {
                        $layerState.lastError = "Request canceled or timed out."
                    } else {
                        $layerState.lastError = "Request did not complete before retry deadline."
                    }
                    continue
                }

                try {
                    $bytes = $task.Result
                    $receivedAt = [DateTimeOffset]::UtcNow
                    $signature = if ($bytes.Length -ge 6) {
                        [Text.Encoding]::ASCII.GetString($bytes, 0, 6)
                    } else {
                        ""
                    }
                    if ($signature -notlike "GIF8*") {
                        throw "Downloaded content is not a GIF."
                    }

                    [IO.File]::WriteAllBytes($layerState.filePath, $bytes)
                    $receiveDelayMs = [math]::Round(
                        ($receivedAt - $time.ToUniversalTime()).TotalMilliseconds,
                        3
                    )
                    $qualityFlags = [Collections.Generic.List[string]]::new()
                    $qualityFlags.Add("clock_unsynchronized")
                    if ($receiveDelayMs -gt $LateThresholdMs) {
                        $qualityFlags.Add("late")
                    }

                    $records.Add([ordered]@{
                        timeJst = $time.ToString("yyyy-MM-ddTHH:mm:ss")
                        observedAt = $time.ToString("yyyy-MM-ddTHH:mm:sszzz")
                        requestStartedAt = $layerState.firstRequestStartedAt.ToString("o")
                        receivedAt = $receivedAt.ToString("o")
                        retrievedAt = $receivedAt.ToString("o")
                        retrievalDurationMs = [math]::Round(
                            ($receivedAt - $request.requestStartedAt).TotalMilliseconds,
                            3
                        )
                        receiveDelayMs = $receiveDelayMs
                        attempts = $layerState.attempts
                        cacheStatus = "downloaded_live"
                        layer = $request.layer
                        file = $layerState.fileName
                        bytes = $bytes.Length
                        sha256 = (Get-FileHash -LiteralPath $layerState.filePath -Algorithm SHA256).Hash.ToLowerInvariant()
                        ok = $true
                        qualityFlags = $qualityFlags
                        url = $layerState.url
                    })
                    $downloaded++
                    [void]$pending.Remove($request.layer)
                } catch {
                    $layerState.lastError = $_.Exception.Message
                }
            }

            if ($pending.Count -gt 0 -and
                [DateTimeOffset]::UtcNow.AddMilliseconds($PollIntervalMs) -le $deadline) {
                Start-Sleep -Milliseconds $PollIntervalMs
            }
        }

        foreach ($layer in @($pending)) {
            $layerState = $state[$layer]
            $records.Add([ordered]@{
                timeJst = $time.ToString("yyyy-MM-ddTHH:mm:ss")
                observedAt = $time.ToString("yyyy-MM-ddTHH:mm:sszzz")
                requestStartedAt = if ($null -eq $layerState.firstRequestStartedAt) {
                    $null
                } else {
                    $layerState.firstRequestStartedAt.ToString("o")
                }
                receivedAt = $null
                retrievedAt = [DateTimeOffset]::UtcNow.ToString("o")
                retrievalDurationMs = $null
                receiveDelayMs = $null
                attempts = $layerState.attempts
                cacheStatus = "failed"
                layer = $layer
                file = $layerState.fileName
                bytes = 0
                sha256 = $null
                ok = $false
                qualityFlags = @("missing", "retrieval_failed", "clock_unsynchronized")
                url = $layerState.url
                error = $layerState.lastError
            })
            $failed++
        }

        $completedTimestamps++
        Write-CaptureManifest -InProgress $true
    }
    Repair-FailedRecords
} catch {
    $captureError = $_.Exception.Message
    throw
} finally {
    $captureInProgress = $false
    $client.Dispose()
    $httpClient.Dispose()
    Write-CaptureManifest -InProgress $false
}

[pscustomobject]@{
    Directory = $outputDirectory
    StartTimeJst = $startTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
    EndTimeJst = $endTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
    Downloaded = $downloaded
    Failed = $failed
    GifFiles = (Get-ChildItem -LiteralPath $outputDirectory -Filter "*.gif" -File).Count
}

if ($failed -gt 0) {
    exit 2
}
