class_name TWelaEffectGameEventComponent
extends TWelaEffectComponent
## Port of TWelaEffectGameEventComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:482,
## implementation :3131), server only. On fire triggers the global eiGameEvent [Name] for each added event, in
## the order they were added.

var FGameEvents: Array = []  # of String


func Fire(_Targets: Array) -> void:
	for GameEvent in FGameEvents:
		GlobalEventbus().Trigger(C.eiGameEvent, [GameEvent])


## Adds an event, which will be set on fire.
func Event(EventID: String = "") -> TWelaEffectGameEventComponent:
	FGameEvents.append(EventID)
	return self
