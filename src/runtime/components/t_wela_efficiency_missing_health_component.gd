class_name TWelaEfficiencyMissingHealthComponent
extends TWelaEfficiencyComponent
## Port of TWelaEfficiencyMissingHealthComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:838,
## implementation :3036): the target's missing health (health cap - health).


func GetEfficiencyToTarget(Entity) -> float:
	return RParam.ToSingle(RParam.AsSingle(Entity.Cap(C.reHealth)) - RParam.AsSingle(Entity.Balance(C.reHealth)))
