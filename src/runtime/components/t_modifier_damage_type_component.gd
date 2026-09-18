class_name TModifierDamageTypeComponent
extends TModifierComponent
## Port of TModifierDamageTypeComponent (BaseConflict.EntityComponents.Shared.Wela.pas:45, implementation :3301).
## Adds and removes damage types of eiDamageType in its groups.

var FAdded: Array = []
var FRemoved: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnDamageType", C.eiDamageType, C.epMiddle, C.etRead))


func OnDamageType(Previous):
	return DSet.Difference(DSet.Union(RParam.AsSet(Previous), FAdded), FRemoved)


func Add(DamageTypes: Array) -> TModifierDamageTypeComponent:
	FAdded = DSet.Make(DamageTypes)
	return self


func Remove(DamageTypes: Array) -> TModifierDamageTypeComponent:
	FRemoved = DSet.Make(DamageTypes)
	return self
