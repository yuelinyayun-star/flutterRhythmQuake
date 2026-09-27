param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('personal', 'public')]
    [string]$Edition
)

$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir

$versionLine = Get-Content -Encoding UTF8 '.\pubspec.yaml' |
    Where-Object { $_ -match '^version:\s*' } |
    Select-Object -First 1
if ($versionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    throw 'Unable to parse version from pubspec.yaml.'
}
$packageVersion = "$($Matches[1]).$($Matches[2])"

& flutter build apk --release "--dart-define=RQ_EDITION=$Edition"
if ($LASTEXITCODE -ne 0) {
    throw "Android $Edition build failed with exit code $LASTEXITCODE."
}

$source = Join-Path $projectDir 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Android APK not found: $source"
}
$outputDir = Join-Path $projectDir 'build\installer'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$destination = Join-Path $outputDir "RhythmQuake_${packageVersion}_${Edition}.apk"
Copy-Item -LiteralPath $source -Destination $destination -Force
$hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLower()
$fileName = Split-Path -Leaf $destination
Set-Content -LiteralPath "$destination.sha256" -Encoding ASCII -NoNewline -Value "$hash  $fileName"
Write-Host "$destination`nSHA256: $hash"
