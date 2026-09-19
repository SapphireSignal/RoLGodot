class_name TBrainActionComponent
extends TBrainComponent
## Port of TBrainActionComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:893, implementation
## :2879), server only. Sits on top of the think chain (epHigher) and delays shots so animations can play:
## eiPreFire [ATarget] in a group fires eiFire there at once if eiWelaActionpoint <= 0, else after the action
## point (a TDelayedEventHandler; at that time it checks CanThink, eiIsReady and eiWelaTargetPossible again, else
## cancels: eiCancelFire to the group). Either way it locks the chain (its handler returns False) for
## max(1, action point, eiWelaActionduration) ms and while a shot is pending. Exile cancels a pending shot, unless
## the shot itself exiled the unit.
## Port note: the delayed shot is queued in GlobalEventbus().Game.DelayedEvents (ServerGame's queue); without it
## (tests without a game) the shot is dropped.

var FTargets: Array = []  # ATarget
var FFireGroup: Array = []
var FEventHandler: TDelayedEventHandler = null
var FLock: TTimer = null
var FInFireHandling := false


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FEventHandler = TDelayedEventHandler.new().Create(Fire)
	FLock = TTimer.new().Create()
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnPreFire", C.eiPreFire, C.epLast, C.etTrigger))
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epHigher, C.etTrigger))
	e.append(XEvent("OnExiled", C.eiExiled, C.epLast, C.etWrite))


func Destroy() -> void:
	if FEventHandler != null:
		FEventHandler.Free()
		FEventHandler = null
	FLock = null
	super()


func CancelFire() -> void:
	FLock.Expired = true
	Eventbus().Trigger(C.eiCancelFire, [], FFireGroup)


func Fire() -> void:
	if CanThink() and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FFireGroup)) and \
		_TargetsPossible(ATarget.ToRParam(FTargets), FFireGroup):
		FInFireHandling = true
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(FTargets)], FFireGroup)
		FInFireHandling = false
	else:
		CancelFire()


func OnExiled(Exiled) -> bool:
	# if current fire handling exiles this unit, it won't cancel itself
	if RParam.AsBoolean(Exiled) and not FInFireHandling:
		CancelFire()
		FEventHandler.UnregisterEvent()
	return true


func OnPreFire(Targets) -> bool:
	var CalledToGroup: Array = TEventbus.GetCurrentEvent_CalledToGroup().duplicate()
	var ActionPoint := RParam.AsInteger(Eventbus().Read(C.eiWelaActionpoint, [], CalledToGroup))
	if ActionPoint <= 0:
		Eventbus().Trigger(C.eiFire, [Targets], CalledToGroup)
	else:
		FFireGroup = CalledToGroup
		FTargets = ATarget.FromRParam(Targets).duplicate()
		var game = BrainGame()
		var Queue = game.get("DelayedEvents") if game != null else null
		if Queue != null:
			FEventHandler.RegisterEvent(ActionPoint, Queue)
	var ActionDuration := RParam.AsInteger(Eventbus().Read(C.eiWelaActionduration, [], CalledToGroup))
	ActionDuration = maxi(ActionPoint, ActionDuration)
	FLock.Interval = maxi(1, ActionDuration)
	FLock.Start()
	return true


func OnThinkChain() -> bool:
	return not FEventHandler.IsWaiting() and FLock.Expired
