# ============================================================
#  flutterrhythmquake Windows Build Script
#  Automates: kill dart, pre-fill sqlite3 DLL cache, run flutter
# ============================================================

param(
    [switch]$Clean,
    [switch]$Release
)

# Force UTF-8 in terminal
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 2>$null | Out-Null

$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $projectDir

$dartTools = ".dart_tool"
$hooksShared = "$dartTools\hooks_runner\shared\sqlite3"
$cacheDir = "$hooksShared\download-8e7ad29"
$cacheDll = "$cacheDir\sqlite3.dll"
$nativeAssetsDir = "build\native_assets\windows"
$dllSource = "$env:LOCALAPPDATA\sqlite3_cache\sqlite3.x64.windows.dll"
$dllUrl = "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.3.1/sqlite3.x64.windows.dll"
$expectedHash = "15b1e7bee3fede1c90eab94c7eb9bb36ae29c33aa2d61bdc0de546326ae6c089"

# ============================================================
# Step 1: Kill dart processes (VS Code DAS) to release .lock
# ============================================================
Write-Host "[1/4] Killing dart processes..." -ForegroundColor Cyan
$dartProcs = Get-Process -Name "dart" -ErrorAction SilentlyContinue
if ($dartProcs) {
    Stop-Process -Name "dart" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "dartvm" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Host "      All dart processes killed" -ForegroundColor Green
} else {
    Write-Host "      No dart processes running" -ForegroundColor DarkGray
}

# ============================================================
# Step 2: Ensure sqlite3 DLL is cached locally
# ============================================================
Write-Host "[2/4] Checking sqlite3 DLL cache..." -ForegroundColor Cyan

if (-not (Test-Path $dllSource)) {
    Write-Host "      Downloading from GitHub..." -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $dllSource) | Out-Null
        Invoke-WebRequest -Uri $dllUrl -OutFile $dllSource -TimeoutSec 60
        Write-Host "      Downloaded: $((Get-Item $dllSource).Length) bytes" -ForegroundColor Green
    } catch {
        Write-Host "      Download failed: $_" -ForegroundColor Red
        Write-Host "      Manual download:" -ForegroundColor Yellow
        Write-Host "  $dllUrl" -ForegroundColor Yellow
        Write-Host "      Save to: $dllSource" -ForegroundColor Yellow
        exit 1
    }
}

$actualHash = (Get-FileHash -Path $dllSource -Algorithm SHA256).Hash.ToLower()
if ($actualHash -ne $expectedHash) {
    Write-Host "      SHA256 mismatch!" -ForegroundColor Red
    Write-Host "      Actual:   $actualHash" -ForegroundColor Red
    Write-Host "      Expected: $expectedHash" -ForegroundColor Red
    Write-Host "      Re-downloading..." -ForegroundColor Yellow
    Remove-Item $dllSource -Force
    exit 1
}
Write-Host "      DLL verified: $expectedHash" -ForegroundColor Green

# ============================================================
# Step 3: Clean and pre-fill cache
# ============================================================
Write-Host "[3/4] Pre-filling sqlite3 cache..." -ForegroundColor Cyan

if ($Clean) {
    Write-Host "      Cleaning build artifacts (--clean)..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force ".dart_tool" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "build" -ErrorAction SilentlyContinue
    flutter clean 2>$null
}

New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
Copy-Item $dllSource $cacheDll -Force

# Ensure native assets directory exists (fix INSTALL step)
New-Item -ItemType Directory -Force -Path $nativeAssetsDir | Out-Null

Write-Host "      Cache ready: $cacheDll" -ForegroundColor Green

# ============================================================
# Step 4: Run Flutter
# ============================================================
Write-Host "[4/4] Running Flutter..." -ForegroundColor Cyan

if ($Release) {
    Write-Host "      Mode: Release build" -ForegroundColor Yellow
    flutter build windows --release
} else {
    flutter run -d windows
}
