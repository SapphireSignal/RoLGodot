param([int]$Seconds = 30, [string]$Shot = 'original.png', [switch]$Stop)
# Runs the reference build of the original (docs/original-build.md): stops a running one, copies the fresh exes from
# build/original/src into build/original/run, starts the game server, then the client (which joins the server's
# sandbox test game), waits $Seconds, prints the client log's exceptions and state changes (Error.log) and saves a
# capture of the client window to build/original/captures/$Shot. -Stop only stops a running original.
$run = Join-Path $PSScriptRoot '..\..\build\original\run'
$src = Join-Path $PSScriptRoot '..\..\build\original\src'
$captures = Join-Path $PSScriptRoot '..\..\build\original\captures'
foreach ($n in 'RiseOfLegions', 'RiseOfLegionsGameServer') {
  Get-Process $n -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Confirm:$false }
}
if ($Stop) { 'stopped'; return }
Start-Sleep 1
New-Item -ItemType Directory -Force $captures | Out-Null
Copy-Item "$src\RiseOfLegions.exe" "$run\" -Force
Copy-Item "$src\GameServer\RiseOfLegionsGameServer.exe" "$run\GameServer\" -Force
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
}
'@
  [RolWin]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); $null = [RolWin]::SetForegroundWindow($cl.MainWindowHandle)
  [RolWin]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 700
  $r = New-Object RolWin+RECT; $null = [RolWin]::GetWindowRect($cl.MainWindowHandle, [ref]$r)
  $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $captures $Shot))
  "capture: build/original/captures/$Shot"
}
