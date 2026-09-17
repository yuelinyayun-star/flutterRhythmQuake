# ============================================================
#  FlutterRhythmQuake Windows Package Script
#  1. 运行 build_windows.ps1 -Release 构建 Release
#  2. 准备经过校验的安装器语言文件
#  3. 调用 Inno Setup 编译 RhythmQuake 自有安装器
# ============================================================

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir

$pubspecVersionLine = Get-Content -Encoding UTF8 ".\pubspec.yaml" |
    Where-Object { $_ -match '^version:\s*' } |
    Select-Object -First 1
if (-not $pubspecVersionLine -or
    $pubspecVersionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
    throw "Unable to parse version from pubspec.yaml. Expected version: x.y.z+build"
}
$appVersion = $Matches[1]
$appBuild = $Matches[2]
$packageVersion = "$appVersion.$appBuild"

$installerCacheDir = Join-Path $env:LOCALAPPDATA "RhythmQuake\build-cache\inno"
$chineseMessagesFile = Join-Path $installerCacheDir "ChineseSimplified.isl"
$chineseMessagesUrl = "https://raw.githubusercontent.com/jrsoftware/issrc/1ae7bf81dc0d2013235dfe4bb0b6f4e4a0b6b25c/Files/Languages/ChineseSimplified.isl"
$chineseMessagesHash = "e0b0b350e2245f3c5e65586dfe43d574f6e7f06f2261149aba284954b3fc9a8d"

# 检查 Inno Setup 安装路径
$isccPaths = @(
    "D:\Program Files\Inno Setup 7\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 5\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 5\ISCC.exe"
)

$iscc = $null
foreach ($path in $isccPaths) {
    if (Test-Path $path) {
        $iscc = $path
        break
    }
}

# 步骤 1: 构建 Release
Write-Host "[1/4] Building Windows Release $appVersion+$appBuild..." -ForegroundColor Cyan
& ".\build_windows.ps1" -Release

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Build failed! Exit code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}
Write-Host "      Build successful!" -ForegroundColor Green

$releaseDir = Join-Path $projectDir "build\windows\x64\runner\Release"
$requiredPayloadFiles = @(
    "flutterrhythmquake.exe",
    "flutter_windows.dll",
    "native_assets.json",
    "data\app.so",
    "data\icudtl.dat",
    "data\flutter_assets\AssetManifest.bin"
)
foreach ($relativePath in $requiredPayloadFiles) {
    $requiredPath = Join-Path $releaseDir $relativePath
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Windows release payload is incomplete: $relativePath"
    }
}

$manifestPath = Join-Path $releaseDir "release_manifest.json"
$manifestFiles = @(
    Get-ChildItem -LiteralPath $releaseDir -Recurse -File |
        Where-Object { $_.FullName -ne $manifestPath } |
        Sort-Object FullName |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($releaseDir.Length + 1).Replace('\', '/')
            [ordered]@{
                path = $relativePath
                bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
            }
        }
)
$releaseManifest = [ordered]@{
    product = "RhythmQuake"
    version = "$appVersion+$appBuild"
    architecture = "x64"
    files = $manifestFiles
}
$releaseManifest | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host "      Payload manifest: $($manifestFiles.Count) files" -ForegroundColor Green

# 步骤 2: 检查 Inno Setup
Write-Host "[2/4] Checking Inno Setup..." -ForegroundColor Cyan
if (-not $iscc) {
    Write-Host "  Inno Setup not found!" -ForegroundColor Red
    Write-Host "  Please install Inno Setup from: https://jrsoftware.org/isinfo.php" -ForegroundColor Yellow
    Write-Host "  Default installation paths:" -ForegroundColor Yellow
    foreach ($p in $isccPaths) {
        Write-Host "    - $p" -ForegroundColor Yellow
    }
    exit 1
}
Write-Host "      Found: $iscc" -ForegroundColor Green

# 步骤 3: 准备简体中文语言文件
Write-Host "[3/4] Preparing Simplified Chinese installer language..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $installerCacheDir | Out-Null
$downloadLanguageFile = $true
if (Test-Path -LiteralPath $chineseMessagesFile) {
    $cachedHash = (Get-FileHash -LiteralPath $chineseMessagesFile -Algorithm SHA256).Hash.ToLower()
    $downloadLanguageFile = $cachedHash -ne $chineseMessagesHash
}
if ($downloadLanguageFile) {
    $languageTempFile = "$chineseMessagesFile.download"
    Remove-Item -LiteralPath $languageTempFile -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $chineseMessagesUrl -OutFile $languageTempFile -TimeoutSec 60
    $downloadedHash = (Get-FileHash -LiteralPath $languageTempFile -Algorithm SHA256).Hash.ToLower()
    if ($downloadedHash -ne $chineseMessagesHash) {
        Remove-Item -LiteralPath $languageTempFile -Force -ErrorAction SilentlyContinue
        throw "Simplified Chinese installer language SHA256 mismatch."
    }
    Move-Item -LiteralPath $languageTempFile -Destination $chineseMessagesFile -Force
}
Write-Host "      Verified: $chineseMessagesHash" -ForegroundColor Green

# 步骤 4: 编译安装包
Write-Host "[4/4] Compiling branded installer..." -ForegroundColor Cyan
& $iscc "/DMyAppVersion=$appVersion" "/DMyAppBuild=$appBuild" "/DChineseMessagesFile=$chineseMessagesFile" "installer_rhythmquake.iss"

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Installer compilation failed! Exit code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Green
Write-Host "  Done! Installer created in: build\installer" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

$installerPath = Join-Path $projectDir "build\installer\RhythmQuake_Setup_${packageVersion}_x64.exe"
if (-not (Test-Path -LiteralPath $installerPath)) {
    throw "Expected installer was not created: $installerPath"
}
$installer = Get-Item -LiteralPath $installerPath
$installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLower()
$hashPath = "$installerPath.sha256"
Set-Content -LiteralPath $hashPath -Encoding ASCII -NoNewline -Value "$installerHash  $($installer.Name)"
$size = [math]::Round($installer.Length / 1MB, 2)
Write-Host "  $($installer.Name)  ($size MB)" -ForegroundColor White
Write-Host "  SHA256: $installerHash" -ForegroundColor DarkGray
