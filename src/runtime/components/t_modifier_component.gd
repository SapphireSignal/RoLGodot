class_name TModifierComponent
extends TEntityComponent
## Port of TModifierComponent (BaseConflict.EntityComponents.Shared.Wela.pas:32, implementation :984).
## Base of the components that adjust a value other components read (cooldown, damage, range, cost, ...).
## The value to apply is read from FValueGroup (default: own group); with a ReadyGroup the modifier only works
## while eiIsReady of that group is true (or empty).

const BC = preload("res://src/runtime/base_conflict_constants.gd")
const L = preload("res://src/runtime/dws/dws_lib.gd")

var FValueGroup: Array = []
var FReadyGroup: Array = []


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FValueGroup = ComponentGroup
	return self


func IsActive() -> bool:
	return FReadyGroup.is_empty() or RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FReadyGroup))


func SetValueGroup(ValueGroup: Array) -> TModifierComponent:
	FValueGroup = DSet.Make(ValueGroup)
	return self


func ReadyGroup(ReadyGroup_: Array) -> TModifierComponent:
	FReadyGroup = DSet.Make(ReadyGroup_)
	return self
