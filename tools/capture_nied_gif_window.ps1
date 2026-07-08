param(
    [Parameter(Mandatory = $true)]
    [string]$OriginTime,

    [Parameter(Mandatory = $true)]
    [string]$CaseId,

    [int]$PreSeconds = 30,
    [int]$PostSeconds = 120,
    [double]$Latitude = [double]::NaN,
    [double]$Longitude = [double]::NaN,
    [double]$DepthKm = [double]::NaN,
    [double]$Magnitude = [double]::NaN,
    [string]$Region = "",
    [string]$TruthSource = "",
    [string]$DecoderVersion = "nied_gif_layered_v2",
    [string]$StationDbVersion = "kanameishi_niedsitepub_1749_v1",
    [string]$SensorSelectionPolicy = "surface_jma_s_primary_v1",
    [string]$Layers = "jma_s,jma_b,acmap_s,acmap_b,vcmap_s,vcmap_b,dcmap_s,dcmap_b",
    [string]$OutputRoot = "tmp/captures",
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

if ($PreSeconds -lt 0 -or $PostSeconds -lt 0) {
    throw "PreSeconds and PostSeconds must be non-negative."
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
$layerList = @($Layers.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($layer in $layerList) {
    if ($allowedLayers -notcontains $layer) {
        throw "Unsupported NIED layer: $layer"
    }
}
if ($OriginTime -notmatch "(Z|[+-][0-9]{2}:[0-9]{2})$") {
    throw "OriginTime must include an explicit UTC offset, for example 2026-06-20T22:55:39+08:00."
}
try {
    $origin = [DateTimeOffset]::Parse(
        $OriginTime,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None
    )
} catch {
    throw "OriginTime is not a valid ISO 8601 timestamp: $OriginTime"
}
$originTimeJst = $origin.ToOffset([TimeSpan]::FromHours(9))
if ($CaseId -notmatch "^[A-Za-z0-9_-]+$") {
    throw "CaseId may contain only letters, numbers, underscores, and hyphens."
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

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$startTime = $originTimeJst.AddSeconds(-$PreSeconds)
$endTime = $originTimeJst.AddSeconds($PostSeconds)
if ($ValidateOnly) {
    [pscustomobject]@{
        OriginTimeInput = $origin.ToString("o")
        OriginTimeJst = $originTimeJst.ToString("yyyy-MM-ddTHH:mm:sszzz")
        StartTimeJst = $startTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
        EndTimeJst = $endTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
    return
}
$client = [Net.WebClient]::new()
$client.Headers["User-Agent"] = "Mozilla/5.0"
$records = [Collections.Generic.List[object]]::new()
$downloaded = 0
$failed = 0

try {
    for ($time = $startTime; $time -le $endTime; $time = $time.AddSeconds(1)) {
        $stamp = $time.ToString("yyyyMMddHHmmss")
        $date = $time.ToString("yyyyMMdd")
        foreach ($layer in $layerList) {
            $fileName = "$stamp.$layer.gif"
            $filePath = Join-Path $outputDirectory $fileName
            $url = "https://smi.lmoniexp.bosai.go.jp/data/map_img/RealTimeImg/$layer/$date/$fileName"
            $retrievalStartedAt = Get-Date
            try {
                $cacheStatus = if (Test-Path -LiteralPath $filePath) { "existing" } else { "downloaded" }
                if (-not (Test-Path -LiteralPath $filePath)) {
                    $client.DownloadFile($url, $filePath)
                }
                $retrievedAt = Get-Date
                $bytes = [IO.File]::ReadAllBytes($filePath)
                $signature = if ($bytes.Length -ge 6) {
                    [Text.Encoding]::ASCII.GetString($bytes, 0, 6)
                } else {
                    ""
                }
                if ($signature -notlike "GIF8*") {
                    throw "Downloaded content is not a GIF."
                }
                $records.Add([ordered]@{
                    timeJst = $time.ToString("yyyy-MM-ddTHH:mm:ss")
                    observedAt = $time.ToString("yyyy-MM-ddTHH:mm:sszzz")
                    receivedAt = $null
                    retrievedAt = $retrievedAt.ToString("o")
                    retrievalDurationMs = [math]::Round(($retrievedAt - $retrievalStartedAt).TotalMilliseconds, 3)
                    cacheStatus = $cacheStatus
                    layer   = $layer
                    file    = $fileName
                    bytes   = $bytes.Length
                    sha256  = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
                    ok      = $true
                    qualityFlags = @()
                    url     = $url
                })
                $downloaded++
            } catch {
                if (Test-Path -LiteralPath $filePath) {
                    Remove-Item -LiteralPath $filePath -Force
                }
                $records.Add([ordered]@{
                    timeJst = $time.ToString("yyyy-MM-ddTHH:mm:ss")
                    observedAt = $time.ToString("yyyy-MM-ddTHH:mm:sszzz")
                    receivedAt = $null
                    retrievedAt = (Get-Date).ToString("o")
                    retrievalDurationMs = [math]::Round(((Get-Date) - $retrievalStartedAt).TotalMilliseconds, 3)
                    cacheStatus = "failed"
                    layer   = $layer
                    file    = $fileName
                    bytes   = 0
                    ok      = $false
                    qualityFlags = @("missing", "retrieval_failed")
                    url     = $url
                    error   = $_.Exception.Message
                })
                $failed++
            }
        }
    }

    try {
        $client.DownloadFile(
            "https://weather-kyoshin.east.edge.storage-yahoo.jp/SiteList/sitelist.json",
            (Join-Path $outputDirectory "sitelist.json")
        )
    } catch {
        Write-Warning "Failed to download Yahoo sitelist: $($_.Exception.Message)"
    }
} finally {
    $client.Dispose()
}

function Optional-Number([double]$Value) {
    if ([double]::IsNaN($Value)) { return $null }
    return $Value
}

$manifest = [ordered]@{
    schemaVersion = 2
    capturedAt = (Get-Date).ToString("o")
    caseId = $CaseId
    event = [ordered]@{
        originTimeInput = $origin.ToString("o")
        originTimeJst = $originTimeJst.ToString("yyyy-MM-ddTHH:mm:sszzz")
        latitude = Optional-Number $Latitude
        longitude = Optional-Number $Longitude
        depthKm = Optional-Number $DepthKm
        magnitude = Optional-Number $Magnitude
        region = $Region
        truthSource = $TruthSource
    }
    startTimeJst = $startTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
    endTimeJst = $endTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
    expectedGifCount = (($PreSeconds + $PostSeconds + 1) * $layerList.Count)
    layers = $layerList
    expectedFrameIntervalMs = 1000
    decoderVersion = $DecoderVersion
    stationDbVersion = $StationDbVersion
    sensorSelectionPolicy = $SensorSelectionPolicy
    receivedAtStatus = "unavailable_historical_fetch"
    downloadedGifCount = $downloaded
    failedGifCount = $failed
    records = $records
}

$manifest |
    ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $outputDirectory "capture_manifest.json") -Encoding UTF8

[pscustomobject]@{
    Directory = $outputDirectory
    Downloaded = $downloaded
    Failed = $failed
    GifFiles = (Get-ChildItem -LiteralPath $outputDirectory -Filter "*.gif" -File).Count
}

if ($failed -gt 0) {
    exit 2
}
