# Unused features of the original

Things the original's code can do that no script or game code in the pinned version ever uses. The port stays
1:1, so none of this is switched on; the list is for deciding, once the game is finished, whether any of it is worth
adding. Add an entry whenever porting turns one up (with the evidence that it is unused).

| Feature | Where | What it would do | Ported? |
| --- | --- | --- | --- |
| Axis dynamic zone | `TDynamicZoneAxisEmitterComponent`, `BaseConflict.EntityComponents.Shared.pas:606` | A zone bounded by a straight line instead of a circle: everything on one side of a line through a point (e.g. "your half of the map") counts as inside. Could allow card play on a whole map half. Quirk: `SetPosition` normalizes the point, so it can only sit at distance 1 from the map centre unless fixed. | Yes (`src/runtime/components/t_dynamic_zone_axis_emitter_component.gd`) |
| Excluding zones | `TDynamicZoneEmitterComponent.Exclude`, `:592` | A zone that forbids instead of allows: a spot inside it is "not in zone" even if another emitter covers it. Could block card play around an objective or enemy structure. | Yes |
| Nexus early vulnerability | `TNexusEarlyVulnerabilityComponent`, `:88`, implementation `:2080` | Its group's `eiWelaDamage` starts at the set value and falls linearly to 1 by the game tick in `eiCooldown`, rounded up to whole steps (its comment: "6x, 5x, 4x, 3x ..."). The name suggests a damage multiplier that makes the Nexus extra vulnerable early in the match; how it would be wired in is not in the code. | No (declared and exposed only) |

Evidence: no `Scripts\` file and no other `.pas` unit mentions these (searched 2026-09-18).
