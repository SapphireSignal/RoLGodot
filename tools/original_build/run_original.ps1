param([int]$Seconds = 30, [string]$Shot = 'original.png', [switch]$Stop, [switch]$Keep, [string]$Keys = '',
  [switch]$Lobby, [string]$Steps = '')
# Runs the reference build of the original (docs/original-build.md): stops a running one, copies the fresh exes from
# build/original/src into build/original/run, starts the game server, then the client (which joins the server's
# sandbox test game), waits $Seconds, prints the client log's exceptions and state changes (Error.log) and saves a
# capture of the client window to build/original/captures/$Shot, then stops both (-Keep leaves them running).
# -Keys presses letter / digit keys (real input) in the client first, e.g. -Keys P (the sandbox's capture mode: the
# player HUD instead of the sandbox layout). -Lobby starts the client in its real login and main menu against the
# local master stand-in (master_standin.py, log in build/original/standin.log) instead of the sandbox test game.
# -Stop only stops a running original.
$run = Join-Path $PSScriptRoot '..\..\build\original\run'
$src = Join-Path $PSScriptRoot '..\..\build\original\src'
$ref = Join-Path $PSScriptRoot '..\..\reference\rise-of-legions'
$captures = Join-Path $PSScriptRoot '..\..\build\original\captures'
function Stop-Original {
  foreach ($n in 'RiseOfLegions', 'RiseOfLegionsGameServer') {
    Get-Process $n -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Confirm:$false }
  }
  Get-CimInstance Win32_Process -Filter "Name like 'python%'" | Where-Object { $_.CommandLine -like '*master_standin.py*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Confirm:$false }
}
Stop-Original
if ($Stop) { 'stopped'; return }
# the settings of the mode: the snapshot's (sandbox test game) or the lobby's (stand-in, no test game, HTTP broker
# fallback, no login queue)
$debug = Get-Content "$ref\DebugSettings.ini" -Raw
$connection = Get-Content "$ref\SettingsConnection.ini" -Raw
if ($Lobby) {
  $debug = $debug.Replace("`nUseLocalTestServer=True", "`nUseLocalTestServer=False")
  $debug = $debug.Replace("[General]", "[General]`r`nBypassLoginQueue=True`r`nForceBrokerFallback=True")
  $debug = $debug.Replace('WebApiServer=https://riseoflegions.com', 'WebApiServer=http://127.0.0.1:8765')
  $connection = $connection.Replace('WebApiServer=https://riseoflegions.com', 'WebApiServer=http://127.0.0.1:8765')
}
[IO.File]::WriteAllText("$run\DebugSettings.ini", $debug)
[IO.File]::WriteAllText("$run\SettingsConnection.ini", $connection)
Start-Sleep 1
New-Item -ItemType Directory -Force $captures | Out-Null
# a project not rebuilt since the last prepare_original has no exe in src: run/ keeps the last one
if (Test-Path "$src\RiseOfLegions.exe") { Copy-Item "$src\RiseOfLegions.exe" "$run\" -Force }
if (Test-Path "$src\GameServer\RiseOfLegionsGameServer.exe") {
  Copy-Item "$src\GameServer\RiseOfLegionsGameServer.exe" "$run\GameServer\" -Force
}
Remove-Item "$run\Error.log" -ErrorAction SilentlyContinue
if ($Lobby) {
  $srv = Start-Process python -ArgumentList "`"$PSScriptRoot\master_standin.py`"" -WindowStyle Hidden -PassThru
  Start-Sleep 3
} else {
  $srv = Start-Process "$run\GameServer\RiseOfLegionsGameServer.exe" -WorkingDirectory "$run\GameServer" -PassThru
  Start-Sleep 6
}
$cl = Start-Process "$run\RiseOfLegions.exe" -WorkingDirectory $run -PassThru
Start-Sleep $Seconds
$srv.Refresh(); $cl.Refresh()
"server alive $(-not $srv.HasExited), client alive $(-not $cl.HasExited)"
if (Test-Path "$run\Error.log") {
  Get-Content "$run\Error.log" | Select-String -Pattern 'EXCEPTION|Entered Gamestate|FMod error|Server |Login|Failed|metaserver|broker|Fallback' | ForEach-Object { $_.Line }
}
if (-not $cl.HasExited) {
  Add-Type -AssemblyName System.Drawing
  Add-Type @'
using System; using System.Runtime.InteropServices;
public static class RolWin {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
}
'@
  # the game's form by its class: a debug build also opens a console, which can be the process's "main window"
  $hwnd = [RolWin]::FindWindow('THauptform', $null)
  if ($hwnd -eq [IntPtr]::Zero) { $hwnd = $cl.MainWindowHandle }
  [RolWin]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); $null = [RolWin]::SetForegroundWindow($hwnd)
  [RolWin]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 700
  if ($Keys -ne '') { "client in front: $([RolWin]::GetForegroundWindow() -eq $hwnd)" }
  function Get-Rect { $w = New-Object RolWin+RECT; $null = [RolWin]::GetWindowRect($hwnd, [ref]$w); $w }
  function Save-Shot([string]$name) {
    $r = Get-Rect
    $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
    $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $captures $name)); $g.Dispose(); $bmp.Dispose()
    "capture: build/original/captures/$name"
  }
  # the client reads the keyboard through DirectInput, which goes by scan code: send it with the key; it handles keys
  # only while the cursor is over its window (CursorInRenderpanel), so the cursor waits there and goes back after
  function Send-Key([char]$k, [int]$x, [int]$y) {
    $r = Get-Rect; $old = New-Object RolWin+POINT; $null = [RolWin]::GetCursorPos([ref]$old)
    $null = [RolWin]::SetCursorPos($r.L + $x, $r.T + $y); Start-Sleep -Milliseconds 300
    $vk = [byte][char]::ToUpperInvariant($k); $scan = [byte][RolWin]::MapVirtualKey($vk, 0)
    [RolWin]::keybd_event($vk, $scan, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150
    [RolWin]::keybd_event($vk, $scan, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
    $null = [RolWin]::SetCursorPos($old.X, $old.Y)
  }
  # a left click at a window position (the capture's pixel coordinates), real mouse input
  function Send-Click([int]$x, [int]$y) {
    $r = Get-Rect; $old = New-Object RolWin+POINT; $null = [RolWin]::GetCursorPos([ref]$old)
    $null = [RolWin]::SetCursorPos($r.L + $x, $r.T + $y); Start-Sleep -Milliseconds 250
    [RolWin]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 120
    [RolWin]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 250
    # leave the game's last cursor position on an empty spot (right edge, middle), so captures show no hover tooltips
    $null = [RolWin]::SetCursorPos($r.R - 6, [int](($r.T + $r.B) / 2)); Start-Sleep -Milliseconds 250
    $null = [RolWin]::SetCursorPos($old.X, $old.Y)
  }
  $center = Get-Rect
  foreach ($k in $Keys.ToCharArray()) {
    Send-Key $k (($center.R - $center.L) / 2) (($center.B - $center.T) / 2); Start-Sleep -Milliseconds 700
  }
  # -Steps "click:x,y;key:P;wait:ms;shot:name.png": a scripted walk through the client, captures on the way
  foreach ($step in ($Steps -split ';' | Where-Object { $_ -ne '' })) {
    $kind, $arg = $step -split ':', 2
    switch ($kind) {
      'click' { $x, $y = $arg -split ','; Send-Click ([int]$x) ([int]$y) }
      'key' { Send-Key ([char]$arg) (($center.R - $center.L) / 2) (($center.B - $center.T) / 2) }
      'wait' { Start-Sleep -Milliseconds ([int]$arg) }
      'shot' { Save-Shot $arg }
      default { "unknown step: $step" }
    }
  }
  Save-Shot $Shot
}
if ($Lobby -and (Test-Path "$run\..\standin.log")) {
  $calls = @(Get-Content "$run\..\standin.log")
  "stand-in: $($calls.Count) calls, not 200: $(@($calls | Where-Object { $_ -notmatch ' -> 200,' }).Count)"
}
if (-not $Keep) {
  Stop-Original
  'stopped'
}
