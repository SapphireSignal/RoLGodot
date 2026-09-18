class_name TWelaEffectRemoveBeaconComponent
extends TWelaEffectComponent
## Port of TWelaEffectRemoveBeaconComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:537,
## implementation :2982), server only. On fire removes from each entity target the groups its eiWelaSearch finds
## for SearchForWelaBeacon (`RemoveGroups`: the global eiRemoveComponentGroup, carried out at the manager's Idle).

var FLookForGroup: Array = []  # SetUnitProperty


func Fire(Targets: Array) -> void:
	if FLookForGroup.is_empty():
		push_error("TWelaEffectRemoveBeaconComponent.Fire: No beacon specified!")
	var game = GlobalEventbus().Game
	for Target in Targets:
		var TargetEntity = Target.TryGetTargetEntity(game)
		if TargetEntity != null:
			var RemoveGroups := RParam.AsSet(TargetEntity.Eventbus.Read(C.eiWelaSearch, [FLookForGroup.duplicate()]))
			if not RemoveGroups.is_empty():
				TargetEntity.RemoveGroups(RemoveGroups)


func SearchForWelaBeacon(Properties = []) -> TWelaEffectRemoveBeaconComponent:
	FLookForGroup = DSet.Make(Properties)
	return self
