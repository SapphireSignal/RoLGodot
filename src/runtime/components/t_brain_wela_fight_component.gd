class_name TBrainWelaFightComponent
extends TBrainTargetingWelaComponent
## Port of TBrainWelaFightComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:962,
## implementation :1392), server only. The default brain of nearly every unit's weapon. Each chain:
## 1. drops the targets eiWelaValidateTarget rejects;
## 2. updates the targets (UpdateTargets) if none is left valid or the weapon is ready;
## 3. no targets: the chain goes on (to the approach / lane brains);
## 4. targets: preemptive brains consume the thought and stand (once, when they become active); if eiIsReady they
##    fire FFireEvent at all targets (ChangeTargetToMyself: at the owner, once per target; DisableTargetLock: drop
##    the targets after firing); a blocking brain stands before (when not preemptive) and consumes the thought.

var FDisableTargetLock := false
var FFireAtMyself := false
var FWasActive := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epMiddle, C.etTrigger))


func ChangeTargetToMyself() -> TBrainWelaFightComponent:
	FFireAtMyself = true
	return self


func DisableTargetLock() -> TBrainWelaFightComponent:
	FDisableTargetLock = true
	return self


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func ThinkChain() -> bool:
	# check current targets, whether there is at least one valid target
	var AtLeastOneTargetOk := false
	for i in range(FCurrentTargets.size() - 1, -1, -1):
		if RParam.AsBoolean(Eventbus().Read(C.eiWelaValidateTarget, [FCurrentTargets[i]], ComponentGroup)):
			AtLeastOneTargetOk = true
		else:
			RemoveTarget(i)
	var WeaponReady := RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup))
	# search for targets in attackrange if targets are not ok or weapon is ready
	# search for new targets if weapon not ready to prevent walking although a target is in range
	if not AtLeastOneTargetOk or WeaponReady:
		UpdateTargets()

	# no valid targets in range, let next brain think (and walk to next target)
	if FCurrentTargets.size() <= 0:
		FWasActive = false
		return true
	var Result := not FPreemptive
	# if wela is preemptive and there are targets, we stand to wait for activation, but only if not already waiting
	if not FWasActive and FPreemptive:
		Eventbus().Trigger(C.eiStand, [])
	# Fire!
	if WeaponReady:
		# if wela is blocking we want to stand on fire as afterwards the thinking is blocked
		if not FWasActive and not FPreemptive and FBlocking:
			Eventbus().Trigger(C.eiStand, [])

		if FFireAtMyself:
			var Target := ATarget.ToRParam(ATarget.Make(FOwner))
			for i in FCurrentTargets.size():
				Eventbus().Trigger(FFireEvent, [Target], ComponentGroup)
		else:
			Eventbus().Trigger(FFireEvent, [ATarget.ToRParam(FCurrentTargets)], ComponentGroup)

		if FDisableTargetLock:
			for i in range(FCurrentTargets.size() - 1, -1, -1):
				RemoveTarget(i)

		# if this wela is blocking, we have to interrupt think chain after firing to prevent other welas to cancel action
		if FBlocking:
			Result = false
	FWasActive = not Result
	return Result
