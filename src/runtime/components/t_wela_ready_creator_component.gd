class_name TWelaReadyCreatorComponent
extends TWelaReadyComponent
## Port of TWelaReadyCreatorComponent (BaseConflict.EntityComponents.Shared.Wela.pas:739, implementation :3086).
## Ready while eiIsReady of the creator's group (eiCreator / eiCreatorGroup in its group) is true. Ready if the
## creator is gone or the creator group is empty (a global read would ask every wela of the creator).


func IsReady() -> bool:
	var CreatorID := RParam.AsInteger(Eventbus().Read(C.eiCreator, [], ComponentGroup))
	var game = GlobalEventbus().Game
	var Creator = game.EntityManager.TryGetEntityByID(CreatorID) if game != null else null
	if Creator != null:
		var CreatorGroup := RParam.AsSet(Eventbus().Read(C.eiCreatorGroup, [], ComponentGroup))
		# don't make a global fire as it would trigger all welas on that entity
		if not CreatorGroup.is_empty():
			return RParam.AsBooleanDefaultTrue(Creator.Eventbus.Read(C.eiIsReady, [], CreatorGroup))
	return true
