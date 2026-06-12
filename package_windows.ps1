# ============================================================
#  FlutterRhythmQuake Windows Package Script
#  1. 运行 build_windows.ps1 -Release 构建 Release
#  2. 调用 Inno Setup 编译生成安装包
# ============================================================

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir

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
Write-Host "[1/3] Building Windows Release..." -ForegroundColor Cyan
& ".\build_windows.ps1" -Release

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Build failed! Exit code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}
Write-Host "      Build successful!" -ForegroundColor Green

# 步骤 2: 检查 Inno Setup
Write-Host "[2/3] Checking Inno Setup..." -ForegroundColor Cyan
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

# 步骤 3: 编译安装包
Write-Host "[3/3] Compiling installer..." -ForegroundColor Cyan
& $iscc "installer.iss"

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Installer compilation failed! Exit code: $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "============================================" -ForegroundColor Green
Write-Host "  Done! Installer created in: build\installer" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

# 列出生成的安装包
$installers = Get-ChildItem "build\installer\*.exe"
foreach ($inst in $installers) {
    $size = [math]::Round($inst.Length / 1MB, 2)
    Write-Host "  $($inst.Name)  ($size MB)" -ForegroundColor White
}
