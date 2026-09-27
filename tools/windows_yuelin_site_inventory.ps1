$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$root = [System.IO.Path]::GetFullPath('C:\wwwroot\yuelinrhythm.top')
$knownFiles = @('index.php','index.html','composer.json','package.json','artisan',
    'wp-load.php','wp-includes\version.php','.user.ini','web.config')
$top = @(Get-ChildItem -LiteralPath $root -Force | ForEach-Object {
    [pscustomobject]@{Name=$_.Name;Type=if($_.PSIsContainer){'directory'}else{'file'};
        Length=if($_.PSIsContainer){$null}else{$_.Length};Modified=$_.LastWriteTimeUtc}
})
$known = @(foreach($relative in $knownFiles) {
    $path = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { continue }
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $item=Get-Item -LiteralPath $path
        [pscustomobject]@{Relative=$relative;Length=$item.Length;Modified=$item.LastWriteTimeUtc;
            SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    }
})
$framework=[ordered]@{
    WordPress=(Test-Path -LiteralPath (Join-Path $root 'wp-load.php'))
    Laravel=(Test-Path -LiteralPath (Join-Path $root 'artisan'))
    Composer=(Test-Path -LiteralPath (Join-Path $root 'composer.json'))
    Node=(Test-Path -LiteralPath (Join-Path $root 'package.json'))
}
if ($framework.WordPress) {
    $version=Get-Content -LiteralPath (Join-Path $root 'wp-includes\version.php') -Encoding UTF8 |
        Where-Object { $_ -match '^\s*\$wp_version\s*=' } | Select-Object -First 1
    $framework['WordPressVersionDeclaration']=$version
}
$configFiles=@(
    'C:\BtSoft\nginx\conf\vhost\yuelinrhythm.top.conf',
    'C:\BtSoft\nginx\conf\php\83.conf',
    'C:\BtSoft\nginx\conf\vhost\extension\yuelinrhythm.top\site_total.conf'
)
$configs=@(foreach($path in $configFiles){
    if(Test-Path -LiteralPath $path){
        $safeLines=@(Get-Content -LiteralPath $path -Encoding UTF8 |
            Where-Object { $_ -notmatch '^\s*(#|$)' } |
            ForEach-Object { $_ -replace '(?i)(password|secret|token)\s+[^;]+','$1 [redacted]' })
        [pscustomobject]@{Path=$path;Lines=$safeLines}
    }
})
$php=@(Get-CimInstance Win32_Process -Filter "Name='php-cgi.exe'" | ForEach-Object {
    [pscustomobject]@{Pid=$_.ProcessId;ParentPid=$_.ParentProcessId;Executable=$_.ExecutablePath;
        WorkingSetMiB=[math]::Round($_.WorkingSetSize/1MB,2);Started=$_.CreationDate}
})
$requests=@(foreach($url in @('http://127.0.0.1/','https://127.0.0.1/')){
    $request=[System.Net.HttpWebRequest]::Create($url)
    $request.Proxy=$null; $request.Timeout=12000; $request.Host='yuelinrhythm.top'
    if($url.StartsWith('https:')){$request.ServerCertificateValidationCallback={param($s,$c,$ch,$e) $true}}
    $response=$null; $failure=$null
    try{$response=$request.GetResponse()}catch [System.Net.WebException]{$response=$_.Exception.Response;$failure=[string]$_.Exception.Status}
    if($null -eq $response){[pscustomobject]@{Url=$url;HttpStatus=$null;Error=$failure};continue}
    [pscustomobject]@{Url=$url;HttpStatus=[int]$response.StatusCode;Server=$response.Headers['Server'];
        ContentType=$response.ContentType;ContentLength=$response.ContentLength;
        Location=$response.Headers['Location'];PoweredBy=$response.Headers['X-Powered-By']}
    $response.Close()
})
[pscustomobject]@{CapturedAt=[DateTime]::UtcNow.ToString('o');Root=$root;
    Framework=$framework;TopLevel=$top;KnownFiles=$known;Configs=$configs;
    PhpProcesses=$php;Requests=$requests} | ConvertTo-Json -Depth 8 -Compress
