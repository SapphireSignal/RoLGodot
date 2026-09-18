class_name TAutoBrainPreventDeathComponent
extends TAutoBrainComponent
## Port of TAutoBrainPreventDeathComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:758,
## implementation :2304), server only. At eiDie (epLower, before the later death handlers), if the brain can think,
## the unit is not exiled (unless ThinksInExile), eiIsReady of its group allows and the owner passes
## eiWelaTargetPossible there: fires eiFire at the owner in FireInGroup and stops the event (the unit does not die).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnBeforeDie", C.eiDie, C.epLower, C.etTrigger))


func OnBeforeDie(_KillerID, _KillerCommanderID) -> bool:
	if not CanThink() or (not FThinkInExile and RParam.AsBoolean(Eventbus().Read(C.eiExiled, []))):
		return true
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
		var Target := ATarget.Make(FOwner)
		if _TargetsPossible(ATarget.ToRParam(Target), ComponentGroup):
			Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Target)], FFireGroup)
			return false
	return true
