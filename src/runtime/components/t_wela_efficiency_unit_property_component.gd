class_name TWelaEfficiencyUnitPropertyComponent
extends TWelaEfficiencyComponent
## Port of TWelaEfficiencyUnitPropertyComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:876,
## implementation :3107): 1 if the target has a prioritized unit property, else 0; Reverse swaps them.

var FReversed := false
var FPrioritizedUnitProperties: Array = []


func Prioritize(UnitProperties: Array) -> TWelaEfficiencyUnitPropertyComponent:
	FPrioritizedUnitProperties = DSet.Make(UnitProperties)
	return self


## Reverse the priorization, so units with the unit properties are treated less prioritized.
func Reverse() -> TWelaEfficiencyUnitPropertyComponent:
	FReversed = true
	return self


func GetEfficiencyToTarget(Entity) -> float:
	var UnitProperties := RParam.AsSet(Entity.Eventbus.Read(C.eiUnitProperties, [], []))
	var Result := 1.0 if DSet.Intersects(UnitProperties, FPrioritizedUnitProperties) else 0.0
	if FReversed:
		Result = 1 - Result
	return Result
