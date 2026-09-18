class_name TWelaReadyAfterGameStartComponent
extends TWelaReadyComponent
## Port of TWelaReadyAfterGameStartComponent (BaseConflict.EntityComponents.Shared.Wela.pas:698, implementation
## :2100). Ready from the first global eiGameTick on (after the warm-up), for the rest of the game.

var FReady := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameTick", C.eiGameTick, C.epLast, C.etTrigger, C.esGlobal))


func IsReady() -> bool:
	return FReady


## Start weapon.
func OnGameTick() -> bool:
	FReady = true
	return true
