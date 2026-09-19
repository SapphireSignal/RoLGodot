# Builds the C++ core (native/, docs/native.md) into bin/rol_native.windows.<target>.x86_64.dll with SCons and the
# Visual Studio C++ tools (found by SCons itself). Incremental: SCons rebuilds only what changed. Fetches godot-cpp
# first if it is missing. Exit code 1 on a failed build.
#   tools\build_native.ps1              the debug library (what play.bat and the tests load)
#   tools\build_native.ps1 -Release     also the release library (exports)
param([switch]$Release)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$native = Join-Path $root 'native'
if (-not (Test-Path (Join-Path $native 'godot-cpp\SConstruct')) -or -not (Test-Path (Join-Path $native 'extension_api.json'))) {
    & (Join-Path $PSScriptRoot 'fetch_godot_cpp.ps1')
}
$jobs = [Environment]::ProcessorCount
$targets = @('template_debug')
if ($Release) { $targets += 'template_release' }
foreach ($target in $targets) {
    Push-Location $native
    try {
        # optimize=speed: the debug library runs the game too (play.bat, tests); it keeps Godot's debug checks
        python -m SCons -Q "-j$jobs" platform=windows "target=$target" optimize=speed
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($code -ne 0) {
        Write-Host "native build FAILED ($target)"
        exit 1
    }
}
Write-Host "native build ok: $($targets -join ', ')"
exit 0
