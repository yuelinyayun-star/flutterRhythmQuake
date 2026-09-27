$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$ports = '21','80','443','888','3306','3389','5985','8080','8765','8787'
$rules = @(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue |
    ForEach-Object {
        $rule=$_
        Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue |
            Where-Object { $_.Protocol -in 'TCP',6 -and ($_.LocalPort -eq 'Any' -or $_.LocalPort -in $ports) } |
            ForEach-Object { [pscustomobject]@{Name=$rule.DisplayName;Profile=[string]$rule.Profile;LocalPort=[string]$_.LocalPort} }
    })
[pscustomobject]@{
    CapturedAt=[DateTime]::UtcNow.ToString('o')
    Profiles=Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction
    InboundAllowRules=$rules
} | ConvertTo-Json -Depth 5 -Compress
