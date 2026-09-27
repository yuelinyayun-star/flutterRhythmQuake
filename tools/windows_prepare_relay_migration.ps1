$ErrorActionPreference='Stop'
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$root='C:\Users\Administrator\AppData\Local\Temp\rq-relay-migration-20260911'
$stage=Join-Path $root 'stage'
$archive=Join-Path $root 'relay-services.tar.gz'
Remove-Item -LiteralPath $stage,$archive -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'kma'),(Join-Path $stage 'wauth'),(Join-Path $stage 'ssl'),(Join-Path $stage 'nginx')|Out-Null

Copy-Item -LiteralPath 'D:\KmaPewsRelay\app\kma_pews_relay.py','D:\KmaPewsRelay\app\requirements.txt' -Destination (Join-Path $stage 'kma')
Copy-Item -LiteralPath 'D:\WAuthGateway\wauth_gateway.py','D:\WAuthGateway\requirements.txt','D:\WAuthGateway\wauth_background.jpg' -Destination (Join-Path $stage 'wauth')
Copy-Item -LiteralPath 'D:\KmaPewsRelay\ssl\ws.yuelinrhythm.top-chain.pem','D:\KmaPewsRelay\ssl\ws.yuelinrhythm.top-key.pem' -Destination (Join-Path $stage 'ssl')
Copy-Item -LiteralPath 'C:\BtSoft\nginx\conf\vhost\quake.yuelinrhythm.top.conf','C:\BtSoft\nginx\conf\vhost\ws.yuelinrhythm.top.conf' -Destination (Join-Path $stage 'nginx')

$secret=[Environment]::GetEnvironmentVariable('WAUTH_CLIENT_SECRET','Machine')
if([string]::IsNullOrWhiteSpace($secret)){$secret=[Environment]::GetEnvironmentVariable('WAUTH_CLIENT_SECRET','User')}
if([string]::IsNullOrWhiteSpace($secret)){throw 'WAUTH_CLIENT_SECRET is missing'}
[IO.File]::WriteAllLines((Join-Path $stage 'kma.env'),@('PYTHONUTF8=1','PYTHONUNBUFFERED=1','KMA_RELAY_HOST=127.0.0.1','KMA_RELAY_PORT=8765'),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines((Join-Path $stage 'wauth.env'),@('PYTHONUTF8=1','PYTHONIOENCODING=utf-8','PYTHONUNBUFFERED=1','WAUTH_HOST=127.0.0.1','WAUTH_PORT=8787',('WAUTH_CLIENT_SECRET='+$secret),'WAUTH_REDIRECT_URI=https://quake.yuelinrhythm.top/wauth/callback'),[Text.UTF8Encoding]::new($false))

$manifest=[ordered]@{CreatedAt=[DateTime]::UtcNow.ToString('o');Files=@()}
Get-ChildItem -LiteralPath $stage -File -Recurse|ForEach-Object{
  $relative=$_.FullName.Substring($stage.Length).TrimStart('\')
  if($relative -notin 'wauth.env'){$manifest.Files+=[ordered]@{Path=$relative;Length=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}}
}
$secretHash=(Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($secret))) -Algorithm SHA256).Hash
$manifest.WAuthSecret=[ordered]@{Length=$secret.Length;SHA256=$secretHash}
$manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $stage 'manifest.json') -Encoding UTF8

Push-Location $stage
try{& tar.exe -czf $archive *;if($LASTEXITCODE){throw 'tar failed'}}finally{Pop-Location}
& icacls.exe $root /inheritance:r /grant:r 'Administrator:(OI)(CI)F' 'SYSTEM:(OI)(CI)F'|Out-Null
[pscustomobject]@{Archive=$archive;Length=(Get-Item $archive).Length;SHA256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash;SecretLength=$secret.Length;SecretSHA256=$secretHash}|ConvertTo-Json -Compress
