param([int]$TargetPid, [int]$Seconds = 20)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ThreadNames {
 [DllImport("kernel32.dll")] static extern IntPtr OpenThread(uint a, bool i, uint id);
 [DllImport("kernel32.dll")] static extern int GetThreadDescription(IntPtr h, out IntPtr p);
 [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 public static string Name(uint id) {
  IntPtr h = OpenThread(0x0800, false, id), p;
  if (h == IntPtr.Zero) return "";
  try { if (GetThreadDescription(h, out p) != 0) return "";
    try { return Marshal.PtrToStringUni(p); } finally { LocalFree(p); }
  } finally { CloseHandle(h); }
 }
}
'@
$before = @{}
(Get-Process -Id $TargetPid).Threads | ForEach-Object { $before[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds }
Start-Sleep -Seconds $Seconds
(Get-Process -Id $TargetPid).Threads | ForEach-Object {
 if ($before.ContainsKey($_.Id)) { [pscustomobject]@{
   id=$_.Id; name=[ThreadNames]::Name($_.Id)
   cpuMs=$_.TotalProcessorTime.TotalMilliseconds - $before[$_.Id]
 } }
} | Sort-Object cpuMs -Descending | Select-Object -First 25 | ConvertTo-Json
