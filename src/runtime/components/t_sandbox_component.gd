class_name TSandboxComponent
extends TEntityComponent
## Port of TSandboxComponent (BaseConflict.EntityComponents.Shared.pas:464, implementation :2484): in the sandbox,
## clears the game director's events at the global eiGameCommencing (no scripted game flow).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameCommencing", C.eiGameCommencing, C.epLast, C.etTrigger, C.esGlobal))


func OnGameCommencing() -> bool:
	GlobalEventbus().Game.GameDirector.ClearEvents()
	return true
