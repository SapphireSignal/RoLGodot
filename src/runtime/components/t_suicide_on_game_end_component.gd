class_name TSuicideOnGameEndComponent
extends TGDEntityComponent
## Port of TSuicideOnGameEndComponent (BaseConflict.EntityComponents.Client.pas:462, implementation :4759), client
## only. Frees its owner (DeferFree) when the game ends: the global eiLose [TeamID].


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnLose", C.eiLose, C.epLast, C.etTrigger, C.esGlobal))


func OnLose(_TeamID) -> bool:
	Owner.DeferFree()
	return true
