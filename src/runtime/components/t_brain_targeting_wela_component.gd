class_name TBrainTargetingWelaComponent
extends TBrainWelaComponent
## Port of TBrainTargetingWelaComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:919,
## implementation :1060), server only. Base of the brains with persistent targets (a list, the first is the main
## target), kept up to date by the group's targeting (eiWelaUpdateTargets changes the list in place). Its eiThinkChain
## handler moves to epHigh (Preemptive: back to epMiddle, so non-preemptive brains think before the main gun).
## eiWelaStop clears the targets, eiWelaChangeTarget [RTarget] makes one the main target if eiWelaValidateTarget
## allows (or is empty), eiGetCurrentTargets (epFirst) appends the targets to the previous list. The main target is
## announced with eiWelaSetMainTarget [RTarget] (empty when the last target goes).
## Port note: the list's comparer is the original's RTarget "=", RTarget.Equal here.

var FCurrentTargets: Array = []  # of RTarget
var FPreemptive := false


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FPreemptive = false
	FFireEvent = C.eiFire
	ChangeEventPriority(C.eiThinkChain, C.etTrigger, C.epHigh)
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWelaStop", C.eiWelaStop, C.epLast, C.etTrigger))
	e.append(XEvent("OnChangeTarget", C.eiWelaChangeTarget, C.epLast, C.etTrigger))
	e.append(XEvent("OnGetCurrentTargets", C.eiGetCurrentTargets, C.epFirst, C.etRead))


func Destroy() -> void:
	FCurrentTargets = []
	super()


## Preemptive brains block the think chain while they have possible targets (the main gun of a unit). They fire
## eiPreFire.
func Preemptive() -> TBrainTargetingWelaComponent:
	FPreemptive = true
	FFireEvent = C.eiPreFire
	# increase priority of non-preemptive brains to trigger before
	ChangeEventPriority(C.eiThinkChain, C.etTrigger, C.epMiddle)
	return self


func OnChangeTarget(Target) -> bool:
	var Possible = Eventbus().Read(C.eiWelaValidateTarget, [Target], ComponentGroup)
	if RParam.IsEmpty(Possible) or RParam.AsBoolean(Possible):
		SetTarget(0, Target if Target is RTarget else RTarget.CreateEmpty(), true)
	return true


func OnGetCurrentTargets(PrevValue):
	var Result: Array = [] if RParam.IsEmpty(PrevValue) else PrevValue
	Result.append_array(FCurrentTargets)
	return Result


func OnWelaStop() -> bool:
	for i in range(FCurrentTargets.size() - 1, -1, -1):
		RemoveTarget(i)
	return true


func ContainsTarget(Target: RTarget) -> bool:
	for Item: RTarget in FCurrentTargets:
		if Item.Equal(Target):
			return true
	return false


func RemoveTarget(Index: int) -> void:
	if FCurrentTargets.size() > Index:
		FCurrentTargets.remove_at(Index)
	# no more valid target exists? inform everybody about
	if FCurrentTargets.size() <= 0:
		Eventbus().Trigger(C.eiWelaSetMainTarget, [RTarget.CreateEmpty()], ComponentGroup)


## Take care that no replacement will insert the target and may violate the max target count.
func SetTarget(Index: int, Target: RTarget, Replace: bool = true) -> void:
	if Index == 0:
		Eventbus().Trigger(C.eiWelaSetMainTarget, [Target], ComponentGroup)
	if FCurrentTargets.size() > Index:
		if Replace:
			FCurrentTargets[Index] = Target
		else:
			FCurrentTargets.insert(Index, Target)
	else:
		FCurrentTargets.append(Target)


func UpdateTargets() -> void:
	# if not enough targets, we are searching for more
	Eventbus().Trigger(C.eiWelaUpdateTargets, [FCurrentTargets], ComponentGroup)
	# if our target count shrunk, we may have too many targets at this point, so we have to check them
	var MaxTargets := maxi(0, RParam.AsIntegerDefault(Eventbus().Read(C.eiWelaTargetCount, [], ComponentGroup), 1))
	while MaxTargets < FCurrentTargets.size():
		RemoveTarget(FCurrentTargets.size() - 1)
	# the first of our targets is our main target
	if FCurrentTargets.size() > 0:
		Eventbus().Trigger(C.eiWelaSetMainTarget, [FCurrentTargets[0]], ComponentGroup)
