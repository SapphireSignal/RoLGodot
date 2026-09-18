class_name TThinkImpulseImmediateComponent
extends TEntityComponent
## Port of TThinkImpulseImmediateComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:74,
## implementation :1033), server only. Thinks in its group every frame (global eiIdle), unless the unit is exiled.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))


func OnIdle() -> bool:
	if not RParam.AsBoolean(Eventbus().Read(C.eiExiled, [])):
		Eventbus().Trigger(C.eiThink, [], ComponentGroup)
		Eventbus().Trigger(C.eiThinkChain, [], ComponentGroup)
	return true
