# Bugs of the original, fixed in the port

The port copies what the original's code was meant to do, never its bugs (project rule). Each entry: where the bug is
in the reference snapshot, what it did, and what the port does. Behaviour that looks odd but is intended (documented
by the original, or a design choice) is not a bug and stays; see the end of this file.

| Where (original) | The bug | The port |
| --- | --- | --- |
| `BaseConflict.EntityComponents.Shared.pas:1475`, `:1508` (`TryGetNexusNextEnemy`, `NexusNext`) | kept the *farthest* nexus (`bestDistance < distance`) | the nearest. Same on today's maps (one enemy nexus) |
| `BaseConflict.EntityComponents.Shared.Wela.pas:1661` (`TWelaTargetConstraintMaxTargetDistanceComponent`) | tested `IsEmpty` where it means "is set": compared only empty targets, never failed | set targets must lie within `eiAbilityTargetRange` of each other (Relocate's second target) |
| `BaseConflict.EntityComponents.Shared.Wela.pas:2703` (`TWelaHelperResolveComponent`, owner tier) | `upTier2` gave index 1 | 2 (Relocate heals tier 2 buildings by its 25 %, not the tier 1 value) |
| `GameServer/...Server.Brains.pas:2248` (`TAutoBrainOnDeathComponent.Fire`) | the FireAtKiller override sat on the parameterless `Fire`; `CheckAndFire` calls the other overload, so it never fired at the killer | fires at the killer (the HighlyExplosiveBuff mutator) |
| `GameServer/...Server.Welas.pas:1359` (`TWelaEffectFactoryComponent`) | blocked the build fields in PreProcessing, before the unit has its ID: fields held entity ID 0 | blocked in the setup with the unit's ID |
| `GameServer/...Server.Welas.pas:1856` (`TWelaEffectProjectileComponent`) | any shooter standing exactly at (0, 0) was taken for a commander (no position): its projectile started at the target | only a commander of the game |
| `GameServer/...Server.Warheads.pas:1032` (`TWarheadSpottyTeleportComponent`, AsProjectile) | passed the owner's entity ID as the projectile's owning commander | the owner's commander |
| `GameServer/...Server.Welas.pas:1475` (`TWelaLinkEffectComponent`, break all) | walked the live `TDictionary` keys while each break removed its entry: a link shifted back into a visited slot was skipped and stayed up | walks a snapshot: every link breaks |
| `GameServer/...Server.Welas.pas:2904`, `:2910` (`TWelaEffectFireComponent.RedirectToLink{Source,Destination}`) | set flags nothing read | fire at the link's `eiLinkSource` / `eiLinkDest` (no script uses them) |
| `GameServer/...Server.Welas.pas:1041`, `:1043` (`TWelaEffectReplaceComponent`) | `KeepResource` read the owner's balance and `eiReplaceEntity` named the owner, not the replaced target | the target (the same entity in every script) |
| `GameServer/...Server.Brains.Special.pas` via `Engine/Engine.Math.pas:4479` (`RMatrix2x2.Inverse`, spawner `ApplyGridOffset`) | swapped the off-diagonal cells the wrong way round (the transpose of the inverse): a spawner's wave came out mirrored against the spawner's field | the true inverse |
| `GameServer/BaseConflict.EntityComponents.Server.pas` (`TServerEntityManagerComponent.Idle`) | cleared the kill queue after the loop: kills queued while it ran were dropped, those entities never died | they wait for the next frame |
| `GameServer/BaseConflict.EntityComponents.Server.pas:2599` (`TScenarioDirectorComponent.SpawnUnits`) | a row of more than 7 wrapped, but the wrapped units kept the y offset of one long row (the new row sat off to one side) | each row of up to 7 is centred |
| `BaseConflict.Map.pas:727` (`TLane.DistanceToPoint`) | the loop overwrote the minimum it started (`MaxSingle`): distance to the last waypoint | the nearest waypoint |
| `BaseConflict.Classes.Pathfinding.pas:353` (`DoPathfinding`, `IgnoreOtherEntities`) | inverted: expanded only permanently blocked tiles | every tile that is not permanently blocked |
| `BaseConflict.Classes.Pathfinding.pas:319` (`DoPathfinding`) | the source tile kept its heuristic from an earlier search (it is extracted first, so no path changed) | computed per search |
| `BaseConflict.Classes.Pathfinding.pas:187`, `:672` (`ComputeDebugPath`, `TPath.ReleasePath`) | a path that reserved nothing released time slots on freeing: other units' reservations | only a reserved path releases |
| `Engine/Engine.Collision.pas:211` (`TLooseQuadTreeNode.AddItemRecursive`) | an item whose centre lay outside every child was counted but stored nowhere: never found, never uncounted | stays in that node |
| `Engine/Engine.Collision.pas:253` (`RemoveItemRecursive`) | updated a node's emptiness after its ancestors: `HasItems` stale above the parent | each node before its parent |
| `Engine/Engine.Helferlein.Windows.pas:2124` (`TTimer.StartWithRest`) | kept `Min(0, Trunc(p) - 1) + Frac(p)` intervals (3.6 => 0.6, 0.5 => -0.5) | as documented: "reducing it by at max one interval. Expired 3.6 => 2.6" |
| `Engine/Engine.Helferlein.Windows.pas:2197` (`TTimer.setPaused`) | inverted: `Paused := True` called Weiter, `False` called Pause | True pauses, False runs on |
| `Engine/Engine.Helferlein.Windows.pas:2216` (`TTimeManager.Create`) | started `LetzteZeit` from the raw counter while TickTack subtracts `ProgramStart`: the first ZDiff of a server game was a large negative number | measured from the clock's creation |

Not bugs (checked, kept):
- `RTargetValidity`: empty targets start invalid, and a target once invalid stays invalid (the original documents both).
- `TLane.GetNextWaypoint` ignores its direction parameter: it returns the nearest waypoint and its caller applies the
  direction.
- `DelphiDictionary`'s live walk skipping a shifted entry is how Delphi's `TDictionary` works; only callers that remove
  while walking were bugs (fixed above).
- A decoration of size 0 in a map file is drawn at size 0 (map data, not code).
- Delphi `single` precision, `TList.Sort` tie order, hash-order walks: the original's behaviour, not bugs.
