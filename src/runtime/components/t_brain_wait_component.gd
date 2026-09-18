class_name TBrainWaitComponent
extends TBrainComponent
## Port of TBrainWaitComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:314, implementation
## :1263), server only. Stands still while its group's targeting finds something: every chain (epLow) triggers
## eiWelaUpdateTargets on a fresh list; with a target it stands (if moving) and consumes the thought.


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epLow, C.etTrigger))


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func ThinkChain() -> bool:
	var Result := true
	var TargetList: Array = []
	# look for an enemy, done every think, because other entities can pass the current target
	Eventbus().Trigger(C.eiWelaUpdateTargets, [TargetList], ComponentGroup)
	# stand still if enemy in weaponrange
	if TargetList.size() > 0:
		if RParam.AsBoolean(Eventbus().Read(C.eiIsMoving, [])):
			Eventbus().Trigger(C.eiStand, [])
		Result = false
	return Result
