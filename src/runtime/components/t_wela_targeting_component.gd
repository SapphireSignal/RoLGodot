class_name TWelaTargetingComponent
extends TEntityComponent
## Port of TWelaTargetingComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:40, implementation
## :1117), server only. Base of a wela's targeting: eiWelaUpdateTargets [Targets] (trigger, epMiddle) updates the
## caller's target list (an Array of RTarget, changed in place), eiWelaValidateTarget [Target] (read, epFirst)
## answers whether one target (RTarget or empty) can still be targeted. Subclasses override UpdateTargets and
## ValidateTarget.
## Port notes: the original's TList<RTarget>.Contains used Delphi's default record comparer, a memory compare that
## also sees fields the RTarget constructors leave uninitialised; the port compares with RTarget.Equal (what the code
## means). Delphi's Random is Godot's RNG here (the server randomizes at start, nothing to reproduce).

var FPickRandom := false
var FRepetition := false
var FValidateGroup: Array = []
var FTargetTeamConstraint: int = C.tcEnemies
var FTargetPriorization: int = C.tcAll
var FMaxNewTargetCount := 0


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FValidateGroup = ComponentGroup
	FTargetTeamConstraint = C.tcEnemies
	FTargetPriorization = C.tcAll
	return self


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnUpdateShootingTargets", C.eiWelaUpdateTargets, C.epMiddle, C.etTrigger))
	e.append(XEvent("OnValidateTarget", C.eiWelaValidateTarget, C.epFirst, C.etRead))


## The Game targets are resolved in (the original's Game global).
func TargetGame():
	return GlobalEventbus().Game


## Abstract: update the list of targets (Array of RTarget), removing invalid and adding new ones.
func UpdateTargets(_CurrentList: Array) -> void:
	pass


## Abstract: whether Target can be targeted.
func ValidateTarget(_Target: RTarget) -> bool:
	return false


func IsTargetPossible(Target, TargetGroup: Array) -> bool:
	if Target == null or RParam.AsBoolean(Target.Eventbus.Read(C.eiExiled, [])):
		return false
	return RTargetValidity.FromRParam(Eventbus().Read(C.eiWelaTargetPossible,
		[ATarget.ToRParam(ATarget.Make(Target))], TargetGroup)).IsValid()


## eiEfficiency of the target in TargetGroup (+ 0.01 for the prioritized team), or -1 if it is not a possible target.
func FetchEfficiency(Target, TargetGroup: Array) -> float:
	if IsTargetPossible(Target, TargetGroup):
		var Result := RParam.AsSingle(Eventbus().Read(C.eiEfficiency, [Target], TargetGroup))
		if FTargetPriorization != C.tcAll:
			if _IsPrioritized(Target):
				Result = RParam.ToSingle(Result + 0.01)
		return Result
	return -1.0


func _IsPrioritized(Target) -> bool:
	return (FTargetPriorization == C.tcEnemies and Owner.TeamID() != Target.TeamID()) \
		or (FTargetPriorization == C.tcAllies and Owner.TeamID() == Target.TeamID())


## TList<RTarget>.Contains (see the port notes above).
static func ContainsTarget(List: Array, Target: RTarget) -> bool:
	for Item in List:
		if Item.Equal(Target):
			return true
	return false


func OnUpdateShootingTargets(Targets) -> bool:
	UpdateTargets(Targets)
	return true


func OnValidateTarget(Target):
	if RParam.IsEmpty(Target):
		return ValidateTarget(RTarget.Create(null))
	return ValidateTarget(Target)


## Picks random targets from PossibleTargetList (Array of TEntity or null) and adds them to the current targets,
## the prioritized team first. Every picked entity gets eiWelaYoureMyTarget [Owner].
func PickRandomTargets(CurrentTargetList, PossibleTargetList) -> void:
	if PossibleTargetList == null or CurrentTargetList == null:
		return
	var MaxTargets := maxi(1, RParam.AsInteger(Eventbus().Read(C.eiWelaTargetCount, [], ComponentGroup)))
	var MaxNew := 10000 if FMaxNewTargetCount <= 0 else FMaxNewTargetCount
	var PrioritizedTargets: Array = []
	var Targets: Array
	if FTargetPriorization != C.tcAll:
		Targets = []
		for Target in PossibleTargetList:
			if _IsPrioritized(Target):
				PrioritizedTargets.append(Target)
			else:
				Targets.append(Target)
	else:
		Targets = PossibleTargetList

	while (PrioritizedTargets.size() > 0 or Targets.size() > 0) and CurrentTargetList.size() < MaxTargets and MaxNew > 0:
		var PickList: Array = PrioritizedTargets if PrioritizedTargets.size() > 0 else Targets
		var pick := randi_range(0, PickList.size() - 1)
		if FRepetition or not ContainsTarget(CurrentTargetList, RTarget.Create(PickList[pick])):
			CurrentTargetList.append(RTarget.Create(PickList[pick]))
			PickList[pick].Eventbus.Trigger(C.eiWelaYoureMyTarget, [Owner])
			MaxNew -= 1
		if not FRepetition:
			PickList.remove_at(pick)


## Set type of targets the wela can attack (e.g. tcAllies). Default is tcEnemies.
func SetTargetTeamConstraint(Value: int) -> TWelaTargetingComponent:
	FTargetTeamConstraint = Value
	return self


## The wela can target everything, but prioritizes the set team.
func SetTargetTeamConstraintPriority(Value: int) -> TWelaTargetingComponent:
	FTargetTeamConstraint = C.tcAll
	FTargetPriorization = Value
	return self


## Validate existing targets against another group's modules.
func SetValidateGroup(Group: Array) -> TWelaTargetingComponent:
	FValidateGroup = DSet.Make(Group)
	return self


func PicksRandomTargets() -> TWelaTargetingComponent:
	FPickRandom = true
	return self


func PicksRandomTargetsWithRepetition() -> TWelaTargetingComponent:
	FPickRandom = true
	FRepetition = true
	return self


func MaxNewTargetCount(Count: int) -> TWelaTargetingComponent:
	FMaxNewTargetCount = Count
	return self
