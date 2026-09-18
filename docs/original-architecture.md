# The original: how Rise of Legions is built

Findings from the pinned snapshot (see `source-of-truth.md`). Paths are relative to
`reference/rise-of-legions/`. Everything here was checked in the source; open questions are marked **?**.

## Size

| Area | Where | Size |
| --- | --- | --- |
| Client + shared game code | `BaseConflict.*.pas` (48 units, root) | 59k lines |
| Game server | `GameServer/` | 16k lines |
| Entity scripts | `Scripts/` (`.ets`, `.dws`, `.sps`) | 35k lines, 509 files |
| Engine ("delphi3d-engine") | `Engine/` | 748k lines, mostly DirectX / WinAPI headers and libraries |
| Assets | `Graphics/` 1 GB, `Maps/` 430 MB, `Sound/` 300 MB | |

`Engine/` is identical to the `Engine/` folder of the separate delphi3d-engine repo; that repo only adds
`Editors/`. The port does not port the engine: Godot replaces it. We read the engine only to decode its file
formats and to copy behaviour the game relies on (animation, particles, GUI layout, pathfinding).

## Programs

- `RiseOfLegions.dpr`: the client (Delphi 10.1, DirectX 11, FMOD Studio, Steam).
- `GameServer/RiseOfLegionsGameServer.dpr`: the authoritative game server that runs one match.
  Run locally with the client, it hosts a **sandbox game** (the README's "how to use").
- `MapEditor/`, `Tools/RoLTools.dpr`: dev tools (preloader cache, script tests).
- Not in the snapshot: the master server (accounts, matchmaking, shop, collection, quests).
  The client's side of it lives in `BaseConflict.Api.*.pas` (the contract the port must satisfy locally).

## Gameplay model: entities, blackboard, eventbus, components

Every unit, building, projectile and spell is a `TEntity` (`BaseConflict.Entity.pas`) with:
- a **Blackboard**: typed values keyed by an event id (`eiResourceCap`, `eiWelaDamage`, ...) and a group
  index list, e.g. `SetValue(eiWelaDamage, [1], 13.0)` = "ability group 1 deals 13 damage";
- an **Eventbus**: components talk only through events (`Write`, `WriteGrouped`, subscriptions);
- **components** attached per group. Families by name:
  - `TBrain*`: decisions (approach, fight, auto-cast);
  - `TWela*`: *weapon/ability* ("Wela"): targeting, target constraints, readiness/cooldown, effect;
  - `TWarhead*`: what an effect does (damage, heal, modifiers);
  - client-only: `TMeshComponent`, `TAnimationComponent`, `TTooltip*`, sound components.
- Shared components: `BaseConflict.EntityComponents.Shared*.pas`; server-only: `GameServer/*.Server.*.pas`;
  client-only: `BaseConflict.EntityComponents.Client*.pas`.

## Scripts: the content

Units, spells, projectiles, buildings, modifiers, scenarios and AI are **DWScript** (Pascal) files run by
`Engine/Engine.Script.pas` (`TDelphiWebScript`). One file serves client and server through
`{$IFDEF CLIENT}` / `{$IFDEF SERVER}`. A unit script has three entry points, each calling the previous:
- `CreateData`: stats on the blackboard (health, armor type, damage, range, cooldown, action timing);
- `CreateMeta`: presentation (mesh, skins, bone zones, animation frame ranges, click capsule);
- `CreateEntity`: behaviour (server brains, welas, warheads).
Shared helpers are included with `{$INCLUDE 'UnitTemplate.dws'}` (`Scripts/HelperScripts/`).
`{@UBL_...}` markers tag balance values (health, damage, range, cooldown).

Per card there are usually three scripts: `X.ets` (the unit), `XDrop.ets` (card played as a one-off drop),
`XSpawner.ets` (card played as a spawner building that produces X over time).

Folders: `Units/{White,Black,Green,Blue,Colorless,Golems,Neutral,Scenario}`, `Spells/*`, `Projectiles/*`,
`Modifiers`, `Links`, `Environment`, `Scenarios` (+ `Mutators`), `AI`, `Commander`, `Effects`.

## Cards

`BaseConflict.Constants.Cards.pas` registers every card by GUID:
`CardInfoManager.AddCard(guid, TCardInfo.Create(CardType, Colors, Filename, Techlevel))`, with type `ctSpawner`,
`ctDrop`, ...; the last argument is the card's tech level / tier (declaration at line 94). The sandbox deck the local game server hands
out is in `GameServer/BaseConflict.Game.Server.pas` (`Commander.Cards.Add(...)`).

## Assets and formats

| Kind | Files | Format | Port route |
| --- | --- | --- | --- |
| Unit / effect meshes | `.fbx` (204) + `.xml` descriptor | FBX 7.3/7.4 (binary, 14 ASCII), all Y-up, mixed UnitScaleFactor that the original's assimp ignores (raw units) + XML: `GeometryFile`, diffuse/material/glow/fur texture (no normal maps used), cull mode, alpha, outline | done: `tools/import_graphics.py` + `TMesh`, see `assets.md` |
| Mesh cache | `.msh` (204) | `%KMF V.01` binary (`Engine.Core.Mesh.pas`) | not needed: every `.msh` has its `.fbx` (names differ only in case) |
| Textures | `.tga` (796), `.png` (912), `.tex` (1717) | `.tex` = `%KTF V.01`: mip chunks of 32-bit pixels, RLE (value, count) pairs (`Engine.Core.Texture.pas`) | use the source image; only 8 `.tex` have none (GUI: sacrifice arrow, early-access banner, a few card/faction icons): a small KTF decoder covers them |
| Particle effects | `.pfx` (366) | XML `TParticleEffectPattern` | converter to Godot particles, checked side by side |
| GUI | `.dui` (139) + `.scss` (53) | XML markup with classes + SCSS-like stylesheets (`Engine.GUI.pas`) | converter to Godot Control scenes + theme |
| Shaders | `.fx` (28), `PostEffects.fxs` | HLSL | rewrite as Godot shaders |
| Maps | `Maps/Classic`, `Maps/Single` | `.bcm` map, `.bcc`, `.ter` terrain, `.veg` vegetation, `.wat` water, `.lig` lights, tiled diffuse/material/normal PNG/TEX | per-format converters |
| Sound | `Sound/Banks/*.bank` | FMOD Studio banks; `Music.bank` is a split zip (`.001`-`.003`); `GUIDs.txt` maps event paths | extract samples; rebuild events in Godot audio. FMOD project source is on GitLab (outside our source of truth) |
| Text | `Lang/*.csv` (23 files) | `;`-separated, 29 languages, `%(param)` placeholders, `§key` references, `<span class="...">` markup | Godot translations + a formatter for the markup |
| Fonts | `.ttf` (6) | TrueType | direct |

Gotchas:
- XML and INI values use German decimal commas (`10,1960000991821`). Every converter must parse them.
- File names differ in case between references and disk (`footman.fbx` vs `Footman.FBX`). The original ran
  on case-insensitive Windows; converters must resolve paths case-insensitively and emit one canonical case.

## Open questions (**?**)
- Networking: the port runs the game-server simulation in-process for local play. Multiplayer later, if wanted.
