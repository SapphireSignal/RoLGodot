# Clones the pinned original Rise of Legions sources into reference/ (git-ignored, not exported).
# The pinned commits are the single source of truth for the port; see docs/source-of-truth.md.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ref = Join-Path $root 'reference'
New-Item -ItemType Directory -Force $ref | Out-Null
# Keep Godot from importing anything in here.
$gdignore = Join-Path $ref '.gdignore'
if (-not (Test-Path $gdignore)) { New-Item -ItemType File $gdignore | Out-Null }

$repos = @(
    @{ Name = 'rise-of-legions'; Url = 'https://github.com/BrokenGamesUG/rise-of-legions.git'; Commit = '96d5b8e45296d67ae05d9e752ab44dd90c5116fe' },
    @{ Name = 'delphi3d-engine'; Url = 'https://github.com/BrokenGamesUG/delphi3d-engine.git'; Commit = '7c745ef3634437ef3eeee407d34b15baa3a693ce' }
)

foreach ($r in $repos) {
    $dir = Join-Path $ref $r.Name
    if (-not (Test-Path (Join-Path $dir '.git'))) {
        git clone --no-checkout $r.Url $dir
        if ($LASTEXITCODE -ne 0) { throw "clone failed: $($r.Name)" }
    }
    git -C $dir -c core.autocrlf=false checkout --quiet $r.Commit
    if ($LASTEXITCODE -ne 0) { throw "checkout failed: $($r.Name)" }
    Write-Host "$($r.Name) at $(git -C $dir rev-parse HEAD)"
}
