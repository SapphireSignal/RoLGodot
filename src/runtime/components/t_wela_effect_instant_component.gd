class_name TWelaEffectInstantComponent
extends TWelaEfficiencyEffectComponent
## Port of TWelaEffectInstantComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:467,
## implementation :963), server only. Fires the warheads of its target group (default: its own group) directly on
## the targets: eiFireWarhead [ATarget] if eiWarheadTargetPossible of the group the fire was called to allows.
## Efficiency: 1 against any target that is not upUntargetable, else -1.

var FTargetGroup: Array = []


func CreateGrouped(Entity = null, Group = []) -> TEntityComponent:
	super(Entity, Group)
	FTargetGroup = ComponentGroup
	return self


func Fire(Targets: Array) -> void:
	var Validity := RTargetValidity.FromRParam(Eventbus().Read(C.eiWarheadTargetPossible, [ATarget.ToRParam(Targets)], TEventbus.GetCurrentEvent_CalledToGroup()))
	if Validity.IsValid():
		Eventbus().Trigger(C.eiFireWarhead, [ATarget.ToRParam(Targets)], FTargetGroup)


func GetEfficiency(_TargetsInRange: Array) -> float:
	return RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], TEventbus.GetCurrentEvent_CalledToGroup()))


func GetEfficiencyToTarget(Entity) -> float:
	var IsPossible: bool = not RParam.AsSet(Entity.Eventbus.Read(C.eiUnitProperties, [])).has(C.upUntargetable)
	return 1.0 if IsPossible else -1.0


## Fires eiFireWarhead in the following groups instead of the component group.
func TargetGroup(Group = []) -> TWelaEffectInstantComponent:
	FTargetGroup = DSet.Make(Group)
	return self
