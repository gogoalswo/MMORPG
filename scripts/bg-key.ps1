<#
  Press a key in the game window WITHOUT focusing it (Windows only).

  Test tool for the anti-macro work: it does what a background macro
  does - PostMessage WM_KEYDOWN / WM_KEYUP straight into the window's
  message queue - so we can check that the game ignores it.
  The foreground window is printed before and after to prove focus
  never moved.

    powershell -ExecutionPolicy Bypass -File scripts\bg-key.ps1
    ... -Key 2 -Count 10 -IntervalMs 500
    ... -Title "MMORPG (DEBUG)"     game started from the editor
    ... -Hwnd 0x1A2B3C              exact window

  ASCII only: PowerShell 5.1 reads a BOM-less .ps1 in the ANSI code
  page, so UTF-8 Korean comments turn into garbage.
  Korean notes: docs/features/background-input.md
#>
param(
  [string]$Key = '1',
  [int]$Count = 1,
  [int]$IntervalMs = 1000,
  [int]$HoldMs = 50,
  [string]$Title = 'MMORPG',
  [string]$Hwnd = ''
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class BgKey {
  [DllImport("user32.dll", SetLastError = true)] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);

  public static string Title(IntPtr h) {
    var sb = new StringBuilder(256);
    GetWindowText(h, sb, sb.Capacity);
    return sb.ToString();
  }

  // lParam bits: 0-15 repeat count, 16-23 scan code, 30 previous state, 31 transition
  static IntPtr L(long v) { return IntPtr.Size == 8 ? new IntPtr(v) : new IntPtr(unchecked((int)v)); }

  public static bool Tap(IntPtr h, uint vk, int holdMs) {
    long scan = MapVirtualKey(vk, 0);
    long down = 1L | (scan << 16);
    long up = down | (1L << 30) | (1L << 31);
    if (!PostMessage(h, 0x0100, new IntPtr(vk), L(down))) return false;   // WM_KEYDOWN
    System.Threading.Thread.Sleep(holdMs);
    return PostMessage(h, 0x0101, new IntPtr(vk), L(up));                 // WM_KEYUP
  }
}
'@

if ($Key.Length -ne 1 -or $Key.ToUpper() -notmatch '^[0-9A-Z]$') {
  Write-Error "Key must be one character 0-9 or A-Z (got '$Key')"; exit 2
}
# For 0-9 and A-Z the virtual-key code is the ASCII code
$vk = [uint32][char]$Key.ToUpper()

if ($Hwnd) {
  $target = [IntPtr][Convert]::ToInt64($Hwnd, 16)
} else {
  # The editor title is "MMORPG - Godot Engine"; skip it, we want the game
  $proc = Get-Process | Where-Object {
    $_.MainWindowHandle -ne 0 -and
    $_.MainWindowTitle -like "*$Title*" -and
    $_.MainWindowTitle -notlike '*Godot Engine*'
  } | Select-Object -First 1
  if (-not $proc) { Write-Error "No window with '$Title' in its title. Start the game first."; exit 1 }
  $target = $proc.MainWindowHandle
}
if (-not [BgKey]::IsWindow($target)) { Write-Error "Not a window: $target"; exit 1 }

$fgBefore = [BgKey]::GetForegroundWindow()
'target     : 0x{0:X} "{1}"' -f $target.ToInt64(), [BgKey]::Title($target)
'foreground : 0x{0:X} "{1}"' -f $fgBefore.ToInt64(), [BgKey]::Title($fgBefore)
if ($fgBefore -eq $target) { Write-Warning 'The game window is focused - click another window first, or this is not a background test.' }

for ($i = 1; $i -le $Count; $i++) {
  if (-not [BgKey]::Tap($target, $vk, $HoldMs)) { Write-Error "PostMessage failed (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"; exit 1 }
  "[$i/$Count] key '$Key' posted"
  if ($i -lt $Count) { Start-Sleep -Milliseconds $IntervalMs }
}

$fgAfter = [BgKey]::GetForegroundWindow()
'foreground : 0x{0:X} "{1}"  ({2})' -f $fgAfter.ToInt64(), [BgKey]::Title($fgAfter), $(if ($fgAfter -eq $fgBefore) { 'unchanged' } else { 'CHANGED' })
