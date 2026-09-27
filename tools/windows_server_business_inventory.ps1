$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$vhosts = @(Get-ChildItem -LiteralPath 'C:\BtSoft\nginx\conf\vhost' -Filter '*.conf' -Recurse |
    ForEach-Object {
        $lines = @(Get-Content -LiteralPath $_.FullName -Encoding UTF8 |
            Where-Object { $_ -match '^\s*(server_name|listen|location|proxy_pass|fastcgi_pass|root|include)\s' } |
            ForEach-Object { $_.Trim() -replace '(https?://)[^/@\s]+:[^/@\s]+@','$1[redacted]@' })
        [pscustomobject]@{File=$_.FullName;Directives=$lines}
    })
$checks = @(foreach ($url in @('http://127.0.0.1:8787/health','http://127.0.0.1:8765/health','http://127.0.0.1:8080/')) {
    $request=[System.Net.HttpWebRequest]::Create($url)
    $request.Proxy=$null
    $request.Timeout=10000
    $response=$null
    $failure=$null
    try { $response=$request.GetResponse() }
    catch [System.Net.WebException] { $response=$_.Exception.Response; $failure=[string]$_.Exception.Status }
    if ($null -eq $response) { [pscustomobject]@{Url=$url;HttpStatus=$null;Error=$failure}; continue }
    $result=[ordered]@{Url=$url;HttpStatus=[int]$response.StatusCode}
    if ($url.EndsWith('/health')) {
        $reader=[System.IO.StreamReader]::new($response.GetResponseStream(),[System.Text.Encoding]::UTF8)
        try { $health=$reader.ReadToEnd() | ConvertFrom-Json
            foreach ($name in @('status','redirectUri','pendingAuthorizations','clientSecretConfigured',
                'clockSynced','lastFrameUtc','lastFrameAgeSeconds','stationCount','clientCount',
                'consecutiveFailures','lastOfficialHttpStatus','acceptedFrames')) {
                if ($health.PSObject.Properties.Name -contains $name) { $result[$name]=$health.$name }
            }
        } finally { $reader.Dispose() }
    }
    $response.Close()
    [pscustomobject]$result
})
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Vhosts=$vhosts;Health=$checks} |
    ConvertTo-Json -Depth 7 -Compress
