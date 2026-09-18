class_name TWelaEfficiencyComponent
extends TEntityComponent
## Port of TWelaEfficiencyComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:828, implementation
## :3043), server only. Prioritizes targets for the targeting components: eiEfficiency read [Target: TEntity] in
## its group adds GetEfficiencyToTarget to the previous value (epMiddle; the effects answer first, at epFirst).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnEfficiency", C.eiEfficiency, C.epMiddle, C.etRead))


## Abstract.
func GetEfficiencyToTarget(_Entity) -> float:
	return 0.0


func OnEfficiency(Target, Previous):
	return RParam.ToSingle(RParam.AsSingle(Previous) + GetEfficiencyToTarget(Target))
