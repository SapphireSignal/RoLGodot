class_name TModifierWelaRangeComponent
extends TModifierComponent
## Port of TModifierWelaRangeComponent (BaseConflict.EntityComponents.Shared.Wela.pas:176, implementation :2910).
## While active, multiplies (or adds, AddModifier) eiWelaRange of its groups with Factor = eiWelaModifier of
## ValueGroup (default 1); the result is at least 1. ScaleWithTime scales Factor by the progress of a timer over
## eiCooldown of ValueGroup (started at once; ActivateOnStand restarts it on eiStand, DeactivateOnMoveTo resets and
## pauses it on eiMoveTo). ScaleWithStage multiplies by the tier of the first commander (server) or of the active
## commander (client).

var FTimer: TTimer = null
var FScaleWithTime := false
var FActivateOnStand := false
var FAdditive := false
var FDeactivateOnMoveTo := false
var FScaleWithStage := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWelaRange", C.eiWelaRange, C.epMiddle, C.etRead))
	e.append(XEvent("OnStand", C.eiStand, C.epLast, C.etTrigger))
	e.append(XEvent("OnMoveTo", C.eiMoveTo, C.epLast, C.etTrigger))


func Destroy() -> void:
	if FTimer != null:
		FTimer.Free()
	FTimer = null
	super()


func OnWelaRange(Previous):
	if RParam.IsEmpty(Previous) or not IsActive():
		return Previous
	var Factor := RParam.AsSingleDefault(Eventbus().Read(C.eiWelaModifier, [], FValueGroup), 1.0)
	if FTimer != null:
		Factor = RParam.ToSingle(Factor * FTimer.ZeitDiffProzent(true))
	if FScaleWithStage:
		var game = GlobalEventbus().Game
		if IsServerSide():
			if game != null and game.Commanders.size() > 0:
				Factor = RParam.ToSingle(Factor * RParam.AsInteger(game.Commanders[0].Balance(C.reTier)))
		elif game != null:
			Factor = RParam.ToSingle(Factor * RParam.AsInteger(game.CommanderManager.ActiveCommander.Balance(C.reTier)))
	if FAdditive:
		return RParam.ToSingle(maxf(1.0, RParam.AsSingle(Previous) + Factor))
	return RParam.ToSingle(maxf(1.0, RParam.AsSingle(Previous) * Factor))


## Start time scaling.
func OnStand() -> bool:
	if FTimer != null and FActivateOnStand:
		FTimer.Start()
	return true


## Stop time scaling resetting it.
func OnMoveTo(_Target, _Range) -> bool:
	if FTimer != null and FDeactivateOnMoveTo:
		FTimer.StartAndPause()
	return true


## Adds the modifier to the value instead of multiplying it with it.
func AddModifier() -> TModifierWelaRangeComponent:
	FAdditive = true
	return self


## Scales the modifier by a time factor in eiCooldown of value group.
func ScaleWithTime() -> TModifierWelaRangeComponent:
	FTimer = TTimer.new().CreateAndStart(RParam.AsInteger(Eventbus().Read(C.eiCooldown, [], FValueGroup)))
	return self


## Scales the modifier by stage times eiModifier.
func ScaleWithStage() -> TModifierWelaRangeComponent:
	FScaleWithStage = true
	return self


## Time scaling is started on stand and not on create.
func ActivateOnStand() -> TModifierWelaRangeComponent:
	FActivateOnStand = true
	return self


func DeactivateOnMoveTo() -> TModifierWelaRangeComponent:
	FDeactivateOnMoveTo = true
	return self
