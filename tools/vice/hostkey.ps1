param([string]$Key = " ", [int]$HoldMs = 200, [string]$Title = "VICE")
# Sends a real key down/up to the VICE window so the emulated CIA matrix sees it.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KB {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
}
"@
$p = Get-Process | Where-Object { $_.MainWindowTitle -like "*$Title*" } | Select-Object -First 1
if (-not $p) { Write-Error "window not found"; exit 1 }
[KB]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 300
$map = @{ " " = 0x20; "ENTER" = 0x0D; "F1" = 0x70; "F3" = 0x72; "F5" = 0x74; "F7" = 0x76; "UP"=0x26; "DOWN"=0x28; "LEFT"=0x25; "RIGHT"=0x27 }
0..9 | ForEach-Object { $map["N$_"] = 0x60 + $_ }
foreach ($k in $Key.Split(",")) {
  if ($map.ContainsKey($k)) { $vk = $map[$k] } else { $vk = [byte][char]$k.ToUpper() }
  $sc = [KB]::MapVirtualKey($vk, 0)
  [KB]::keybd_event([byte]$vk, [byte]$sc, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds $HoldMs
  [KB]::keybd_event([byte]$vk, [byte]$sc, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 300
}
