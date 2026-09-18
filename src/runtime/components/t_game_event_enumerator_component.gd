class_name TGameEventEnumeratorComponent
extends TEntityComponent
## Port of TGameEventEnumeratorComponent (BaseConflict.EntityComponents.Shared.pas:630, implementation :2455).
## eiGameEvent (global read, [Event]) enumerates the entities listening to that game event: each adds its owner
## to the list (an Array of TEntity here, TList<TEntity> in the original; created by the first one).

var FGameEvents: Array = []  # of String


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameEvent", C.eiGameEvent, C.epMiddle, C.etRead, C.esGlobal))


func OnGameEvent(Event, Previous):
	var Result = Previous
	var Eventstring := RParam.AsString(Event)
	for GameEvent in FGameEvents:
		if GameEvent == Eventstring:
			var Enumeration = Previous if Previous is Array else null
			if Enumeration == null:
				Enumeration = []
			Enumeration.append(Owner)
			Result = Enumeration
			break
	return Result


## Adds an event, which will be set on fire.
func Event(EventID: String) -> TGameEventEnumeratorComponent:
	FGameEvents.append(EventID)
	return self
