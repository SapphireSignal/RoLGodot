class_name TBrainWelaSavedTargetComponent
extends TBrainWelaComponent
## Port of TBrainWelaSavedTargetComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:360,
## implementation :2323), server only. Welas aimed at saved targets: every chain (epMiddle), if eiIsReady, fires at
## eiWelaSavedTargets of SaveGroup (default []; FireAtIndex: only that one target, nothing if missing) when they
## pass eiWelaTargetPossible (unless DisableValidityCheck). Blocking: stands first and consumes the thought.

var FSaveGroup: Array = []
var FDisableValidityCheck := false
var FFireAtIndex := -1


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FFireAtIndex = -1
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epMiddle, C.etTrigger))


func OnThinkChain() -> bool:
	return ThinkChainEvent()


## The group to load the targets from. Defaults to [].
func SaveGroup(Group: Array) -> TBrainWelaSavedTargetComponent:
	FSaveGroup = DSet.Make(Group)
	return self


## Disables the check of the targets before the fire event is applied on them.
func DisableValidityCheck() -> TBrainWelaSavedTargetComponent:
	FDisableValidityCheck = true
	return self


func FireAtIndex(Index: int) -> TBrainWelaSavedTargetComponent:
	FFireAtIndex = Index
	return self


func ThinkChain() -> bool:
	var Result := true
	if RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup)):
		var Targets = Eventbus().Read(C.eiWelaSavedTargets, [], FSaveGroup)
		if RParam.IsEmpty(Targets):
			MakeException("OnThinkChain: No saved targets to use in group of this brain!")

		if FFireAtIndex >= 0:
			var NewTargets := ATarget.FromRParam(Targets)
			if NewTargets.size() <= FFireAtIndex:
				return Result
			Targets = ATarget.ToRParam(ATarget.Make(NewTargets[FFireAtIndex]))

		if FDisableValidityCheck or _TargetsPossible(Targets, ComponentGroup):
			# firing blocks the chain, so we have to break here
			if FBlocking:
				Eventbus().Trigger(C.eiStand, [])
				Result = false
			Eventbus().Trigger(FFireEvent, [Targets], ComponentGroup)
	return Result
