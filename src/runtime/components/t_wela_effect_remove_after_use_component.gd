class_name TWelaEffectRemoveAfterUseComponent
extends TWelaEffectComponent
## Port of TWelaEffectRemoveAfterUseComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:397,
## implementation :945), server only. On fire removes the target group (default: its own group) from its owner:
## global eiRemoveComponentGroup [owner ID, groups], carried out by the entity manager at its next Idle.

var FTargetGroup: Array = []


func Fire(_Targets: Array) -> void:
	if ComponentGroup.is_empty():
		push_error("Are you sure to clean all components of this entity? A componentless entity should be killed.")
	var Group: Array = ComponentGroup if FTargetGroup.is_empty() else FTargetGroup
	GlobalEventbus().Trigger(C.eiRemoveComponentGroup, [Owner.ID, Group.duplicate()])


func TargetGroup(Group = []) -> TWelaEffectRemoveAfterUseComponent:
	FTargetGroup = DSet.Make(Group)
	return self
