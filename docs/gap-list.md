# Gap list

Every user-visible behaviour of the original, and whether the port has it yet. Worked down by visibility.
Add an entry the moment a behaviour is noticed in the source, even if its phase is far away.

Status: ⬜ missing · 🟨 partial · ✅ matches original (checked against the source)

## Boot and shell
| Behaviour | Source | Status |
| --- | --- | --- |
| Splash screen (`Splash.png`) at startup | `BaseConflictSplash.pas` | ⬜ |
| Window icon | `RiseOfLegions_Icon.ico` | ⬜ |
| Custom mouse cursors | `Graphics/**/*.cur` | ⬜ |
| Settings persisted between runs | `Settings.ini`, `BaseConflict.Settings.Client.pas` | ⬜ |

## Match (sandbox first)
| Behaviour | Source | Status |
| --- | --- | --- |
| Classic map with terrain, water, vegetation, lighting | `Maps/Classic` | ⬜ |
| Units walk lanes, fight, die | `Scripts/Units`, server components | ⬜ |
| Card hand, play spawner / drop / spell | `BaseConflict.Classes.Gamestates*.pas` | ⬜ |
| Minimap | `BaseConflict.Classes.MiniMap.pas` | ⬜ |
| Unit skins (Default, Machine, Underworld, Woodlands, ...) | mesh folders, `Entity.SkinID` | ⬜ |
| Tooltips with ability keywords | `TTooltipUnitAbilityComponent` | ⬜ |
| Scripted AI `MegaRootDude` never runs: its server script does not compile (undeclared `ArcherDrop`); the port keeps the error | `Scripts/AI/MegaRootDude.dws` | 🟨 transpiled as the error; runtime reporting in phase 2 |

## Presentation
| Behaviour | Source | Status |
| --- | --- | --- |
| Particle effects per card | `Graphics/Effects/ParticleEffects` | ⬜ |
| Metal / glow mesh effects | `TMeshEffectMetal`, glow textures | ⬜ |
| Post effects | `PostEffects.fxs` | ⬜ |
| Music and sound effects | `Sound/Banks` | ⬜ |
| 29 languages | `Lang/*.csv` | ⬜ |

## Menus and meta
| Behaviour | Source | Status |
| --- | --- | --- |
| Main menu, dashboard, navbar | `Graphics/GUI`, `Lang/dashboard.csv`, `navbar.csv` | ⬜ |
| Collection, deckbuilder, card sacrifice | `Lang/collection.csv`, `deckbuilder.csv` | ⬜ |
| Shop (offline) | `BaseConflict.Api.Shop.pas` | ⬜ |
| Quests | `BaseConflict.Api.Quests.pas` | ⬜ |
| Tutorial | `Lang/tutorial.csv`, `Scripts/Scenarios` | ⬜ |
| Scenarios and mutators | `Scripts/Scenarios` | ⬜ |
| Post-game statistics | `Lang/game_statistics.csv` | ⬜ |
