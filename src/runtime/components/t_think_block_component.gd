class_name TThinkBlockComponent
extends TGDEntityComponent
## Port of TThinkBlockComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:148, implementation
## :2972), server only. Blocks the thinking of its entity: stops eiThink and eiThinkChain at epFirst (made with
## Create, so only groupless thinking, which is what units' TThinkImpulseTimerComponent sends). The tutorial
## director puts it on units to freeze the game (GameServer/BaseConflict.EntityComponents.Server.pas:3713).


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThink", C.eiThink, C.epFirst, C.etTrigger))
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epFirst, C.etTrigger))


func OnThink() -> bool:
	return false


func OnThinkChain() -> bool:
	return false
