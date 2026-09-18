class_name TAutoBrainOnGameEventComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnGameEventComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:591,
## implementation :2480), server only. At every global eiGameEvent [Name] (trigger, epLast) whose name (any case)
## is one of SetEvent's, fires eiFire at the owner in its group; no other checks.

var FEvents: Array = []  # of lower-case String


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameEvent", C.eiGameEvent, C.epLast, C.etTrigger, C.esGlobal))


func OnGameEvent(Event) -> bool:
	if FEvents.has(RParam.AsString(Event).to_lower()):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], ComponentGroup)
	return true


func SetEvent(Event: String) -> TAutoBrainOnGameEventComponent:
	FEvents.append(Event.to_lower())
	return self
