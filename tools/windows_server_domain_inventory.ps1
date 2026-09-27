$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Get-SafeRouteLines([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @(Get-Content -LiteralPath $path -Encoding UTF8 |
        Where-Object {
            $_ -match '^\s*@(?:app|router)\.(?:get|post|put|delete|patch|websocket|route)\s*\(' -or
            $_ -match '^\s*(?:async\s+)?def\s+[A-Za-z_][A-Za-z0-9_]*\s*\('
        } |
        ForEach-Object { $_.Trim() })
}

function Get-EnvironmentNames([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $names = @()
    foreach ($pattern in @(
        'os\.environ(?:\.get)?\(\s*["'']([A-Za-z_][A-Za-z0-9_]*)["'']',
        'os\.getenv\(\s*["'']([A-Za-z_][A-Za-z0-9_]*)["'']'
    )) {
        $names += @([regex]::Matches($text, $pattern) | ForEach-Object { $_.Groups[1].Value })
    }
    return @($names | Sort-Object -Unique)
}

$apps = @(
    [pscustomobject]@{
        Name = 'KMA PEWS Relay'
        Path = 'D:\KmaPewsRelay\app\kma_pews_relay.py'
    },
    [pscustomobject]@{
        Name = 'WAuth Gateway'
        Path = 'D:\WAuthGateway\wauth_gateway.py'
    }
) | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        Path = $_.Path
        Exists = Test-Path -LiteralPath $_.Path
        Routes = Get-SafeRouteLines $_.Path
        EnvironmentNames = Get-EnvironmentNames $_.Path
    }
}

$vhosts = @(Get-ChildItem -LiteralPath 'C:\BtSoft\nginx\conf\vhost' -Filter '*.conf' -Recurse |
    ForEach-Object {
        $safeLines = @(Get-Content -LiteralPath $_.FullName -Encoding UTF8 |
            Where-Object {
                $_ -match '^\s*(server_name|listen|location|proxy_pass|root|ssl_certificate|ssl_certificate_key)\b'
            } |
            ForEach-Object {
                $line = $_.Trim()
                if ($line -match '^ssl_certificate_key\s+') { 'ssl_certificate_key [configured];' } else { $line }
            })
        [pscustomobject]@{File=$_.FullName;Directives=$safeLines}
    })

$certificates = @()
$certPaths = @(Get-ChildItem -LiteralPath 'C:\BtSoft\nginx\conf\vhost' -Filter '*.conf' -Recurse |
    ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Encoding UTF8 |
            ForEach-Object {
                if ($_ -match '^\s*ssl_certificate\s+(.+?);\s*$') { $Matches[1].Trim('"') }
            }
    } | Sort-Object -Unique)
foreach ($certPath in $certPaths) {
    $resolved = $certPath -replace '/', '\'
    if (-not [System.IO.Path]::IsPathRooted($resolved)) {
        $resolved = Join-Path 'C:\BtSoft\nginx' $resolved
    }
    $entry = [ordered]@{Path=$resolved;Exists=Test-Path -LiteralPath $resolved}
    if ($entry.Exists) {
        try {
            $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($resolved)
            $entry.Subject = $cert.Subject
            $entry.Issuer = $cert.Issuer
            $entry.NotBefore = $cert.NotBefore.ToUniversalTime().ToString('o')
            $entry.NotAfter = $cert.NotAfter.ToUniversalTime().ToString('o')
            $entry.DnsNames = @($cert.Extensions | Where-Object Oid -Property FriendlyName -eq 'Subject Alternative Name' |
                ForEach-Object { $_.Format($false) })
        } catch {
            $entry.Error = $_.Exception.Message
        }
    }
    $certificates += [pscustomobject]$entry
}

$ports = @(21,80,443,888,3306,3389,5985,8080,8765,8787)
$firewallRules = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue |
    ForEach-Object {
        $rule = $_
        Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Protocol -in 'TCP',6 -and (
                    $_.LocalPort -eq 'Any' -or
                    @($_.LocalPort -split ',') | Where-Object { [int]($_ -replace '[^0-9]','0') -in $ports }
                )
            } |
            ForEach-Object {
                [pscustomobject]@{
                    Name=$rule.DisplayName
                    Profile=[string]$rule.Profile
                    LocalPort=[string]$_.LocalPort
                    RemotePort=[string]$_.RemotePort
                }
            }
    })

[pscustomobject]@{
    CapturedAt=[DateTime]::UtcNow.ToString('o')
    Apps=$apps
    Vhosts=$vhosts
    Certificates=$certificates
    FirewallProfiles=Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction
    InboundAllowRules=$firewallRules
} | ConvertTo-Json -Depth 8 -Compress
