class_name TThinkImpulseTimerCooldownComponent
extends TGDEntityComponent
## Port of TThinkImpulseTimerCooldownComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:130,
## implementation :1781), server only. Thinks in its group at the first global eiIdle after every eiCooldown of its
## group (read once in the constructor; the timer starts then, unless TimerIsReady). Once: only the first time.
## Thinks even while exiled.

var FThinkTimer: TTimer = null
var FOnce := false
var FFired := false


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	var Interval = Eventbus().Read(C.eiCooldown, [], ComponentGroup)
	if RParam.IsEmpty(Interval):
		MakeException("CreateGrouped: This component needs an interval in eiCooldown!")
	FThinkTimer = TTimer.new().CreateAndStart(RParam.AsInteger(Interval))
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIdle", C.eiIdle, C.epMiddle, C.etTrigger, C.esGlobal))


func Destroy() -> void:
	FThinkTimer = null
	super()


func OnIdle() -> bool:
	if FThinkTimer.Expired and (not FOnce or not FFired):
		Eventbus().Trigger(C.eiThink, [], ComponentGroup)
		Eventbus().Trigger(C.eiThinkChain, [], ComponentGroup)
		FThinkTimer.Start()
		FFired = true
	return true


func TimerIsReady() -> TThinkImpulseTimerCooldownComponent:
	FThinkTimer.Expired = true
	return self


func Once() -> TThinkImpulseTimerCooldownComponent:
	FOnce = true
	return self
