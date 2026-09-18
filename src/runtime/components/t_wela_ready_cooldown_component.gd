class_name TWelaReadyCooldownComponent
extends TEntityComponent
## Port of TWelaReadyCooldownComponent (BaseConflict.EntityComponents.Shared.Wela.pas:767, implementation :1922).
## Ready after a cooldown (eiCooldown - eiWelaActionpoint of ReadyGroup, or a fixed Cooldown(ms)), restarted by
## eiFire in FireGroup (default: any). eiWelaActive false pauses it. The server writes the timer's start to
## eiCooldownStartingTime of its group; the client reads its timer from there (synced from the server).
## Once: after the first time it is ready, it stays ready.

var FCooldown: TGameTimer = null
var FReadyGroup: Array = []
var FFireGroup: Array = []
var FReadyAfterStart := false
var FOnce := false
var FOnceDone := false
var FFixedCooldown := false
var FFixedInterval := 0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnIsReady", C.eiIsReady, C.epFirst, C.etRead))
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnFire", C.eiFire, C.epLast, C.etTrigger))
	if not IsServerSide():
		e.append(XEvent("OnWriteCooldownStartingTime", C.eiCooldownStartingTime, C.epLast, C.etWrite))
	e.append(XEvent("OnCooldownRemainingTime", C.eiCooldownRemainingTime, C.epLast, C.etRead))
	e.append(XEvent("OnCooldownProgress", C.eiCooldownProgress, C.epLast, C.etRead))
	e.append(XEvent("OnSetWelaActive", C.eiWelaActive, C.epLast, C.etWrite))
	e.append(XEvent("OnCooldownReset", C.eiWelaCooldownReset, C.epLast, C.etTrigger))


func CreateGrouped(Owner = null, Group = [], ReadyAtStart: bool = false) -> TEntityComponent:
	super(Owner, Group)
	FReadyGroup = ComponentGroup
	FReadyAfterStart = ReadyAtStart
	FCooldown = TGameTimer.new().Create()
	InitTimer()
	return self


func Destroy() -> void:
	if FCooldown != null:
		FCooldown.Free()
	FCooldown = null
	super()


func InitTimer() -> void:
	StartTimer()
	OnSetWelaActive(Eventbus().Read(C.eiWelaActive, [], ComponentGroup))
	if FReadyAfterStart:
		FCooldown.Expired = true
	if IsServerSide():
		SaveTimer()
	else:
		UpdateTimer()


func StartTimer() -> void:
	if FFixedCooldown:
		FCooldown.Interval = FFixedInterval
	else:
		FCooldown.Interval = RParam.AsInteger(Eventbus().Read(C.eiCooldown, [], FReadyGroup)) \
				- RParam.AsInteger(Eventbus().Read(C.eiWelaActionpoint, [], FReadyGroup))
	FCooldown.Reset()


func FinishTimer() -> void:
	StartTimer()
	FCooldown.Expired = true


## Server: send time sync.
func SaveTimer() -> void:
	Eventbus().Write(C.eiCooldownStartingTime, [RParam.ToSingle(FCooldown.StartingTime)], ComponentGroup)


## Client: apply the server's timer.
func UpdateTimer() -> void:
	FCooldown.StartingTime = RParam.AsSingle(Eventbus().Read(C.eiCooldownStartingTime, [], ComponentGroup))


func IsReady() -> bool:
	if FOnce and FOnceDone:
		return true
	if not IsServerSide():
		UpdateTimer()
	var Result: bool = FCooldown.Expired and RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiWelaActive, [], ComponentGroup))
	if FOnce and Result:
		FOnceDone = true
	return Result


func OnIsReady(Previous):
	if not DSet.Intersects(TEventbus.CurrentEvent_CalledToGroup, FReadyGroup):
		return Previous
	var Result: bool = RParam.IsEmpty(Previous) or RParam.AsBoolean(Previous)
	return IsReady() and Result


## Apply wela active state.
func OnAfterCreate() -> bool:
	OnSetWelaActive(Eventbus().Read(C.eiWelaActive, [], ComponentGroup))
	if FReadyAfterStart:
		FCooldown.Expired = true
	if IsServerSide():
		SaveTimer()
	return true


## Restart cooldown.
func OnFire(_Targets) -> bool:
	if FFireGroup.is_empty() or DSet.Intersects(FFireGroup, TEventbus.CurrentEvent_CalledToGroup):
		StartTimer()
		if IsServerSide():
			SaveTimer()
	return true


## Client: retrieve sync from server.
func OnWriteCooldownStartingTime(StartingTime) -> bool:
	FCooldown.StartingTime = RParam.AsSingle(StartingTime)
	return true


## Returns the remaining time of this cooldown.
func OnCooldownRemainingTime():
	if FOnce and FOnceDone:
		return 0.0
	if FCooldown.Paused:
		return -1.0
	return RParam.ToSingle(FCooldown.TimeToExpired())


## Returns the percentage of remaining time of this cooldown.
func OnCooldownProgress():
	if FOnce and FOnceDone:
		return 1.0
	if FCooldown.Paused:
		return -1.0
	return RParam.ToSingle(clampf(FCooldown.ZeitDiffProzent(), 0.0, 1.0))


## Activates or deactivates this timer.
func OnSetWelaActive(IsActive) -> bool:
	StartTimer()
	if FReadyAfterStart:
		FCooldown.Expire()
	if not RParam.AsBooleanDefaultTrue(IsActive):
		FCooldown.Pause()
	else:
		FCooldown.Weiter()
	if IsServerSide():
		SaveTimer()
	return true


## Resets this timer.
func OnCooldownReset(Finish) -> bool:
	if RParam.AsBoolean(Finish):
		FinishTimer()
	else:
		StartTimer()
	if IsServerSide():
		SaveTimer()
	return true


## The ready group determines, where this component contribute its ready check. By default the ready group =
## component group.
func ReadyGroup(ReadyGroup_: Array) -> TWelaReadyCooldownComponent:
	FReadyGroup = DSet.Make(ReadyGroup_)
	InitTimer()  # reload cooldown
	return self


## The fire group determines, where this component is reset by fire.
func FireGroup(FireGroup_: Array) -> TWelaReadyCooldownComponent:
	FFireGroup = DSet.Make(FireGroup_)
	return self


func Cooldown(CooldownMs: int) -> TWelaReadyCooldownComponent:
	FFixedCooldown = true
	FFixedInterval = CooldownMs
	InitTimer()
	return self


func Once() -> TWelaReadyCooldownComponent:
	FOnce = true
	return self
