param([string]$PayloadDir, [string]$OutputRoot, [switch]$SelfTest, [switch]$CollectOnly, [switch]$UiSelfTest, [string]$BundleDir)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
if (-not $OutputRoot) { $OutputRoot = Join-Path ([Environment]::GetFolderPath('Desktop')) ('Jian诊断_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$script:Report = [ordered]@{schema='rhythmquake_network_diagnostic_v3';toolVersion='0.3';startedUtc=(Get-Date).ToUniversalTime().ToString('o');mode='passive';apiProbes=0;appLaunches=0;notes=@('Debug APP 内置原文记录；导出器先启动系统抓包，再启动配套 Debug APP。','原始记录包含鉴权凭证及会话密钥，仅保存在本机，不自动上传。','不清空重试记录、不修改安装目录。系统抓包可能同时包含其他程序的流量。')}
$script:FileHashes=@{}
function Get-CachedHash([string]$Path) {
    $item=Get-Item -LiteralPath $Path
    $key=$item.FullName+'|'+$item.Length+'|'+$item.LastWriteTimeUtc.Ticks
    if (-not $script:FileHashes.ContainsKey($key)) { $script:FileHashes[$key]=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() }
    return $script:FileHashes[$key]
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$script:Report.executionContext=@{userSid=$identity.User.Value;administrator=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);osVersion=[Environment]::OSVersion.VersionString;powerShellVersion=$PSVersionTable.PSVersion.ToString()}
function Save-Json($Value, [string]$Path) { [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 14), [Text.UTF8Encoding]::new($false)) }
function Get-AppProcesses {
    $rows = @()
    foreach ($item in @(Get-Process -Name flutterrhythmquake -ErrorAction SilentlyContinue)) {
        try {
            $modules=@();$moduleStatus='captured'
            try {
                foreach ($module in @($item.Modules | Where-Object { $_.ModuleName -ieq 'rq_station_core.dll' })) {
                    $modules += @{path=$module.FileName;sha256=(Get-CachedHash $module.FileName)}
                }
                if (-not $modules.Count) { $moduleStatus='not_loaded' }
            } catch { $moduleStatus='unavailable';$modules=@() }
            $rows += [ordered]@{pid=$item.Id;path=$item.Path;startedUtc=$item.StartTime.ToUniversalTime().ToString('o');stationCoreModules=$modules;moduleCollectionStatus=$moduleStatus}
        }
        catch { $rows += [ordered]@{pid=$item.Id;path=$null;access='unavailable'} }
    }
    return $rows
}
function Get-RetryState {
    $path = Join-Path $env:LOCALAPPDATA 'RhythmQuake/jian_auth_retry.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{present=$false;credentialPresence='not_checked'} }
    try {
        $value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $rows = @()
        foreach ($property in $value.PSObject.Properties) {
            $row = [ordered]@{fingerprint=$(if($property.Name -match '^[a-fA-F0-9]{64}$'){$property.Name}else{'unrecognized_key_not_exported'});failures=0;revision=0;blocked=$false;code=$null;nextAttemptMs=$null}
            foreach ($name in @('failures','revision','blocked','code','nextAttemptMs')) {
                $entry = $property.Value.PSObject.Properties[$name]
                if ($entry) { $row[$name] = $entry.Value }
            }
            $rows += $row
        }
        return @{present=$true;records=$rows;credentialPresence='not_checked'}
    } catch { return @{present=$true;readError=$_.Exception.GetType().Name;credentialPresence='not_checked'} }
}
function Get-SafePreferences {
    $rows = @()
    foreach ($directory in @((Join-Path $env:APPDATA 'com.example/flutterrhythmquake'),(Join-Path $env:APPDATA 'RhythmQuake'))) {
        $file = Join-Path $directory 'shared_preferences.json'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $size = (Get-Item -LiteralPath $file).Length
        $selected = [ordered]@{}
        if ($size -le 2097152) {
            try {
                $data = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($key in @('flutter.api_source_jian_enabled','flutter.jian_retry_after_ms','flutter.nied_data_source','flutter.snet_data_source','flutter.kma_data_source','flutter.jian_icl_debug_enabled')) {
                    if ($data.PSObject.Properties[$key]) { $selected[$key] = $data.$key }
                }
            } catch { $selected['readError'] = $_.Exception.GetType().Name }
        } else { $selected['readError'] = 'preferences_over_2MiB_not_loaded' }
        $rows += @{path=$file;bytes=$size;selected=$selected}
    }
    return $rows
}
function Get-AppFileEvidence([string]$Exe) {
    $rows = @()
    $directory = Split-Path -Parent $Exe
    foreach ($name in @('flutterrhythmquake.exe','rq_station_core.dll','data/app.so','release_manifest.json')) {
        $file = Join-Path $directory $name
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file
            $rows += @{name=$name;bytes=$item.Length;writtenUtc=$item.LastWriteTimeUtc.ToString('o');sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower()}
        }
    }
    return $rows
}
function Capture-Snapshot([string]$Name) {
    $apps = @(Get-AppProcesses)
    $tcp = @();$tcpStatus='app_not_running'
    if ($apps.Count -gt 0) {
        try {
            $tcp = @(Get-NetTCPConnection -OwningProcess @($apps | ForEach-Object { [uint32]$_.pid }) -ErrorAction SilentlyContinue | ForEach-Object { @{pid=$_.OwningProcess;state=[string]$_.State;localPort=$_.LocalPort;remoteAddress=$_.RemoteAddress;remotePort=$_.RemotePort} })
            $tcpStatus=if($tcp.Count){'captured'}else{'empty_or_unavailable'}
        } catch { $tcpStatus='unavailable' }
    }
    $dns=@();$owners=@();$dnsStatus='unavailable'
    try {
        $dns=@(Get-DnsClientCache -ErrorAction Stop | Where-Object { $_.Entry -like '*sismotide.top' -or $_.RecordName -like '*sismotide.top' } | ForEach-Object {
            if ([string]$_.Data -match '^[0-9a-fA-F:.]+$') { @{entry=$_.Entry;recordName=$_.RecordName;address=[string]$_.Data} }
        })
        $dnsStatus='cache_only_no_lookup'
        $addresses=@($dns | ForEach-Object { $_.address } | Select-Object -Unique)
        if ($addresses.Count) {
            $owners=@(Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $addresses -contains $_.RemoteAddress } | ForEach-Object {
                $owner=Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                @{pid=$_.OwningProcess;processName=$owner.ProcessName;remoteAddress=$_.RemoteAddress;remotePort=$_.RemotePort;state=[string]$_.State}
            })
        }
    } catch { $dnsStatus='unavailable' }
    $proxy = Get-ItemProperty -LiteralPath 'HKCU:/Software/Microsoft/Windows/CurrentVersion/Internet Settings' -ErrorAction SilentlyContinue
    $snapshot = [ordered]@{timeUtc=(Get-Date).ToUniversalTime().ToString('o');localTime=(Get-Date).ToString('o');timeZone=[TimeZoneInfo]::Local.Id;appProcesses=$apps;tcpConnections=$tcp;tcpCollectionStatus=$tcpStatus;jianDnsCache=$dns;dnsCollectionStatus=$dnsStatus;cachedAddressConnectionOwners=$owners;addressMatchingLimitation='DNS 缓存地址可能被其他域名共用；不能据此确定请求域名、路径或鉴权。';retryState=(Get-RetryState);preferences=@(Get-SafePreferences);proxy=@{enabled=$proxy.ProxyEnable;configured=[bool]$proxy.ProxyServer;pacConfigured=[bool]$proxy.AutoConfigURL;httpEnvironmentConfigured=[bool]$env:HTTP_PROXY;httpsEnvironmentConfigured=[bool]$env:HTTPS_PROXY;allEnvironmentConfigured=[bool]$env:ALL_PROXY}}
    Save-Json $snapshot (Join-Path $OutputRoot ($Name+'.json'))
    return $snapshot
}
function Get-TraceRows {
    $path = Join-Path $OutputRoot 'jian_handshake.jsonl'
    $rows = @()
    if (Test-Path -LiteralPath $path) {
        foreach ($line in [IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)) {
            if (-not $line.Trim()) { continue }
            try { $rows += ($line | ConvertFrom-Json) } catch { }
        }
    }
    return $rows
}
function Save-CaptureDirectory {
    $source=$script:CaptureDirectory
    if (-not $source) {
        $latest=Join-Path $env:LOCALAPPDATA 'RhythmQuake/network_diagnostics/latest.json'
        if (Test-Path -LiteralPath $latest) {
            try {$source=(Get-Content -LiteralPath $latest -Raw -Encoding UTF8 | ConvertFrom-Json).directory} catch {}
        }
    }
    if (-not $source -or -not (Test-Path -LiteralPath $source -PathType Container)) { $script:Report.captureStatus='not_found';return }
    $target=Join-Path $OutputRoot 'app_capture'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $cutoff=$null
    $controlFile=Join-Path $source 'control.json'
    if (Test-Path -LiteralPath $controlFile) {
        try {
            $control=Get-Content -LiteralPath $controlFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $flush=Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:'+$control.port+'/flush') -Method Post -Headers @{'X-Diagnostic-Token'=$control.token} -TimeoutSec 4
            $answer=$flush.Content | ConvertFrom-Json
            if ($answer.ok -and $answer.pid -eq $control.pid) { $cutoff=[long]$answer.fileBytes;$script:Report.flushStatus='confirmed' }
            else {$script:Report.flushStatus='not_confirmed'}
        } catch {$script:Report.flushStatus='unavailable_live_snapshot_only'}
    }
    # Do not parse/re-encode the raw payload log. Copy a byte-for-byte snapshot.
    foreach ($name in @('session.json','network_raw.jsonl','network_raw.jsonl.status.json','tls_keys.log')) {
        $file=Join-Path $source $name
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $captureInput=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            try {
                $output=[IO.File]::Create((Join-Path $target $name))
                try {
                    if ($name -eq 'network_raw.jsonl' -and $null -ne $cutoff) {
                        $remaining=$cutoff;$buffer=New-Object byte[] 65536
                        while ($remaining -gt 0) {
                            $read=$captureInput.Read($buffer,0,[int][Math]::Min($remaining,$buffer.Length))
                            if ($read -eq 0) {throw '原文快照未达到确认的落盘位置。'}
                            $output.Write($buffer,0,$read);$remaining-=$read
                        }
                        $script:Report.rawSnapshotBytes=$cutoff
                    } else {$captureInput.CopyTo($output)}
                }finally{$output.Dispose()}
            } finally {$captureInput.Dispose()}
        }
    }
    $script:Report.captureDirectory=$source
    $script:Report.captureStatus='raw_snapshot_copied'
    $file=Join-Path $target 'network_raw.jsonl.status.json'
    if (Test-Path -LiteralPath $file) { $script:Report.writerStatus=Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json }
}
function Stop-NetworkCapture {
    if ($script:OwnsPacketCapture) {
        $result=& "$env:SystemRoot/System32/pktmon.exe" stop 2>&1 | Out-String
        [IO.File]::WriteAllText((Join-Path $OutputRoot 'packet_stop.txt'),$result,[Text.Encoding]::UTF8)
        $script:Report.packetStopExitCode=$LASTEXITCODE
        $script:OwnsPacketCapture=$false
        foreach ($file in @(Get-ChildItem -LiteralPath $OutputRoot -Filter '*.etl' -File)) {
            $pcap=[IO.Path]::ChangeExtension($file.FullName,'.pcapng')
            $conversion=& "$env:SystemRoot/System32/pktmon.exe" etl2pcap $file.FullName --out $pcap 2>&1 | Out-String
            [IO.File]::WriteAllText(($file.FullName+'.conversion.txt'),$conversion,[Text.Encoding]::UTF8)
        }
    }
}
function Finish-Report {
    Stop-NetworkCapture
    $null=Capture-Snapshot 'after'
    Save-CaptureDirectory
    $script:Report.finishedUtc=(Get-Date).ToUniversalTime().ToString('o')
    $script:Report.packetFiles=@(Get-ChildItem -LiteralPath $OutputRoot -Filter '*.etl' -File | ForEach-Object { @{name=$_.Name;bytes=$_.Length} })
    Save-Json $script:Report (Join-Path $OutputRoot 'report.json')
    $summary=@('RhythmQuake Debug 网络诊断','','app_capture/network_raw.jsonl：原始 HTTP、WebSocket、TCP 收发记录（包含凭证）。','app_capture/tls_keys.log：Dart HttpClient 和专用 FDSN TLS 会话密钥。','network*.etl：系统原始数据包与 TCPIP/WinHTTP 事件；含机器其他程序流量。','sample_*.json：APP PID、端点、实际 DLL 和本机重试/源配置。','','检查 writerStatus.lost、writeErrors、queuedBytes；非零表示采集存在缺口。','send_queued 只表示提交发送；以网络抓包、HTTP 状态和服务端响应共同核对。','自动 HTTP 重定向、分离后的 Dart Socket、UDP、原生插件流量须结合 ETL；不能只用明文日志认定全覆盖。','原文文件未脱敏；仅在本机保存，没有自动上传。')
    [IO.File]::WriteAllLines((Join-Path $OutputRoot '结果.txt'),$summary,[Text.UTF8Encoding]::new($true))
    $zip=$OutputRoot+'.zip'
    if (Test-Path -LiteralPath $zip) {$zip=$OutputRoot+'_'+(Get-Date -Format 'HHmmss')+'.zip'}
    $items=@(Get-ChildItem -LiteralPath $OutputRoot | Where-Object {$_.Name -ne 'live_app_capture'} | ForEach-Object {$_.FullName})
    Compress-Archive -LiteralPath $items -DestinationPath $zip
    return $zip
}
$script:OwnsPacketCapture=$false;$script:CaptureDirectory=$null
$null=Capture-Snapshot 'before'
if ($SelfTest -or $CollectOnly) {
    $script:Report.mode='passive_self_test'
    $zip=Finish-Report
    Save-Json @{passed=$true;apiProbes=0;appLaunches=0;reportZip=$zip} (Join-Path $OutputRoot 'self-test.json')
    exit 0
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object Windows.Forms.Form
$form.Text='RhythmQuake Debug · 全连接诊断导出'
$form.Size=New-Object Drawing.Size(790,550);$form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$title=New-Object Windows.Forms.Label
$title.Text="以管理员身份运行，先退出旧 APP，再启动配套 Debug。`r`n先抓包后启动；原文含 Token／会话密钥，仅本机保存。"
$title.SetBounds(18,15,745,55);$form.Controls.Add($title)
$pathBox=New-Object Windows.Forms.TextBox;$pathBox.SetBounds(18,83,600,30);$form.Controls.Add($pathBox)
if ($BundleDir) {$pathBox.Text=Join-Path $BundleDir 'APP/flutterrhythmquake.exe'}
$browse=New-Object Windows.Forms.Button;$browse.Text='选择 Debug';$browse.SetBounds(630,80,125,34);$form.Controls.Add($browse)
$start=New-Object Windows.Forms.Button;$start.Text='抓包并启动 Debug';$start.SetBounds(18,130,220,40);$form.Controls.Add($start)
$save=New-Object Windows.Forms.Button;$save.Text='停止抓包并导出';$save.SetBounds(250,130,210,40);$form.Controls.Add($save)
$open=New-Object Windows.Forms.Button;$open.Text='打开结果目录';$open.SetBounds(472,130,170,40);$form.Controls.Add($open)
$status=New-Object Windows.Forms.TextBox;$status.Multiline=$true;$status.ReadOnly=$true;$status.ScrollBars='Vertical';$status.SetBounds(18,185,737,305);$form.Controls.Add($status)
$status.Text="Debug 单独启动时也会记录原文；本程序配合抓系统数据包。`r`n记录 180 秒后自动导出，也可提前停止。不会代替你解封或清空冷却。`r`n结果目录：$OutputRoot`r`n"
$script:Recording=$false;$script:Saved=$false;$script:StartedAt=$null
$browse.Add_Click({$dialog=New-Object Windows.Forms.OpenFileDialog;$dialog.Filter='RhythmQuake|flutterrhythmquake.exe';if($dialog.ShowDialog() -eq 'OK'){$pathBox.Text=$dialog.FileName}})
$open.Add_Click({Start-Process -FilePath explorer.exe -ArgumentList @($OutputRoot) -WindowStyle Normal})
$save.Add_Click({try{$timer.Stop();$zip=Finish-Report;$script:Saved=$true;$script:Recording=$false;$status.AppendText("`r`n已导出：$zip`r`nAPP 继续运行；需停止全部连接时手动退出 APP。`r`n")}catch{$status.AppendText("`r`n导出失败：$($_.Exception.Message)`r`n")}})
$start.Add_Click({
    try {
        if ($script:Recording) {return}
        if (-not $script:Report.executionContext.administrator) {throw '系统抓包需要管理员权限。请右键本程序，以管理员身份运行。'}
        if (@(Get-AppProcesses).Count) {throw '请先手动退出旧 APP，避免两份程序同时连接。'}
        $exe=$pathBox.Text.Trim('"');$appDir=Split-Path -Parent $exe
        $marker=Join-Path $appDir 'network_diagnostic_build.json'
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {throw '所选目录不是配套的网络诊断 Debug 包，未启动。'}
        $build=Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($file in $build.files) {
            $path=Join-Path $appDir $file.path
            if ((Get-CachedHash $path) -ne $file.sha256) {throw ('诊断文件校验不一致：'+$file.path)}
        }
        $script:Report.mode='debug_raw_and_packet_capture'
        $script:Report.appFiles=@(Get-AppFileEvidence $exe)
        $packet=Join-Path $OutputRoot 'network.etl'
        $filters=& "$env:SystemRoot/System32/pktmon.exe" filter list 2>&1 | Out-String
        [IO.File]::WriteAllText((Join-Path $OutputRoot 'packet_filters.txt'),$filters,[Text.Encoding]::UTF8)
        $script:Report.packetFiltersPreserved=$true
        $result=& "$env:SystemRoot/System32/pktmon.exe" start --capture --pkt-size 0 --trace --provider Microsoft-Windows-TCPIP --provider Microsoft-Windows-WinHttp --level 5 --file-name $packet --file-size 128 --log-mode multi-file 2>&1 | Out-String
        $code=$LASTEXITCODE
        [IO.File]::WriteAllText((Join-Path $OutputRoot 'packet_start.txt'),$result,[Text.Encoding]::UTF8)
        $script:Report.packetStartExitCode=$code
        if ($code -ne 0) {throw '系统抓包启动失败，未启动 APP。请查看 packet_start.txt；不会停止其他已有抓包。'}
        $script:OwnsPacketCapture=$true
        $script:CaptureDirectory=Join-Path $OutputRoot 'live_app_capture'
        New-Item -ItemType Directory -Force -Path $script:CaptureDirectory | Out-Null
        $launch=New-Object Diagnostics.ProcessStartInfo
        $launch.FileName=$exe;$launch.WorkingDirectory=$appDir;$launch.UseShellExecute=$false
        $launch.EnvironmentVariables['RHYTHMQUAKE_NETWORK_DIR']=$script:CaptureDirectory
        $launch.EnvironmentVariables['RQ_STATION_CORE_LIBRARY']=Join-Path $appDir 'rq_station_core.dll'
        $process=[Diagnostics.Process]::Start($launch)
        $script:Report.launchedPid=$process.Id;$script:Report.appLaunches=1
        $script:Recording=$true;$script:StartedAt=Get-Date;$start.Enabled=$false
        $status.AppendText("`r`n系统抓包已启动，APP PID：$($process.Id)。`r`n等待 APP 自报记录器启动；不会因为进程存在就认定成功。`r`n")
    } catch {Stop-NetworkCapture;$status.AppendText("`r`n$($_.Exception.Message)`r`n")}
})
$timer=New-Object Windows.Forms.Timer;$timer.Interval=5000
$timer.Add_Tick({
    if (-not $script:Recording) {return}
    try {
        $elapsed=[int]((Get-Date)-$script:StartedAt).TotalSeconds
        $null=Capture-Snapshot ('sample_'+$elapsed.ToString('000'))
        $session=Join-Path $script:CaptureDirectory 'session.json'
        $state='未确认'
        if (Test-Path -LiteralPath $session) {
            $evidence=Get-Content -LiteralPath $session -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($evidence.pid -eq $script:Report.launchedPid) {$state='已启动';$script:Report.appRecorderConfirmed=$true}
        }
        $form.Text="Debug 网络诊断 · $elapsed / 180 秒 · 原文记录器$state"
        if ($elapsed -ge 15 -and $state -eq '未确认') {
            $status.AppendText("`r`n未确认 APP 记录器启动。系统抓包仍在进行；不能认定明文覆盖。`r`n")
        }
        if ($elapsed -ge 180) {$timer.Stop();$zip=Finish-Report;$script:Saved=$true;$script:Recording=$false;$status.AppendText("`r`n已导出：$zip`r`nAPP 未被关闭，请自行退出以停止连接。`r`n")}
    } catch {$status.AppendText("`r`n采集失败：$($_.Exception.Message)`r`n")}
})
$form.Add_FormClosing({$timer.Stop();try{if(-not $script:Saved){$null=Finish-Report}else{Stop-NetworkCapture}}catch{Stop-NetworkCapture}})
if ($UiSelfTest) {$form.CreateControl();$form.PerformLayout();Save-Json @{passed=$true;apiProbes=0;appLaunches=0;controls=$form.Controls.Count} (Join-Path $OutputRoot 'ui-self-test.json');$form.Dispose();exit 0}
try {$timer.Start();[Windows.Forms.Application]::Run($form)} finally {Stop-NetworkCapture}
