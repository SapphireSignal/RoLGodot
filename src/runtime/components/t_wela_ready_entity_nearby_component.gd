class_name TWelaReadyEntityNearbyComponent
extends TWelaReadyComponent
## Port of TWelaReadyEntityNearbyComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:234,
## implementation :3193), server only. Ready if certain entities are nearby: each check asks the targeting of
## TargetingGroup (default own group) for targets (eiWelaUpdateTargets into an empty list); ReadyIfTargets: ready
## with any, else (the default) ready with none.

var FTargetingGroup: Array = []
var FReadyIfTargets := false


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FTargetingGroup = ComponentGroup
	return self


func IsReady() -> bool:
	var Targets: Array = []
	Eventbus().Trigger(C.eiWelaUpdateTargets, [Targets], FTargetingGroup)
	return (FReadyIfTargets and Targets.size() > 0) or (not FReadyIfTargets and Targets.size() <= 0)


func TargetingGroup(Group: Array) -> TWelaReadyEntityNearbyComponent:
	FTargetingGroup = DSet.Make(Group)
	return self


func ReadyIfTargets() -> TWelaReadyEntityNearbyComponent:
	FReadyIfTargets = true
	return self


func ReadyIfNoTargets() -> TWelaReadyEntityNearbyComponent:
	FReadyIfTargets = false
	return self
