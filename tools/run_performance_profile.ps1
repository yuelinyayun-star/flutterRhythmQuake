param([string]$DataRoot)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$workspace = Split-Path $PSScriptRoot -Parent
if (!$DataRoot) { $DataRoot = Join-Path $workspace 'tmp/profile_run' }
$DataRoot = [IO.Path]::GetFullPath($DataRoot)
if (!(Test-Path -LiteralPath (Join-Path $DataRoot 'support/shared_preferences.json'))) {
    throw 'Use an isolated test directory containing a COPY of your settings under support/shared_preferences.json.'
}
$exe = Join-Path $workspace 'build/windows/x64/runner/Profile/flutterrhythmquake.exe'
if (!(Test-Path -LiteralPath $exe)) { throw 'Build tool/performance_profile.dart in Profile mode first.' }
$previous = $env:RQ_PROFILE_ROOT
try {
    $env:RQ_PROFILE_ROOT = $DataRoot
    Start-Process -FilePath $exe -WorkingDirectory $DataRoot -WindowStyle Hidden
} finally {
    $env:RQ_PROFILE_ROOT = $previous
}
