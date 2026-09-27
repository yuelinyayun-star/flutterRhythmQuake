#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$directory = Join-Path $PSScriptRoot '../tmp/fdsn_connection_review'
$output = Join-Path $directory 'pktmon_admin_inspection_20260910.log'
$lines = @('Inspection UTC: ' + [DateTime]::UtcNow.ToString('o'))
$lines += & pktmon status 2>&1
$lines += 'STATUS_EXIT=' + $LASTEXITCODE
$lines += & pktmon filter list 2>&1
$lines += 'FILTER_EXIT=' + $LASTEXITCODE
$lines += & logman query -ets 2>&1
$lines | Out-File -LiteralPath $output -Encoding utf8
