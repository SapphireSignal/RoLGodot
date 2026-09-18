class_name TWelaEfficiencyEffectComponent
extends TWelaEffectComponent
## Port of TWelaEfficiencyEffectComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:291,
## implementation :1103), server only. An effect that knows its efficiency against a target: eiEfficiency read
## [Target: TEntity] in its group answers GetEfficiencyToTarget at epFirst, ignoring the previous value (the
## TWelaEfficiency*Components add to it afterwards). -1 = cannot act on the target.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnEfficiency", C.eiEfficiency, C.epFirst, C.etRead))


## Abstract. TargetsInRange: Array of RTarget. Nothing in the snapshot calls it.
func GetEfficiency(_TargetsInRange: Array) -> float:
	return 0.0


## Negative value means cannot act on target. Positive value is the efficiency.
func GetEfficiencyToTarget(_Entity) -> float:
	return -1.0


## Return the efficiency of the wela to the target. -1 for not possible.
func OnEfficiency(Target):
	return RParam.ToSingle(GetEfficiencyToTarget(RParam.AsObject(Target)))
