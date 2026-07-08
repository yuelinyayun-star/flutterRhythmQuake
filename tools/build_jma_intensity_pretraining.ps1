param(
    [int[]]$Years = @(2020, 2021, 2022),
    [string]$OutputRoot = "tmp/jma_intensity_pretraining"
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
$tmpRoot = [IO.Path]::GetFullPath((Join-Path $outputBase "raw"))

if (-not $outputBase.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must remain inside the workspace."
}

New-Item -ItemType Directory -Path $outputBase -Force | Out-Null
New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null

$baseUrl = "https://www.data.jma.go.jp/eqev/data/bulletin/data/shindo"
$stationZip = Join-Path $tmpRoot "code_p.zip"
$stationDirectory = Join-Path $tmpRoot "stations"
if (-not (Test-Path -LiteralPath $stationZip)) {
    Invoke-WebRequest -Uri "$baseUrl/code_p.zip" -OutFile $stationZip
}
New-Item -ItemType Directory -Path $stationDirectory -Force | Out-Null
Expand-Archive -LiteralPath $stationZip -DestinationPath $stationDirectory -Force
$stationFile = Get-ChildItem -LiteralPath $stationDirectory -Filter "code_p.dat" -File |
    Select-Object -First 1
if ($null -eq $stationFile) {
    throw "code_p.dat was not found after extraction."
}

$results = [Collections.Generic.List[object]]::new()
foreach ($year in $Years) {
    $yearZip = Join-Path $tmpRoot "i$year.zip"
    $yearDirectory = Join-Path $tmpRoot "i$year"
    if (-not (Test-Path -LiteralPath $yearZip)) {
        Invoke-WebRequest -Uri "$baseUrl/i$year.zip" -OutFile $yearZip
    }
    New-Item -ItemType Directory -Path $yearDirectory -Force | Out-Null
    Expand-Archive -LiteralPath $yearZip -DestinationPath $yearDirectory -Force
    $yearFile = Get-ChildItem -LiteralPath $yearDirectory -Filter "i$year.dat" -File |
        Select-Object -First 1
    if ($null -eq $yearFile) {
        throw "i$year.dat was not found after extraction."
    }

    $outputFile = Join-Path $outputBase "jma_final_intensity_$year.json"
    & dart run tools/import_jma_intensity_archive.dart `
        --intensity $yearFile.FullName `
        --stations $stationFile.FullName `
        --output $outputFile `
        --year $year `
        --source-url "https://www.data.jma.go.jp/eqev/data/bulletin/shindo.html"
    if ($LASTEXITCODE -ne 0) {
        throw "JMA intensity import failed for $year."
    }
    $results.Add([pscustomobject]@{
        Year = $year
        Output = $outputFile
        Bytes = (Get-Item -LiteralPath $outputFile).Length
    })
}

$datasetArguments = [Collections.Generic.List[string]]::new()
foreach ($result in $results) {
    $datasetArguments.Add("--input")
    $datasetArguments.Add($result.Output)
}
$datasetArguments.Add("--output")
$datasetArguments.Add($outputBase)
& dart run tools/build_jma_intensity_dataset.dart @datasetArguments
if ($LASTEXITCODE -ne 0) {
    throw "JMA intensity dataset build failed."
}

$revealArguments = [Collections.Generic.List[string]]::new()
foreach ($result in $results) {
    $revealArguments.Add("--input")
    $revealArguments.Add($result.Output)
}
$revealArguments.Add("--splits")
$revealArguments.Add((Join-Path $outputBase "splits.json"))
$revealArguments.Add("--output")
$revealArguments.Add($outputBase)
& dart run tools/build_synthetic_reveal_dataset.dart @revealArguments
if ($LASTEXITCODE -ne 0) {
    throw "Synthetic reveal dataset build failed."
}

& dart run tools/train_static_intensity_baseline.dart `
    --train (Join-Path $outputBase "synthetic_reveal_train.json") `
    --validation (Join-Path $outputBase "synthetic_reveal_validation.json") `
    --output $outputBase
if ($LASTEXITCODE -ne 0) {
    throw "Static intensity attenuation training failed."
}

$results
