param([string]$Project, [string]$Exe, [int]$WaitSeconds = 80, [switch]$Continue, [string]$Shot = 'delphi.png')
# One build in the Delphi 13 Community IDE (docs/original-build.md). Community refuses command-line builds, so this
# drives the IDE with real mouse / keyboard input and screen captures only: window messages to the IDE while it
# compiles (WM_GETTEXT, BM_CLICK, PrintWindow) crash or close it.
# Run it from the PowerShell tool (a PowerShell started by Git Bash cannot see the IDE's windows).
# Without -Continue: opens $Project if Delphi is not running, closes a finished build's result dialog, clicks into the
# editor, presses Shift+F9 (Build), waits for the Community EULA reminder and clicks its OK. Then (also with
# -Continue) waits until $Exe changes, Delphi dies or $WaitSeconds pass, and saves a capture of the IDE to
# build/original/captures/$Shot. A build that stops on a compile error leaves the exe untouched: read the capture.
$captures = Join-Path $PSScriptRoot '..\..\build\original\captures'
New-Item -ItemType Directory -Force $captures | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class RolIde {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr a, IntPtr b, string c, string t);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int x, int y, uint d, UIntPtr e);
  public static void Front(IntPtr h) {
    if (GetForegroundWindow() == h) return;
    keybd_event(0x12, 0, 0, UIntPtr.Zero); SetForegroundWindow(h); keybd_event(0x12, 0, 2, UIntPtr.Zero);
    System.Threading.Thread.Sleep(500);
  }
  public static void Click(int x, int y) {
    POINT old; GetCursorPos(out old);
    SetCursorPos(x, y); System.Threading.Thread.Sleep(100);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    System.Threading.Thread.Sleep(300);
    SetCursorPos(old.X, old.Y);
  }
}
'@
function Find-Window([string]$class) {
  $h = [RolIde]::FindWindowEx([IntPtr]::Zero, [IntPtr]::Zero, $class, [NullString]::Value)
  if ($h -ne [IntPtr]::Zero -and [RolIde]::IsWindowVisible($h)) { return $h } else { return [IntPtr]::Zero }
}
function Save-Capture {
  $h = Find-Window 'TAppBuilder'; if ($h -eq [IntPtr]::Zero) { return }
  $r = New-Object RolIde+RECT; $null = [RolIde]::GetWindowRect($h, [ref]$r)
  $bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $captures $Shot))
}

$p = Get-Process bds -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) {
  if ($Continue) { 'Delphi is not open'; return }
  Start-Process "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\bds.exe" -ArgumentList '-pDelphi', '-ns', "`"$Project`""
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep 2
    $p = Get-Process bds -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*Delphi*' } | Select-Object -First 1
    if ($p) { break }
  }
  if (-not $p) { 'Delphi did not come up'; return }
  Start-Sleep 15
  'opened Delphi'
}
$ide = Find-Window 'TAppBuilder'
if ([RolIde]::IsIconic($ide)) { $null = [RolIde]::ShowWindow($ide, 9); Start-Sleep 1 }
$before = $null
if (Test-Path $Exe) { $before = (Get-Item $Exe).LastWriteTime }
if (-not $Continue) {
  [RolIde]::Front($ide)
  if ([RolIde]::GetForegroundWindow() -ne $ide) { 'Delphi not in front, nothing sent'; return }
  $prog = Find-Window 'TProgressForm'
  if ($prog -ne [IntPtr]::Zero) {   # a finished build's result dialog: its OK button
    $pr = New-Object RolIde+RECT; $null = [RolIde]::GetWindowRect($prog, [ref]$pr)
    [RolIde]::Click($pr.R - 76, $pr.B - 25); Start-Sleep 1
  }
  $r = New-Object RolIde+RECT; $null = [RolIde]::GetWindowRect($ide, [ref]$r)
  [RolIde]::Click($r.L + 1150, $r.T + 600)   # into the editor, never the form designer's property fields
  Start-Sleep -Milliseconds 500
  (New-Object -ComObject WScript.Shell).SendKeys('+{F9}')
  'build started'
  $d = [IntPtr]::Zero
  for ($i = 0; $i -lt 30 -and $d -eq [IntPtr]::Zero; $i++) { Start-Sleep 1; $d = Find-Window 'TCENotificationDialog' }
  if ($d -ne [IntPtr]::Zero) {
    Start-Sleep 1
    [RolIde]::Front($ide)
    $dr = New-Object RolIde+RECT; $null = [RolIde]::GetWindowRect($d, [ref]$dr)
    [RolIde]::Click($dr.R - 73, $dr.B - 17)   # the reminder's OK button
    Start-Sleep 1
    if ((Find-Window 'TCENotificationDialog') -ne [IntPtr]::Zero) { 'the EULA reminder is still open'; Save-Capture; return }
  } else { 'no EULA reminder showed: the build may not have started, read the capture' }
}
$t0 = Get-Date
$state = 'still building'
while (((Get-Date) - $t0).TotalSeconds -lt $WaitSeconds) {
  Start-Sleep 2
  $p.Refresh()
  if ($p.HasExited) { $state = 'Delphi crashed (see the Application event log)'; break }
  if ((Test-Path $Exe) -and ((Get-Item $Exe).LastWriteTime -ne $before)) { $state = 'exe written'; Start-Sleep 3; break }
}
"$state after $([int]((Get-Date) - $t0).TotalSeconds)s"
if (-not $p.HasExited) { Save-Capture; "capture: build/original/captures/$Shot" }
