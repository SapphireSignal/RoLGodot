class_name TThinkImpulseFireComponent
extends TEntityComponent
## Port of TThinkImpulseFireComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:57, implementation
## :2716), server only. Thinks in TargetGroup (default: the public group []) at every eiFire (epLast) that reaches
## its own group, unless the unit is exiled.

var FThinkGroup: Array = []


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnFire", C.eiFire, C.epLast, C.etTrigger))


func OnFire(_Targets) -> bool:
	if not RParam.AsBoolean(Eventbus().Read(C.eiExiled, [])):
		Eventbus().Trigger(C.eiThink, [], FThinkGroup)
		Eventbus().Trigger(C.eiThinkChain, [], FThinkGroup)
	return true


func TargetGroup(Group: Array) -> TThinkImpulseFireComponent:
	FThinkGroup = DSet.Make(Group)
	return self
