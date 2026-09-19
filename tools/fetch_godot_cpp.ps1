# Fetches godot-cpp (the official C++ bindings for GDExtension) into native/godot-cpp (git-ignored) at the pinned
# commit, and dumps the extension API of the project's Godot build into native/extension_api.json, which godot-cpp is
# built against (custom_api_file): the bindings then match Godot 4.7.1 exactly. See docs/native.md.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$native = Join-Path $root 'native'
$dir = Join-Path $native 'godot-cpp'
$url = 'https://github.com/godotengine/godot-cpp.git'
$commit = '507ed9d840c01a3c5b2a39af8bb4000bfac30bf5'  # master, 2026-09-19 (no 4.7 branch; built against our API dump)
$godot = 'D:\Godot\Godot_v4.7.1-stable_win64_console.exe'

New-Item -ItemType Directory -Force $native | Out-Null
if (-not (Test-Path (Join-Path $dir '.git'))) {
    git init --quiet $dir
    git -C $dir remote add origin $url
}
git -C $dir -c core.autocrlf=false fetch --quiet --depth 1 origin $commit
if ($LASTEXITCODE -ne 0) { throw 'fetch failed: godot-cpp' }
git -C $dir -c core.autocrlf=false checkout --quiet FETCH_HEAD
if ($LASTEXITCODE -ne 0) { throw 'checkout failed: godot-cpp' }
Write-Host "godot-cpp at $(git -C $dir rev-parse HEAD)"

# the extension API of the Godot build the project runs on
Push-Location $native
try {
    & $godot --headless --dump-extension-api | Out-Null
} finally {
    Pop-Location
}
if (-not (Test-Path (Join-Path $native 'extension_api.json'))) { throw 'extension_api.json was not written' }
Write-Host 'native/extension_api.json dumped from' $godot
