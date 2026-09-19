class_name TThinkImpulseGameTickComponent
extends TGDEntityComponent
## Port of TThinkImpulseGameTickComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:46,
## implementation :1719), server only. Thinks in its group at every global eiGameTick, unless the unit is exiled.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnGameTick", C.eiGameTick, C.epMiddle, C.etTrigger, C.esGlobal))


func OnGameTick() -> bool:
	if not RParam.AsBoolean(Eventbus().Read(C.eiExiled, [])):
		Eventbus().Trigger(C.eiThink, [], ComponentGroup)
		Eventbus().Trigger(C.eiThinkChain, [], ComponentGroup)
	return true
