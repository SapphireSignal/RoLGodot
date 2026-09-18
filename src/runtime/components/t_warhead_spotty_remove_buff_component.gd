class_name TWarheadSpottyRemoveBuffComponent
extends TWarheadSpottyComponent
## Port of TWarheadSpottyRemoveBuffComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:104,
## implementation :1068), server only. Removes buffs from each target entity: eiRemoveBuffs [MustHaveAny,
## MustNotHave] (SetBuffType; All = every buff type).

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FMustHaveAny: Array = []
var FMustNotHave: Array = []


func ApplyEffect(Entity: TEntity) -> void:
	if Entity != null:
		Entity.Eventbus.Trigger(C.eiRemoveBuffs, [FMustHaveAny.duplicate(), FMustNotHave.duplicate()])


func All() -> TWarheadSpottyRemoveBuffComponent:
	FMustHaveAny = BC.ALL_BUFF_TYPES.duplicate()
	return self


func MustHaveAny(TargetBuffs = []) -> TWarheadSpottyRemoveBuffComponent:
	FMustHaveAny = DSet.Make(TargetBuffs)
	return self


func MustNotHave(TargetBuffs = []) -> TWarheadSpottyRemoveBuffComponent:
	FMustNotHave = DSet.Make(TargetBuffs)
	return self
