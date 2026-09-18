class_name TThinkImpulseTimerComponent
extends TEntityComponent
## Port of TThinkImpulseTimerComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:111,
## implementation :1462), server only. Used by all units: thinks in its group at the first global eiIdle after
## every THINK_TIME_INTERVAL (250 ms; the timer starts at creation), and at the next eiIdle after
## eiMoveTargetReached. Not while exiled or dead (eiIsAlive false; empty counts as alive).

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FThinkTimer: TTimer = null


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FThinkTimer = TTimer.new().CreateAndStart(BC.THINK_TIME_INTERVAL)
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnMoveTargetReached", C.eiMoveTargetReached, C.epLast, C.etTrigger))
	e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))


func Destroy() -> void:
	FThinkTimer = null
	super()


func OnIdle() -> bool:
	if not RParam.AsBoolean(Eventbus().Read(C.eiExiled, [])):
		var Alive = Eventbus().Read(C.eiIsAlive, [])
		if FThinkTimer.Expired and (RParam.IsEmpty(Alive) or RParam.AsBoolean(Alive)):
			Eventbus().Trigger(C.eiThink, [], ComponentGroup)
			Eventbus().Trigger(C.eiThinkChain, [], ComponentGroup)
			FThinkTimer.Start()
	return true


func OnMoveTargetReached() -> bool:
	FThinkTimer.Expired = true
	return true
