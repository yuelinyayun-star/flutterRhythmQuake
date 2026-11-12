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

& flutter build apk --release --split-per-abi "--dart-define=RQ_EDITION=$Edition"
if ($LASTEXITCODE -ne 0) {
    throw "Android split APK build failed with exit code $LASTEXITCODE."
}

$outputDir = Join-Path $projectDir 'build\installer'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$abis = @(
    @{ Name = 'armeabi-v7a'; Source = 'app-armeabi-v7a-release.apk' },
    @{ Name = 'arm64-v8a'; Source = 'app-arm64-v8a-release.apk' },
    @{ Name = 'x86_64'; Source = 'app-x86_64-release.apk' }
)

Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($abi in $abis) {
    $source = Join-Path $projectDir "build\app\outputs\flutter-apk\$($abi.Source)"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Split APK not found for $($abi.Name): $source"
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($source)
    try {
        $entries = @($zip.Entries | Where-Object { $_.FullName -like 'lib/*/*.so' })
        $expected = "lib/$($abi.Name)/"
        $payloadAbis = @(
            $entries |
                ForEach-Object { $_.FullName.Split('/')[1] } |
                Sort-Object -Unique
        )
        if ($payloadAbis.Count -ne 1 -or $payloadAbis[0] -ne $abi.Name -or
            $entries.Count -eq 0 -or
            ($entries | Where-Object { $_.FullName -notlike "$expected*" }).Count -ne 0) {
            throw "Split APK contains unexpected native ABI payload for $($abi.Name)."
        }
        $rustEntry = $zip.GetEntry("lib/$($abi.Name)/librq_station_core.so")
        if ($null -eq $rustEntry -or $rustEntry.Length -eq 0) {
            throw "Rust backend missing for $($abi.Name)."
        }
    } finally {
        $zip.Dispose()
    }
    $destination = Join-Path $outputDir "RhythmQuake_${packageVersion}_${Edition}_$($abi.Name).apk"
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLower()
    $fileName = Split-Path -Leaf $destination
    Set-Content -LiteralPath "$destination.sha256" -Encoding ASCII -NoNewline -Value "$hash  $fileName"
    Write-Host "$destination`nSHA256: $hash"
}
