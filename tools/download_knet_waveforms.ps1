param(
    [string]$ManifestPath = "tmp/knet_waveform_seed_download_manifest.json",
    [string]$OutputDirectory = "tmp/knet_downloads",
    [string]$Username = "",
    [string]$Password = "",
    [switch]$SkipExisting,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$manifestFile = if ([IO.Path]::IsPathRooted($ManifestPath)) {
    [IO.Path]::GetFullPath($ManifestPath)
} else {
    [IO.Path]::GetFullPath((Join-Path $workspace $ManifestPath))
}
$outputRoot = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    [IO.Path]::GetFullPath($OutputDirectory)
} else {
    [IO.Path]::GetFullPath((Join-Path $workspace $OutputDirectory))
}

if (-not (Test-Path -LiteralPath $manifestFile)) {
    throw "Manifest not found: $manifestFile"
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

$manifest = Get-Content -Raw -LiteralPath $manifestFile | ConvertFrom-Json
if ($manifest.schemaVersion -ne "knet_waveform_download_manifest_v1") {
    throw "Unsupported manifest schema: $($manifest.schemaVersion)"
}

if ([string]::IsNullOrWhiteSpace($Username)) {
    $Username = Read-Host "NIED username"
}
if ([string]::IsNullOrWhiteSpace($Username)) {
    throw "Username is required."
}

$securePassword = if ($DryRun) {
    ConvertTo-SecureString "dry-run" -AsPlainText -Force
} elseif (-not [string]::IsNullOrWhiteSpace($Password)) {
    ConvertTo-SecureString $Password -AsPlainText -Force
} else {
    Read-Host "NIED password (input hidden)" -AsSecureString
}
$credential = [Management.Automation.PSCredential]::new($Username, $securePassword)
$plainPassword = $credential.GetNetworkCredential().Password
$basicToken = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes("${Username}:${plainPassword}")
)
$plainPassword = $null

$targets = New-Object System.Collections.Generic.List[object]
foreach ($event in $manifest.events) {
    $eventId = [string]$event.eventId
    $eventTargets = $manifest.targetsByEventId.$eventId
    foreach ($target in $eventTargets) {
        $uri = [Uri]$target.url
        $fileName = [IO.Path]::GetFileName($uri.AbsolutePath)
        $eventDirectory = Join-Path $outputRoot $eventId
        $filePath = Join-Path $eventDirectory $fileName
        $targets.Add([pscustomobject]@{
            eventId = $eventId
            collection = [string]$target.collection
            format = [string]$target.format
            url = [string]$target.url
            outputPath = $filePath
        })
    }
}

$reportRecords = New-Object System.Collections.Generic.List[object]
$downloaded = 0
$skipped = 0
$failed = 0

foreach ($target in $targets) {
    $eventDirectory = Split-Path -Parent $target.outputPath
    New-Item -ItemType Directory -Path $eventDirectory -Force | Out-Null

    if ($DryRun) {
        $status = "dry_run"
        $bytes = 0
        $sha256 = $null
        $skipped++
    } elseif ($SkipExisting -and (Test-Path -LiteralPath $target.outputPath)) {
        $status = "existing"
        $bytes = (Get-Item -LiteralPath $target.outputPath).Length
        $sha256 = (Get-FileHash -LiteralPath $target.outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $skipped++
    } else {
        try {
            Invoke-WebRequest `
                -Uri $target.url `
                -OutFile $target.outputPath `
                -Headers @{
                    "User-Agent" = "Mozilla/5.0"
                    "Authorization" = "Basic $basicToken"
                } `
                -TimeoutSec 120

            $bytes = (Get-Item -LiteralPath $target.outputPath).Length
            $signature = if ($bytes -ge 4) {
                $raw = [IO.File]::ReadAllBytes($target.outputPath)
                [Text.Encoding]::ASCII.GetString($raw, 0, 4)
            } else {
                ""
            }
            if ($signature -ne "PK`u{0003}`u{0004}" -and $signature -ne "PK$([char]3)$([char]4)") {
                throw "Downloaded content is not a ZIP archive."
            }
            $sha256 = (Get-FileHash -LiteralPath $target.outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $status = "downloaded"
            $downloaded++
        } catch {
            if (Test-Path -LiteralPath $target.outputPath) {
                Remove-Item -LiteralPath $target.outputPath -Force
            }
            $status = "failed"
            $bytes = 0
            $sha256 = $null
            $failed++
            $errorMessage = $_.Exception.Message
        }
    }

    $record = [ordered]@{
        eventId = $target.eventId
        collection = $target.collection
        format = $target.format
        url = $target.url
        outputPath = $target.outputPath
        status = $status
        bytes = $bytes
        sha256 = $sha256
        downloadedAt = (Get-Date).ToString("o")
    }
    if ($status -eq "failed") {
        $record.error = $errorMessage
    }
    $reportRecords.Add($record)
}

$report = [ordered]@{
    schemaVersion = "knet_waveform_download_report_v1"
    createdAt = (Get-Date).ToString("o")
    manifestPath = $manifestFile
    outputDirectory = $outputRoot
    credentialUser = $Username
    credentialStored = $false
    dryRun = [bool]$DryRun
    targetCount = $targets.Count
    downloaded = $downloaded
    skipped = $skipped
    failed = $failed
    records = $reportRecords
}

$reportPath = Join-Path $outputRoot "download_report.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

[pscustomobject]@{
    Manifest = $manifestFile
    OutputDirectory = $outputRoot
    Targets = $targets.Count
    Downloaded = $downloaded
    Skipped = $skipped
    Failed = $failed
    Report = $reportPath
}

if ($failed -gt 0) {
    exit 2
}
