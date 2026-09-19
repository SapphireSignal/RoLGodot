# The reference build of the original

The original client and game server, built from `reference/rise-of-legions` with the installed Delphi 13 Community,
run a local sandbox game without the closed master server. It is the reference the port is compared against:
captures, timings, behaviour. First run on 2026-09-19: the client joins the server's sandbox test game and draws the
Single map (nexus, build grid, vegetation, toon outlines); since the CRLF data layout (below) the HUD lays out too,
and capture mode (P) shows the player HUD: the in-game reference pictures come from here.

Everything lives in `build/original/` (git-ignored, `.gdignore`d): `src/` the patched code copy, `run/` the game
folder, `captures/`. The snapshot is never modified.

## The data needs CRLF line ends
The snapshot stores every text file with LF (`git ls-files --eol`: 1353 `i/lf`, git normalised them on the devs'
Windows machines, where `autocrlf` checked them out with CRLF, as the shipped game had them). The original's parsers
split on `sLineBreak` (CRLF): the stylesheets (`TGUIStyleManager.LoadStylesFromText`, whose first-load errors were
ignored, so every class style was missing and the HUD collapsed into the top-left corner), the shader block
composition (`Engine.GfxApi.pas`), `Engine.Terrain.pas`, `Engine.DX11Api.pas`. So `run/Graphics`, `Maps`, `Scripts`,
`Lang` are a mirror as a CRLF checkout would be: git's text files written with CRLF, every other file hard-linked to
the snapshot (`mirror_crlf` in `prepare_original.py`). Not a bug of the original and not a Delphi 13 difference.

## Steps
1. `python tools/original_build/prepare_original.py`: copies the code, applies the changes below (each checked; a
   missing anchor stops it), lays out `run/`. `--run-only` redoes only `run/`. It overwrites in place (a running IDE
   holds the folders open) and keeps the `.dcu` files; close Delphi before rerunning it anyway (the IDE compiles its
   open editor buffers, and a file changed under it can prompt).
2. Build both projects in Delphi, from the PowerShell tool (a PowerShell started by Git Bash cannot see the IDE):
   `tools\original_build\delphi_build.ps1 -Project <dproj> -Exe <exe>` for
   `build\original\src\GameServer\RiseOfLegionsGameServer.dproj` (exe next to it) and
   `build\original\src\RiseOfLegions.dproj` (exe `build\original\src\RiseOfLegions.exe`). A second project is opened in
   the running IDE with Ctrl+F11 (Open Project), path, Enter; answer the "save changes" prompt.
   A build that stops on a compile error leaves the exe as it was: read `build/original/captures/<Shot>`.
