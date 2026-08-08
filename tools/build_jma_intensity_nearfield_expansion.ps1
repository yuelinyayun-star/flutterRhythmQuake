param(
    [int[]]$Years = @(2010..2019),
    [string]$OutputRoot = "tmp/jma_intensity_nearfield_expansion"
)

$ErrorActionPreference = "Stop"

if ($Years.Count -eq 0) {
    throw "At least one year is required."
}
if ($Years | Where-Object { $_ -lt 1919 -or $_ -gt 2022 }) {
    throw "JMA annual intensity archives currently cover 1919 through 2022."
}

$workspace = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outputBase = if ([IO.Path]::IsPathRooted($OutputRoot)) {
    [IO.Path]::GetFullPath($OutputRoot)
} else {
    [IO.Path]::GetFullPath((Join-Path $workspace $OutputRoot))
}
$rawRoot = [IO.Path]::GetFullPath((Join-Path $outputBase "raw"))

if (-not $outputBase.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must remain inside the workspace."
}

New-Item -ItemType Directory -Path $outputBase -Force | Out-Null
New-Item -ItemType Directory -Path $rawRoot -Force | Out-Null

$baseUrl = "https://www.data.jma.go.jp/eqev/data/bulletin/data/shindo"
$indexUrl = "https://www.data.jma.go.jp/eqev/data/bulletin/shindo.html"
$stationUrl = "$baseUrl/code_p.zip"
$stationZip = Join-Path $rawRoot "code_p.zip"
$stationDirectory = Join-Path $rawRoot "stations"
if (-not (Test-Path -LiteralPath $stationZip)) {
    Invoke-WebRequest -Uri $stationUrl -OutFile $stationZip
}
New-Item -ItemType Directory -Path $stationDirectory -Force | Out-Null
Expand-Archive -LiteralPath $stationZip -DestinationPath $stationDirectory -Force
$stationFile = Get-ChildItem -LiteralPath $stationDirectory -Filter "code_p.dat" -File |
    Select-Object -First 1
if ($null -eq $stationFile) {
    throw "code_p.dat was not found after extraction."
}

$entries = [Collections.Generic.List[object]]::new()
foreach ($year in ($Years | Sort-Object -Unique)) {
    $archiveUrl = "$baseUrl/i$year.zip"
    $yearZip = Join-Path $rawRoot "i$year.zip"
    $yearDirectory = Join-Path $rawRoot "i$year"
    if (-not (Test-Path -LiteralPath $yearZip)) {
        Invoke-WebRequest -Uri $archiveUrl -OutFile $yearZip
    }
    New-Item -ItemType Directory -Path $yearDirectory -Force | Out-Null
    Expand-Archive -LiteralPath $yearZip -DestinationPath $yearDirectory -Force
    $yearFile = Get-ChildItem -LiteralPath $yearDirectory -Filter "i$year.dat" -File |
        Select-Object -First 1
    if ($null -eq $yearFile) {
        throw "i$year.dat was not found after extraction."
    }

    $outputFile = Join-Path $outputBase "jma_final_intensity_$year.json"
    $importOutput = & dart run tools/import_jma_intensity_archive.dart `
        --intensity $yearFile.FullName `
        --stations $stationFile.FullName `
        --output $outputFile `
        --year $year `
        --source-url $archiveUrl 2>&1
    $importExitCode = $LASTEXITCODE
    $importOutput | Write-Output
    if ($importExitCode -ne 0) {
        throw "JMA intensity import failed for $year with exit code $importExitCode."
    }

    $importSummaryText = (@($importOutput) -join "").Trim()
    $importSummaryMatch = [regex]::Match($importSummaryText, '\{.*\}$')
    if (-not $importSummaryMatch.Success) {
        throw "JMA intensity import did not emit a summary for $year."
    }
    $imported = $importSummaryMatch.Value | ConvertFrom-Json
    $entries.Add([ordered]@{
        year = $year
        archiveUrl = $archiveUrl
        archiveSha256 = (Get-FileHash -LiteralPath $yearZip -Algorithm SHA256).Hash
        archiveBytes = (Get-Item -LiteralPath $yearZip).Length
        dataFile = $yearFile.FullName.Substring($workspace.Length + 1)
        dataBytes = $yearFile.Length
        outputFile = $outputFile.Substring($workspace.Length + 1)
        outputBytes = (Get-Item -LiteralPath $outputFile).Length
        eventCount = $imported.events
        observedStationCount = $imported.observedStations
        missingStationCount = $imported.missingStations
    })
}

$manifest = [ordered]@{
    schemaVersion = "jma_intensity_nearfield_expansion_v1"
    generatedAt = [DateTime]::UtcNow.ToString("o")
    officialIndexUrl = $indexUrl
    officialArchiveRange = [ordered]@{ firstYear = 1919; lastYear = 2022 }
    stationTable = [ordered]@{
        url = $stationUrl
        archiveSha256 = (Get-FileHash -LiteralPath $stationZip -Algorithm SHA256).Hash
        archiveBytes = (Get-Item -LiteralPath $stationZip).Length
        dataFile = $stationFile.FullName.Substring($workspace.Length + 1)
        dataBytes = $stationFile.Length
    }
    predeclaredEvaluationPolicy = [ordered]@{
        calibrationYears = @(2010..2016)
        validationYears = @(2017)
        frozenYears = @(2018)
        previouslyOpenedAuditYears = @(2019, 2020, 2021, 2022)
        frozenRule = "do_not_compute_model_residuals_or_candidate_scores_before_model_selection"
    }
    years = $entries
}

$manifestPath = Join-Path $outputBase "archive_manifest.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
$entries | ForEach-Object {
    [pscustomobject]@{
        Year = $_.year
        Events = $_.eventCount
        ObservedStations = $_.observedStationCount
        MissingStations = $_.missingStationCount
        ArchiveSha256 = $_.archiveSha256
    }
}
