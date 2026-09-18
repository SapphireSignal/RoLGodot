# Runs the headless test suite with a hard timeout. Exit code 0 = all green.
param([int]$TimeoutSec = 400)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$godot = 'D:\Godot\Godot_v4.7.1-stable_win64_console.exe'
$logDir = Join-Path $root 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

function Invoke-Godot([string[]]$GodotArgs, [string]$LogName) {
    $log = Join-Path $logDir $LogName
    $allArgs = @('--headless', '--path', $root, '--log-file', $log) + $GodotArgs
    $p = Start-Process -FilePath $godot -ArgumentList $allArgs -NoNewWindow -PassThru
    $null = $p.Handle  # cache the handle so ExitCode is readable after exit
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        Stop-Process -Id $p.Id -Force
        Write-Host "TIMEOUT after $TimeoutSec s: $LogName"
        return 124
    }
    return $p.ExitCode
}

# Transpiler unit tests; with reference/ present also check the generated scripts are up to date
$pyCode = 0
& python -m unittest discover -s (Join-Path $root 'tools\tests')
if ($LASTEXITCODE -ne 0) { $pyCode = 1 }
if (Test-Path (Join-Path $root 'reference\rise-of-legions\Scripts')) {
    & python (Join-Path $root 'tools\transpile_scripts.py') --check
    if ($LASTEXITCODE -ne 0) { $pyCode = 1 }
    & python (Join-Path $root 'tools\convert_maps.py') --check
    if ($LASTEXITCODE -ne 0) { $pyCode = 1 }
    & python (Join-Path $root 'tools\convert_cards.py') --check
    if ($LASTEXITCODE -ne 0) { $pyCode = 1 }
    & python (Join-Path $root 'tools\import_graphics.py') --check
    if ($LASTEXITCODE -ne 0) { $pyCode = 1 }
} else {
    Write-Host 'reference/ missing: skipped the generated-scripts check'
}

$null = Invoke-Godot @('--import') 'import.log'
$code = Invoke-Godot @('--script', 'res://tests/run_tests.gd') 'tests.log'
# GDScript runtime errors (invalid access, null calls, ...) do not fail a check, so count them from the log
$scriptErrors = @(Select-String -Path (Join-Path $logDir 'tests.log') -Pattern '^SCRIPT ERROR:' -ErrorAction SilentlyContinue).Count
Write-Host "runtime script errors: $scriptErrors"
if ($code -eq 0 -and $scriptErrors -gt 0) { $code = 1 }
if ($code -eq 0) { $code = $pyCode }

# Launcher smoke tests: start the game exactly as the owner does (play.bat, windowed), press one of the main scene's
# viewer buttons (Mesh viewer: a mesh is drawn; Map viewer: terrain, water and vegetation of the Classic map are
# built and a frame is drawn). The game writes the result file and quits by itself.
foreach ($viewer in @('mesh', 'map')) {
    $smoke = Join-Path $logDir "smoke_test_$viewer.txt"
    if (Test-Path $smoke) { Remove-Item $smoke }
    & cmd /c (Join-Path $root 'play.bat') -- "--smoke-test=$smoke" "--smoke-viewer=$viewer"
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path $smoke) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Milliseconds 500
    $smokeResult = if (Test-Path $smoke) { (Get-Content $smoke -Raw).Trim() } else { 'FAIL no result within 60 s' }
    Write-Host "play.bat smoke test ($viewer viewer): $smokeResult"
    if (-not $smokeResult.StartsWith('ok')) {
        Get-Process -Name 'Godot_v4.7.1-stable_win64' -ErrorAction SilentlyContinue | Stop-Process -Force
        if ($code -eq 0) { $code = 1 }
    }
}
exit $code
