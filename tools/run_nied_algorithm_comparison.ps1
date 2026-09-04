param(
    [Parameter(Mandatory = $true)]
    [string]$Capture,
    [string]$OutputDirectory = '',
    [string]$KanameishiRoot = 'D:\Users\Rhythm\Downloads\kanameishi-dev',
    [string]$SrevProject = '.dart_tool\srev_kaizou_diagnostic\upstream\srev-s\assets\project.json',
    [string]$CompiledBaselineProject = '.dart_tool\srev_page\docs\assets\project.json',
    [uint32]$SrevRandomSeed = 20260810
)

$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Resolve-ExistingPath([string]$Value, [string]$Description) {
    $candidate = if ([System.IO.Path]::IsPathRooted($Value)) {
        $Value
    } else {
        Join-Path $projectRoot $Value
    }
    $resolved = [System.IO.Path]::GetFullPath($candidate)
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "$Description not found: $resolved"
    }
    return $resolved
}

function Invoke-Step([string]$Description, [string]$Command, [string[]]$Arguments) {
    Write-Host "[$Description]"
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

function Get-JsonStringProperty(
    [System.Text.Json.JsonElement]$Element,
    [string]$Name
) {
    $property = [System.Text.Json.JsonElement]::new()
    if (-not $Element.TryGetProperty($Name, [ref]$property)) {
        return $null
    }
    return $property.GetString()
}

$capturePath = Resolve-ExistingPath $Capture 'Capture directory'
if (-not (Get-Item -LiteralPath $capturePath).PSIsContainer) {
    throw "Capture path is not a directory: $capturePath"
}
$manifestPath = Join-Path $capturePath 'capture_manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "capture_manifest.json not found: $manifestPath"
}
$kanameishiPath = Resolve-ExistingPath $KanameishiRoot 'kanameishi-dev root'
$srevProjectPath = Resolve-ExistingPath $SrevProject 'srev-kaizou project.json'
$baselineProjectCandidate = if ([System.IO.Path]::IsPathRooted($CompiledBaselineProject)) {
    $CompiledBaselineProject
} else {
    Join-Path $projectRoot $CompiledBaselineProject
}
$baselineProjectPath = if (Test-Path -LiteralPath $baselineProjectCandidate) {
    Resolve-ExistingPath $CompiledBaselineProject 'Compiled Scratch baseline project.json'
} else {
    $null
}

