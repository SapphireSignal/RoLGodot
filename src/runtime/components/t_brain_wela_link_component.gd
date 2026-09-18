class_name TBrainWelaLinkComponent
extends TBrainTargetingWelaComponent
## Port of TBrainWelaLinkComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:979,
## implementation :1314), server only. Brain of link welas (the link effect does the rest). Each chain (epMiddle):
## breaks (eiLinkBreak [RTarget]) the links to targets eiWelaValidateTarget rejects, or all when the weapon is not
## ready; updates the targets when it has none or a build is ready (link timer, default 250 ms, expired and
## eiIsReady of SetBuildCheckGroup, default own group); no targets: the chain goes on; else preemptive brains stand
## and consume the thought, and a ready build fires eiFire at all targets in own group + build group and restarts
## the timer. A target set through eiWelaChangeTarget is fired at alone (after breaking the link it replaces).

const DEFAULT_LINK_BUILD_TIME = 250

var FLinkTimer: TTimer = null
var FBuildReadyGroup: Array = []


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FLinkTimer = TTimer.new().Create(DEFAULT_LINK_BUILD_TIME)
	FBuildReadyGroup = ComponentGroup
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnThinkChain", C.eiThinkChain, C.epMiddle, C.etTrigger))


func Destroy() -> void:
	FLinkTimer = null
	super()


## Time between building links.
func LinkTime(Time: int) -> TBrainWelaLinkComponent:
	FLinkTimer.SetIntervalAndStart(Time)
	return self


func SetBuildCheckGroup(Group: Array) -> TBrainWelaLinkComponent:
	FBuildReadyGroup = DSet.Make(Group)
	return self


func OnThinkChain() -> bool:
	return ThinkChainEvent()


func RemoveTarget(Index: int) -> void:
	if FCurrentTargets.size() > Index:
		Eventbus().Trigger(C.eiLinkBreak, [FCurrentTargets[Index]], ComponentGroup)
	super(Index)


func SetTarget(Index: int, Target: RTarget, _Replace: bool = true) -> void:
	if not ContainsTarget(Target):
		RemoveTarget(Index)
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Target))], ComponentGroup)
		super(Index, Target, false)


func ThinkChain() -> bool:
	# is the weapon ready to shoot, if not break all links
	var WeaponReady := RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], ComponentGroup))

	# check current targets, if not valid break the link
	for i in range(FCurrentTargets.size() - 1, -1, -1):
		if not WeaponReady or not RParam.AsBoolean(Eventbus().Read(C.eiWelaValidateTarget, [FCurrentTargets[i]],
			ComponentGroup)):
			RemoveTarget(i)

	var BuildReady := FLinkTimer.Expired and \
		RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FBuildReadyGroup))

	if WeaponReady and (FCurrentTargets.size() <= 0 or BuildReady):
		UpdateTargets()
	if FCurrentTargets.size() <= 0:
		return true

	var Result := not FPreemptive
	if not Result:
		Eventbus().Trigger(C.eiStand, [])

	if BuildReady:
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(FCurrentTargets)], DSet.Union(ComponentGroup, FBuildReadyGroup))
		FLinkTimer.Start()
	return Result
