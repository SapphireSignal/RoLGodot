class_name TAutoBrainOnHealedComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnHealedComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:701,
## implementation :2639), server only. On eiHeal [var Amount, HealModifier, InflictorID] (read, epFirst; groupless
## reads only), if the brain can think, eiIsReady of its group allows and eiWelaTriggerCheck [Amount, HealModifier,
## InflictorID] passes (empty = pass), fires eiFire at the owner in its group once (TimesForEach(n): Round(Amount)
## div n times). Answers the previous value.
## Port note: Delphi's Round is banker's rounding (L.Round).

const L = preload("res://src/runtime/dws/dws_lib.gd")

var FTimesForEach := 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnHeal", C.eiHeal, C.epFirst, C.etRead))


func OnHeal(Amount, HealModifier, InflictorID, Previous):
	var Result = Previous
	if not CanThink() or not TEventbus.CurrentEvent_CalledToGroup.is_empty():
		return Result
	var Ready := RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup))
	if Ready and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiWelaTriggerCheck, [Amount, HealModifier, InflictorID],
		ComponentGroup)):
		var Times := 1
		if FTimesForEach > 0:
			@warning_ignore("integer_division")
			Times = L.Round(RParam.AsSingle(Amount)) / FTimesForEach
		for i in Times:
			Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], ComponentGroup)
	return Result


func TimesForEach(Factor: int) -> TAutoBrainOnHealedComponent:
	FTimesForEach = Factor
	return self
