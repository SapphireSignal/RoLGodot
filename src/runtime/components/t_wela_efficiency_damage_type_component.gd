class_name TWelaEfficiencyDamageTypeComponent
extends TWelaEfficiencyComponent
## Port of TWelaEfficiencyDamageTypeComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:865,
## implementation :3090): 1 if the target's main weapon (eiDamageType in GROUP_MAINWEAPON) has a prioritized
## damage type, else 0.

var FPrioritizedDamageTypes: Array = []


func Prioritize(DamageTypes: Array) -> TWelaEfficiencyDamageTypeComponent:
	FPrioritizedDamageTypes = DSet.Make(DamageTypes)
	return self


func GetEfficiencyToTarget(Entity) -> float:
	var DamageType := RParam.AsSet(Entity.Eventbus.Read(C.eiDamageType, [], [C.GROUP_MAINWEAPON]))
	return 1.0 if DSet.Intersects(DamageType, FPrioritizedDamageTypes) else 0.0
