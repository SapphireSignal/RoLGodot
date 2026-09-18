# CONTINUE

Hand-off note for the next session. Read `CLAUDE.md` first, then this.

## The owner's brief (session 1, 2026-09-18)
- Port **Rise of Legions** (RoL) to **Godot** as a strict 1:1 replica of its **last update before it became
  Crystal Clash**. Not Crystal Clash, not a new game. Every detail the same: units, cards, numbers, effects,
  sounds, UI, little touches.
- The original devs gave the owner permission to use and do anything with the game and its source.
- Build it in parts, like a professional dev team would, with care. Claude acts as the returning lead dev.
- Research the original source on GitHub deeply and populate this folder with everything the port needs
  (docs, tools, data extractors), but only what is actually needed (lean repo, lean Windows build).
- Delphi is installed on the owner's PC if we need to build or run original tools.
- `play.bat` to launch the game, plus any other standard setup a real project has.
- Professional-looking GitHub repo (README, license notes, structure). Don't claim to be a real team.
- A playful "dev team" roster: named agent roles with a token "salary", brought in only when needed
  (agents cost the owner's usage; see the global rule "Subagents only when needed").
- Do not read or write the owner's other repos. Stay inside this folder.
- Claude may improve the global/project instructions if something would help.

## Environment (verified)
- Godot 4.7.1: `D:\Godot\Godot_v4.7.1-stable_win64.exe` (+ `_console.exe` for headless runs)
- Python 3.14.6 (`python`), Git, GitHub CLI logged in as SapphireSignal
- Delphi / RAD Studio 37.0: `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\` (dcc32, dcc64, bds)
- Our repo: https://github.com/SapphireSignal/RoLGodot (public)

## Research so far
- Original source: https://github.com/BrokenGamesUG/rise-of-legions (~720 MB; Delphi/Pascal client
  and server, game data, assets). Last pushed 2026-09-15.
- The owner mentioned a second repo with their Delphi engine code; not located yet. Search the
  BrokenGamesUG org (`gh repo list BrokenGamesUG`).

## Next steps
1. List the BrokenGamesUG repos; read the RoL repo README and tree (via `gh api`, no full download yet).
2. Work out which commit/tag is the last RoL version before the Crystal Clash rebrand (check history
   for the rename) and pin it as the single source of truth. Record the commit hash in `docs/`.
3. Clone that snapshot into a git-ignored `reference/` folder (with `.gdignore`).
4. Write `docs/`: architecture of the original (client, server, data formats, asset formats),
   the port plan in phases, and the gap list of user-visible behaviour.
5. Scaffold the Godot 4.7 project, the headless test runner (hard timeout, compile sweep), `play.bat`,
   README, `.gitignore`, and the export preset that leaves out tools/tests/docs/reference.