3. `tools\original_build\run_original.ps1 [-Seconds 30] [-Shot name.png] [-Keys P] [-Keep]`: copies the exes into
   `run/`, starts the server, then the client, prints the client log's exceptions and states, captures the client
   window, stops both (`-Keep` leaves them running; `-Stop` only ends a running original). `-Keys` presses keys in the
   client first (P = the sandbox's capture mode: the player HUD instead of the sandbox layout). The client reads the
   keyboard through DirectInput (keys go by scan code) and handles keys only while the cursor is over its window
   (`CursorInRenderpanel`, `Gamestates.pas:2685`): the script parks the owner's cursor there for the presses.
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
| `Engine.Log` `HLog.LogOnce`, `BaseConflictMainUnit` `GUI.Erroroutput`, `Engine.dXML`, `Engine.GUI` | each distinct GUI style error, dXML expression error (elDebug), console message and stylesheet load error goes to `Error.log` once (`[GUI]`, `[dXML]`, `[CONSOLE]`, `[STYLE]`); `HLog.Console` opens no console window | the client dropped them all; the DEBUG console popped up over the game and took clicks and captures; missing `_Hover` / `_Down` / `_Disabled` textures are normal |
| `BaseConflict.Api.Account` `TAccount.LoginWithSteam` | without `STEAM` (our Steamless configuration) a placeholder ticket, build id 0, branch `public` | the login always asked Steam for a ticket, also in the Steamless configuration; the lobby stand-in accepts it |

## The lobby: a stand-in master server
`run_original.ps1 -Lobby` starts the client in its real login and main menu against
`tools/original_build/master_standin.py` (http://127.0.0.1:8765, every call logged to `build/original/standin.log`)
instead of the sandbox test game: it writes `run/DebugSettings.ini` / `SettingsConnection.ini` from the snapshot's with
`UseLocalTestServer=False`, `[General] BypassLoginQueue` and `ForceBrokerFallback` (the broker's HTTP polling instead of
its websocket) and the local `WebApiServer`; without `-Lobby` it writes the snapshot's own.
- The client's API (`BaseConflict.Api*.pas`, `Engine.Network.RPC.pas`): one URL per method (`[RpcUrl]`), GET query or
  POST multipart form fields in, JSON out, mapped onto the declared record / class by field name (every field must be
  present, enums by ordinal or name, sets as ordinal arrays, `TDateTime` as ISO 8601, a `Boolean` result may be empty).
  The stand-in parses those declarations from `build/original/src`, answers all 89 endpoints with complete defaults and
  overrides what the screens need with a sample account: 3 currencies (`currency_gold`, `currency_diamonds`,
  `currency_free_exp`), every card of the snapshot's card list (one instance each, leagues 1-3) and skin, two 12-card
  decks, profile level 12, every player icon, the 13 scenarios of the PLAY screen (`SCENARIO_MAPPING`,
  `Gamestates.pas:386`), a team led by the player. The sample values are made up (the real ones were server data,
  `docs/questions-for-devs.md`).
- `-Steps "click:x,y;key:P;wait:ms;shot:name.png"` walks the client (real input at capture coordinates; after a click
  the game's cursor is left on the window's right edge so no hover tooltip shows; the owner's cursor is put back).
  The menus are a 1280x720 window. Navbar: PLAY 112,26 / DECKBUILDER 234,26 / CARD VENDOR 382,26 / LEADERBOARDS 539,26
  / SHOP 658,26 / profile 1094,26.
- A DEBUG build opens a console for `[Critical]` messages: captures find the game by its form class (`THauptform`).
- What the client itself tells about the server's content (used instead of inventing it): card names (the card
  vendor's `PositionDict` keys, `Gamestates.pas`: `master_standin.card_name`), shop item names = picture names
  (`MainMenu/Shop/<name>.png`: `bundle_medium/large/gold`, `premium_NNN_days`, `Diamonds_NNNN`, `gold_buy_direct_N`),
  crystal pack amounts (2500 / 6300 / 13750 / 28750 / 60000, `ShopItem_itDiamonds.dui`), quest identifiers
  (`Lang/quests.csv`), real-money offers need a `USD` price and `player_currency` (the real-money code). Prices, the
  account's numbers and the leaderboard players stay made up.
- `master_standin.py` checks every answer it builds against the client's declared type at start (prints
  `ANSWER DOES NOT MATCH THE CLIENT TYPE`); a missing field makes the client show "Undefined error".
- Captured so far (2026-09-19): dashboard, PLAY, deckbuilder (deck list, deck editor), card vendor (legion trees),
  leaderboards, shop (skins, icons, bundles, premium, crystals), quest panel, profile menu.

## NaN comparisons differ between the original and everything else
Delphi 10.1's Win32 compiler compares floats with x87 `FCOMP`/`SAHF` and branches as for unsigned integers: an
unordered compare (a NaN operand) sets ZF, PF and CF, so `=`, `<` and `<=` are **true** and `>`, `>=` false. Delphi 13
(and IEEE, and GDScript / C++) make every NaN compare false except `<>`. The engine uses NaN as a marker
(`RVector3.EMPTY` has X = NaN), so any original code comparing such values behaves like Delphi 10.1, not like IEEE.
The port must keep the original's results where it matters (see `docs/original-architecture.md`, gotchas).

## Open
- Captures of the same views as the map viewer (camera placement: the sandbox dev panel's camera buttons, or input),
  then side by side comparisons (CONTINUE.md).
- Lobby data still empty: card unlock requirements (`get_card_requirements`: the locks and unlock quests on the card
  vendor's cards), messages, loot, friends, the dashboard news text.
- "DOUBLE VALUE PAC" is cut off on the bundle cards: the Delphi 13 text path again (like the diamond glyph), or the
  original; compare against a picture of the real shop.
- Ability names show a diamond glyph instead of their spaces (`BaseConflict.Constants.Cards.pas:826` puts U+00A0 in
  them; Proza Libre has that glyph, the Steam screenshots show plain spaces): a Delphi 13 difference in the text path
  (FMX / DirectWrite, the patched `FMX.Canvas.D2D`), to find.
- Playing a match from the lobby (the stand-in would also have to hand out a game server, `RGameFoundData`).
