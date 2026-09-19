class_name TWelaTargetConstraintGridComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintGridComponent (BaseConflict.EntityComponents.Shared.Wela.pas:336, implementation
## :1530). Only build targets whose fields are all free: the unit's eiWelaNeededGridSize (read in the called
## group) from the target field on, each field checked in the build zone at its world position. CheckAllFields
## (set by the client's TWelaTargetConstraintGridVisualizedComponent) keeps checking after the first blocked
## field, so its CheckGridNode override sees every field.

var CheckAllFields := false


func CheckGridNode(_TargetBuildZone: TBuildZone, WorldCoord: Vector2) -> bool:
	var BuildZone: TBuildZone = TargetGame().Map.BuildZones.GetBuildZoneByPosition(WorldCoord)
	if BuildZone == null:
		return false
	return BuildZone.IsFree(BuildZone.PositionToCoord(WorldCoord))


func IsPossible(Target: RTarget) -> bool:
	if not Target.IsBuildTarget():
		return false
	var TargetBuildZone: TBuildZone = Target.GetBuildZone(TargetGame())
	if TargetBuildZone == null:
		return false
	var Result := true
	var NeededSize := RParam.AsIntVector2(Eventbus().Read(C.eiWelaNeededGridSize, [], TEventbus.GetCurrentEvent_CalledToGroup()))
	for X in NeededSize.x:
		for Y in NeededSize.y:
			var targetPos := TargetBuildZone.GetCenterOfField(Target.BuildGridCoordinate + Vector2i(X, Y))
			if not CheckGridNode(TargetBuildZone, targetPos):
				if CheckAllFields:
					Result = false
				else:
					return false
	return Result
