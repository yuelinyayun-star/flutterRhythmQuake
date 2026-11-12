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
Add-Type -AssemblyName System.IO.Compression.FileSystem
$apk = [System.IO.Compression.ZipFile]::OpenRead($source)
try {
    foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
        $entry = $apk.GetEntry("lib/$abi/librq_station_core.so")
        if ($null -eq $entry -or $entry.Length -eq 0) {
            throw "Android APK is missing the Rust backend: $abi"
        }
        $stream = $entry.Open()
        try {
            $header = [byte[]]::new(20)
            $read = $stream.Read($header, 0, $header.Length)
            $expectedClass = if ($abi -eq 'armeabi-v7a') { 1 } else { 2 }
            $expectedMachine = switch ($abi) {
                'armeabi-v7a' { 40 }
                'arm64-v8a' { 183 }
                'x86_64' { 62 }
            }
            if ($read -ne 20 -or $header[0] -ne 127 -or
                [System.Text.Encoding]::ASCII.GetString($header, 1, 3) -ne 'ELF' -or
                $header[4] -ne $expectedClass -or $header[5] -ne 1 -or
                [BitConverter]::ToUInt16($header, 18) -ne $expectedMachine) {
                throw "Android Rust library has an invalid ELF architecture: $abi"
            }
        } finally {
            $stream.Dispose()
        }
    }
} finally {
    $apk.Dispose()
}
$outputDir = Join-Path $projectDir 'build\installer'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$destination = Join-Path $outputDir "RhythmQuake_${packageVersion}_${Edition}.apk"
Copy-Item -LiteralPath $source -Destination $destination -Force
$hash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLower()
$fileName = Split-Path -Leaf $destination
Set-Content -LiteralPath "$destination.sha256" -Encoding ASCII -NoNewline -Value "$hash  $fileName"
Write-Host "$destination`nSHA256: $hash"
