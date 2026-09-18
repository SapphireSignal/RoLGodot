class_name TDynamicZoneRadialEmitterComponent
extends TDynamicZoneEmitterComponent
## Port of TDynamicZoneRadialEmitterComponent (BaseConflict.EntityComponents.Shared.pas:598, implementation :2262).
## Emits a radial dynamic zone around this unit: radius = eiWelaRange of its group, for its team (TeamID <= -1 =
## any team).


func IsInDynamicZone(Position: Vector2, TeamID: int) -> int:
	if (TeamID <= -1 or TeamID == Owner.TeamID()) and \
		Owner.Position.distance_to(Position) <= RParam.AsSingle(Eventbus().Read(C.eiWelaRange, [], ComponentGroup)):
		return drTrue
	return drNone