$manifestDocument = [System.Text.Json.JsonDocument]::Parse(
    [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
)
try {
    $manifestRoot = $manifestDocument.RootElement
    $caseId = Get-JsonStringProperty $manifestRoot 'caseId'
    if ([string]::IsNullOrWhiteSpace($caseId)) {
        $caseId = [System.IO.Path]::GetFileName($capturePath)
    }
    $startJst = Get-JsonStringProperty $manifestRoot 'startTimeJst'
    $endJst = Get-JsonStringProperty $manifestRoot 'endTimeJst'
    $event = $manifestRoot.GetProperty('event')
    $truthLatitude = $event.GetProperty('latitude').GetDouble().ToString(
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    $truthLongitude = $event.GetProperty('longitude').GetDouble().ToString(
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    $region = Get-JsonStringProperty $event 'region'
} finally {
    $manifestDocument.Dispose()
}
if ([string]::IsNullOrWhiteSpace($startJst) -or [string]::IsNullOrWhiteSpace($endJst)) {
    throw 'capture_manifest.json must contain startTimeJst and endTimeJst'
}

# The existing replay test treats its DateTime range as JST wall-clock time.
$startJstWallClock = [regex]::Replace($startJst, '(?:Z|[+-]\d{2}:\d{2})$', '')
$endJstWallClock = [regex]::Replace($endJst, '(?:Z|[+-]\d{2}:\d{2})$', '')
$outputPath = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path $projectRoot (Join-Path '.dart_tool\nied_algorithm_comparison' $caseId)
} elseif ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    [System.IO.Path]::GetFullPath($OutputDirectory)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
}
[System.IO.Directory]::CreateDirectory($outputPath) | Out-Null

$observationPath = Join-Path $outputPath 'gif_observations.json'
$productionDirectory = Join-Path $outputPath 'production'
$productionReportPath = Join-Path $productionDirectory 'report.json'
$kanameishiReportPath = Join-Path $outputPath 'kanameishi_original_report.json'
$srevReportPath = Join-Path $outputPath 'srev_kaizou_report.json'
$compatibilityPath = Join-Path $outputPath 'srev_compiled_core_compatibility.json'

Push-Location $projectRoot
try {
    Invoke-Step 'Export same-frame NIED observations' 'dart' @(
        'run',
        'tools\export_nied_capture_gif_observations.dart',
        '--capture', $capturePath,
        '--output', $observationPath,
        '--sensor-role', 'surface'
    )
    $observationDocument = [System.Text.Json.JsonDocument]::Parse(
        [System.IO.File]::ReadAllText($observationPath, [System.Text.Encoding]::UTF8)
    )
    try {
        $observationCount = $observationDocument.RootElement.GetProperty('observationCount').GetInt32()
    } finally {
        $observationDocument.Dispose()
    }
    if ($observationCount -le 0) {
        throw "Observation export produced no station observations: $observationPath"
    }

    Invoke-Step 'Run current production Dart estimator' 'flutter' @(
        'test',
        'test\current_capture_replay_analysis_test.dart',
        "--dart-define=CURRENT_CAPTURE_DIRECTORY=$capturePath",
        "--dart-define=CURRENT_CAPTURE_CASE_ID=$caseId",
        "--dart-define=CURRENT_CAPTURE_CASE_LABEL=$region",
        "--dart-define=CURRENT_CAPTURE_START_JST=$startJstWallClock",
        "--dart-define=CURRENT_CAPTURE_END_JST=$endJstWallClock",
        "--dart-define=CURRENT_CAPTURE_TRUTH_LATITUDE=$truthLatitude",
        "--dart-define=CURRENT_CAPTURE_TRUTH_LONGITUDE=$truthLongitude",
        "--dart-define=CURRENT_CAPTURE_OUTPUT_DIRECTORY=$productionDirectory",
        '--dart-define=CURRENT_CAPTURE_WRITEBACK_POLICY=current_non_increasing',
        '--dart-define=CURRENT_CAPTURE_SEARCH_SCHEDULE=reference_broad_four_stage'
    )

    Invoke-Step 'Run kanameishi-dev original JavaScript estimator' 'node' @(
        'tools\kanameishi_reference_algorithm_runner.js',
        '--kanameishi-root', $kanameishiPath,
        '--input', $productionReportPath,
        '--output', $kanameishiReportPath
    )

    if ($null -ne $baselineProjectPath) {
        Invoke-Step 'Verify srev procedures against compiled Scratch core' 'node' @(
            'tools\extract_srev_kaizou_procedures.js',
            '--srev-project', $srevProjectPath,
            '--compare-project', $baselineProjectPath,
            '--output', $compatibilityPath
        )
    }

    Invoke-Step 'Run t0729/srev-kaizou Scratch estimator' 'node' @(
        'tools\srev_kaizou_algorithm_runner.js',
        '--project', $srevProjectPath,
        '--input', $observationPath,
        '--output', $srevReportPath,
        '--random-seed', $SrevRandomSeed.ToString([System.Globalization.CultureInfo]::InvariantCulture),
        '--quiet'
    )

    $buildArguments = @(
        'tools\build_nied_algorithm_comparison.js',
        '--manifest', $manifestPath,
        '--capture', $capturePath,
        '--production', $productionReportPath,
        '--kanameishi', $kanameishiReportPath,
        '--srev', $srevReportPath,
        '--output-dir', $outputPath
    )
    if (Test-Path -LiteralPath $compatibilityPath) {
        $buildArguments += @('--compatibility', $compatibilityPath)
    }
    Invoke-Step 'Build unified three-algorithm report' 'node' $buildArguments
} finally {
    Pop-Location
}

Write-Host ''
Write-Host "Comparison JSON: $(Join-Path $outputPath 'comparison_report.json')"
Write-Host "Comparison Markdown: $(Join-Path $outputPath 'comparison_report.md')"
Write-Host "Raw algorithm reports: $outputPath"
