class_name TWelaTriggerCheckTakeDamageComponent
extends TEntityComponent
## Port of TWelaTriggerCheckTakeDamageComponent (BaseConflict.EntityComponents.Shared.Wela.pas:527,
## implementation :1784), abstract. eiWelaTriggerCheck read [Amount, DamageType, InflictorID] in its group: an
## on-damage-taken wela fires only if every check says yes (empty = yes).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnTriggerCheck", C.eiWelaTriggerCheck, C.epHigher, C.etRead))


## Makes a single check for the damage taken (abstract in the original).
func IsValid(_Amount: float, _DamageType: Array, _InflictorID: int) -> bool:
	push_error("%s.IsValid: abstract" % ClassName())
	return true


## Return the result of the constraint.
func OnTriggerCheck(Amount, DamageType, InflictorID, Previous):
	return RParam.AsBooleanDefaultTrue(Previous) \
		and IsValid(RParam.AsSingle(Amount), RParam.AsSet(DamageType), RParam.AsInteger(InflictorID))
