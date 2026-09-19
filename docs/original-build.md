# The reference build of the original

The original client and game server, built from `reference/rise-of-legions` with the installed Delphi 13 Community,
run a local sandbox game without the closed master server. It is the reference the port is compared against:
captures, timings, behaviour. First run on 2026-09-19: the client joins the server's sandbox test game and draws the
Single map (nexus, build grid, vegetation, toon outlines); the HUD does not lay out yet (see "Open").

Everything lives in `build/original/` (git-ignored, `.gdignore`d): `src/` the patched code copy, `run/` the game
folder, `captures/`. The snapshot is never modified: `run/` links to its data folders.

## Steps
1. `python tools/original_build/prepare_original.py`: copies the code, applies the changes below (each checked; a
   missing anchor stops it), lays out `run/`. `--run-only` redoes only `run/`.
2. Build both projects in Delphi, from the PowerShell tool (a PowerShell started by Git Bash cannot see the IDE):
   `tools\original_build\delphi_build.ps1 -Project <dproj> -Exe <exe>` for
   `build\original\src\GameServer\RiseOfLegionsGameServer.dproj` (exe next to it) and
   `build\original\src\RiseOfLegions.dproj` (exe `build\original\src\RiseOfLegions.exe`). A second project is opened in
   the running IDE with Ctrl+F11 (Open Project), path, Enter; answer the "save changes" prompt.
   A build that stops on a compile error leaves the exe as it was: read `build/original/captures/<Shot>`.
3. `tools\original_build\run_original.ps1 [-Seconds 30] [-Shot name.png]`: copies the exes into `run/`, starts the
   server, then the client, prints the client log's exceptions and states, captures the client window.
   `-Stop` ends a running original.
4. Crash addresses: the client logs `[EXCEPTION] ... (offset XXXXXXXX)`;
   `python tools/original_build/resolve_map.py build/original/src/RiseOfLegions.map <offset>` names the function and
   line (the map is written by every client build).

## Delphi 13 Community: what the IDE automation has to respect
- Community refuses `dcc32` and MSBuild ("does not support command line compiling"), and `bds -b` does nothing:
  only the IDE builds.
- Every build shows a "Community Edition EULA Reminder" (`TCENotificationDialog`); the build waits for its OK.
  A `BM_CLICK` sent to that button closes the IDE: click it with the real mouse.
- Never send the IDE window messages while it compiles (`WM_GETTEXT` of the build dialog, `PrintWindow`): it crashes
  (APPCRASH in `clr.dll` in the Application event log). Watch the output files and copy the screen instead.
- Shift+F9 is swallowed when the form designer's property field has the focus: click into the editor first.
- Code Insight must be "Delphi (Classic Code Insight)" (Tools > Options > Editor > Language > Code Insight): the
  default language server (`DelphiLSP.exe`) crash-loops on this code and takes the IDE down with it. Set once on the
  owner's Delphi (2026-09-19).
- The IDE compiles open editor buffers, not the files on disk: close a tab before changing its file from outside.
- The owner's screens: two monitors; captures of the IDE copy its own window rectangle only.

## The changes (prepare_original.py) and why
| Where | Change | Why |
| --- | --- | --- |
| all `.pas/.dpr/.inc` | Windows-1252 to UTF-8 with BOM | Delphi 13 reads BOM-less files as UTF-8 (`TasteRücktaste`) |
| madExcept | stub unit `tools/original_build/madExcept.pas`, server `.dpr` drops the mad* units | commercial library, not installed |
| server `.dproj` | default platform Win32 | the Win64 compiler crashed the IDE |
| `uTPLb_MemoryStreamPool` | `Realloc(var NativeInt)` | the RTL signature changed |
| `dwsRTTIExposer` | the 23-name TTypeKind table without `{$IFDEF VER330}` | exact-version check misses Delphi 13 |
| `Engine.Collision` | `AChildren` without the nested generic parameter | crashes Delphi 13's compiler |
| client `.dpr/.dproj` | the engine's `FixedDX11Header\Winapi.D3D11` removed | clashes with Delphi 13's precompiled `FMX.Context.DX11` |
| client `.dproj` | detailed map file | crash addresses |
| `Engine.GfxApi` + `FMX.Canvas.D2D` | fonts through `TFontManager.AddCustomFontFromFile`; the patched FMX unit made from Delphi 13's source with only the original's implementation changes (grayscale text antialiasing, D2D without the theme check) | the original patched Embarcadero's FMX (`Engine/FixedDX11Header/FMX.Canvas.D2D.diff`: `LoadFontFromFile`, per-range colours, GDI DC leak); Delphi 13's FMX has the rest built in, and a changed interface breaks the precompiled FMX units |
| `Engine.Math.Collision3D` `RAABB.Create` | the `Min <= Max` assert as "some component greater", raising with the caller | NaN semantics, below |
| `BaseConflictMainUnit` | the exception handler logs each distinct exception | the original swallows every exception silently |
| `BaseConflict.Game.Client` destructor | `ClearAction` only when the component exists | a failing `Create` hid its error behind an access violation |

## NaN comparisons differ between the original and everything else
Delphi 10.1's Win32 compiler compares floats with x87 `FCOMP`/`SAHF` and branches as for unsigned integers: an
unordered compare (a NaN operand) sets ZF, PF and CF, so `=`, `<` and `<=` are **true** and `>`, `>=` false. Delphi 13
(and IEEE, and GDScript / C++) make every NaN compare false except `<>`. The engine uses NaN as a marker
(`RVector3.EMPTY` has X = NaN), so any original code comparing such values behaves like Delphi 10.1, not like IEEE.
The port must keep the original's results where it matters (see `docs/original-architecture.md`, gotchas).

## Open
- The HUD collapses into the top-left corner (every element at 0,0, text overlapping); no exception is logged, the
  language setting (`[General] Language=en` in `run/Settings.ini`) did not change it. Suspects: another Delphi 13
  difference in the GUI engine's layout (`Engine.GUI`, `Engine.dXML`), e.g. NaN compares, float parsing, RTTI.
- Captures of the same views as the map viewer, then side by side comparisons (CONTINUE.md).
