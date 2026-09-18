class_name TBrainWelaCommanderComponent
extends TBrainComponent
## Port of TBrainWelaCommanderComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:857,
## implementation :1154), server only. Runs commander abilities the player picked targets for:
## eiCanUseAbility [ACommanderAbilityTarget] (read, epLast, in the group the read was called to): false if the brain
## cannot think or fewer targets than eiAbilityTargetCount (min 1) came; else, if eiIsReady (empty = ready; the
## sandbox skips it), the extra targets are cut off and the RTargets must pass eiWelaTargetPossible (the sandbox
## skips it too); not ready answers the eiIsReady value. eiUseAbility [targets] (epMiddle) fires eiFire at them
## when eiCanUseAbility allows (OverrideTargetToOwner: at the owner instead), and returns False otherwise.
## Port note: Game.IsSandbox is read from GlobalEventbus().Game (no Game: not a sandbox).

var FOverrideTargetToOwner := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnCanRunAbility", C.eiCanUseAbility, C.epLast, C.etRead))
	e.append(XEvent("OnUseAbility", C.eiUseAbility, C.epMiddle, C.etTrigger))


func IsSandbox() -> bool:
	var game = BrainGame()
	return game != null and game.IsSandbox()


func OverrideTargetToOwner() -> TBrainWelaCommanderComponent:
	FOverrideTargetToOwner = true
	return self


func CanUseAbility(Targets: Array) -> bool:
	return IsSandbox() or _TargetsPossible(ATarget.ToRParam(RCommanderAbilityTarget.ToRTargets(Targets, Owner)),
		TEventbus.CurrentEvent_CalledToGroup.duplicate())


## The original asserts eiAbilityTargetCount = the target count here (a debug-build check; dropped like in release).
func UseAbility(Targets: Array) -> void:
	var CalledToGroup: Array = TEventbus.CurrentEvent_CalledToGroup.duplicate()
	Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(RCommanderAbilityTarget.ToRTargets(Targets, Owner))], CalledToGroup)


func OnCanRunAbility(Targets):
	if not CanThink():
		return false
	var CalledToGroup: Array = TEventbus.CurrentEvent_CalledToGroup.duplicate()
	var Result = Eventbus().Read(C.eiIsReady, [], CalledToGroup)
	if RParam.AsBooleanDefaultTrue(Result) or IsSandbox():
		var TargetCount := maxi(1, RParam.AsInteger(Eventbus().Read(C.eiAbilityTargetCount, [], CalledToGroup)))
		var Targ: Array = RCommanderAbilityTarget.ArrayFromRParam(Targets)
		if Targ.size() < TargetCount:
			return false
		# truncate unneeded targets
		Targ = Targ.slice(0, TargetCount)
		Result = CanUseAbility(Targ)
	return Result


func OnUseAbility(Targets) -> bool:
	if RParam.AsBoolean(Eventbus().Read(C.eiCanUseAbility, [Targets], TEventbus.CurrentEvent_CalledToGroup.duplicate())):
		if FOverrideTargetToOwner:
			UseAbility([RCommanderAbilityTarget.Create(Owner)])
		else:
			UseAbility(RCommanderAbilityTarget.ArrayFromRParam(Targets))
		return true
	return false
