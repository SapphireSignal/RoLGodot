param([int]$Seconds = 30, [string]$Shot = 'original.png', [switch]$Stop, [switch]$Keep, [string]$Keys = '')
# Runs the reference build of the original (docs/original-build.md): stops a running one, copies the fresh exes from
# build/original/src into build/original/run, starts the game server, then the client (which joins the server's
# sandbox test game), waits $Seconds, prints the client log's exceptions and state changes (Error.log) and saves a
# capture of the client window to build/original/captures/$Shot, then stops both (-Keep leaves them running).
# -Keys presses letter / digit keys (real input) in the client first, e.g. -Keys P (the sandbox's capture mode: the
# player HUD instead of the sandbox layout). -Stop only stops a running original.
$run = Join-Path $PSScriptRoot '..\..\build\original\run'
$src = Join-Path $PSScriptRoot '..\..\build\original\src'
$captures = Join-Path $PSScriptRoot '..\..\build\original\captures'
foreach ($n in 'RiseOfLegions', 'RiseOfLegionsGameServer') {
  Get-Process $n -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Confirm:$false }
}
if ($Stop) { 'stopped'; return }
Start-Sleep 1
New-Item -ItemType Directory -Force $captures | Out-Null
# a project not rebuilt since the last prepare_original has no exe in src: run/ keeps the last one
if (Test-Path "$src\RiseOfLegions.exe") { Copy-Item "$src\RiseOfLegions.exe" "$run\" -Force }
if (Test-Path "$src\GameServer\RiseOfLegionsGameServer.exe") {
  Copy-Item "$src\GameServer\RiseOfLegionsGameServer.exe" "$run\GameServer\" -Force
}
Remove-Item "$run\Error.log" -ErrorAction SilentlyContinue
$srv = Start-Process "$run\GameServer\RiseOfLegionsGameServer.exe" -WorkingDirectory "$run\GameServer" -PassThru
Start-Sleep 6
$cl = Start-Process "$run\RiseOfLegions.exe" -WorkingDirectory $run -PassThru
Start-Sleep $Seconds
$srv.Refresh(); $cl.Refresh()
"server alive $(-not $srv.HasExited), client alive $(-not $cl.HasExited)"
if (Test-Path "$run\Error.log") {
  Get-Content "$run\Error.log" | Select-String -Pattern 'EXCEPTION|Entered Gamestate|FMod error' | ForEach-Object { $_.Line }
}
if (-not $cl.HasExited -and $cl.MainWindowHandle -ne [IntPtr]::Zero) {
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
}
'@
  [RolWin]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); $null = [RolWin]::SetForegroundWindow($cl.MainWindowHandle)
  [RolWin]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 700
  if ($Keys -ne '') { "client in front: $([RolWin]::GetForegroundWindow() -eq $cl.MainWindowHandle)" }
  # the client reads the keyboard through DirectInput, which goes by scan code: send it with the key; it handles keys
  # only while the cursor is over its window (CursorInRenderpanel), so the cursor waits there and goes back after
  if ($Keys -ne '') {
    $w = New-Object RolWin+RECT; $null = [RolWin]::GetWindowRect($cl.MainWindowHandle, [ref]$w)
    $old = New-Object RolWin+POINT; $null = [RolWin]::GetCursorPos([ref]$old)
    $null = [RolWin]::SetCursorPos([int](($w.L + $w.R) / 2), [int](($w.T + $w.B) / 2)); Start-Sleep -Milliseconds 300
    foreach ($k in $Keys.ToUpperInvariant().ToCharArray()) {
      $vk = [byte][char]$k; $scan = [byte][RolWin]::MapVirtualKey($vk, 0)
      [RolWin]::keybd_event($vk, $scan, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 150
      [RolWin]::keybd_event($vk, $scan, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 1000
    }
    $null = [RolWin]::SetCursorPos($old.X, $old.Y)
  }
  $r = New-Object RolWin+RECT; $null = [RolWin]::GetWindowRect($cl.MainWindowHandle, [ref]$r)
  $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $captures $Shot))
  "capture: build/original/captures/$Shot"
}
if (-not $Keep) {
  foreach ($p in $cl, $srv) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Confirm:$false } }
  'stopped'
}
