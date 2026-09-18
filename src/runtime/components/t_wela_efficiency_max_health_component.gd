class_name TWelaEfficiencyMaxHealthComponent
extends TWelaEfficiencyComponent
## Port of TWelaEfficiencyMaxHealthComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:854,
## implementation :3147): the target's health cap, or with Inverse 10000 - the health cap.

var FInversed := false


func Inverse() -> TWelaEfficiencyMaxHealthComponent:
	FInversed = true
	return self


func GetEfficiencyToTarget(Entity) -> float:
	var Result := RParam.AsSingle(Entity.Cap(C.reHealth))
	if FInversed:
		Result = RParam.ToSingle(10000 - Result)
	return Result
