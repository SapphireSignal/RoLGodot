class_name TWelaReadyAfterGameEventComponent
extends TWelaReadyComponent
## Port of TWelaReadyAfterGameEventComponent (BaseConflict.EntityComponents.Shared.Wela.pas:711, implementation
## :3003). Ready once the global game event GameEvent(UID) has fired (eiGameEvent), for the rest of the game.
## At eiAfterCreate it counts as fired already unless eiGameEventTimeTo of that event is still > 0.

var FFired := false
var FEventUID := ""


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnGameEvent", C.eiGameEvent, C.epLast, C.etTrigger, C.esGlobal))


func IsReady() -> bool:
	return FFired


func OnAfterCreate() -> bool:
	# init firing state, if event is coming, waiting for firing
	FFired = RParam.AsInteger(GlobalEventbus().Read(C.eiGameEventTimeTo, [FEventUID])) <= 0
	return true


func OnGameEvent(EventIdentifier) -> bool:
	if RParam.AsString(EventIdentifier) == FEventUID:
		FFired = true
	return true


func GameEvent(EventUID: String) -> TWelaReadyAfterGameEventComponent:
	FEventUID = EventUID
	return self
