class_name TWelaReadyEnemiesNearbyComponent
extends TWelaReadyComponent
## Port of TWelaReadyEnemiesNearbyComponent (BaseConflict.EntityComponents.Shared.Wela.pas:685, implementation
## :3107). Ready while an enemy (another team) within eiWelaRange of ValueGroup (default: the component's group)
## is a possible target by eiWelaTargetPossible of CheckGroup (default: empty). Asks Game.CollisionManager via
## eiEntitiesInRange; stops checking at the first possible target (Delphi's `or` short-circuits).

var FValueGroup: Array = []
var FCheckGroup: Array = []


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FValueGroup = ComponentGroup
	return self


func ValueGroup(Group: Array) -> TWelaReadyEnemiesNearbyComponent:
	FValueGroup = DSet.Make(Group)
	return self


func CheckGroup(Group: Array) -> TWelaReadyEnemiesNearbyComponent:
	FCheckGroup = DSet.Make(Group)
	return self


func IsReady() -> bool:
	var Result := false
	var Range := RParam.AsSingle(Eventbus().Read(C.eiWelaRange, [], FValueGroup))
	var Enemies = GlobalEventbus().Read(C.eiEntitiesInRange, [Owner.Position, Range, Owner.TeamID(), C.tcEnemies, null])
	if Enemies != null:
		for Enemy in Enemies:
			Result = Result or RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible,
				[ATarget.ToRParam(ATarget.Make(Enemy))], FCheckGroup)).IsValid()
	return Result
