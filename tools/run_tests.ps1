# Runs the headless test suite with a hard timeout. Exit code 0 = all green.
param([int]$TimeoutSec = 180)
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

$null = Invoke-Godot @('--import') 'import.log'
$code = Invoke-Godot @('--script', 'res://tests/run_tests.gd') 'tests.log'
exit $code
