class_name TAutoBrainBilateralComponent
extends TBrainComponent
## Port of TAutoBrainBilateralComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:489,
## implementation :2799), server only. Base of event brains with two sides, the event's targets and the owner.
## Fire(Targets): FireSelfInGroup(G) fires eiFire at the owner in G if eiIsReady / eiWelaTargetPossible of G allow
## (and the targets pass CheckTargetsForSelfInGroup, if set); FireTargetsInGroup(G) likewise fires at the targets
## (and the owner must pass CheckSelfForTargetsInGroup, if set). Unlike TAutoBrainComponent it does not think
## passively by default.

var FFiresAtSelf := false
var FFiresAtTargets := false
var FSelfFireGroup: Array = []
var FTargetsFireGroup: Array = []
var FCheckSelfForTargetsInGroup: Array = []
var FCheckTargetsForSelfInGroup: Array = []


## Executes the set options for firing.
func Fire(Targets: Array) -> void:
	var Self_ := ATarget.ToRParam(ATarget.Make(Owner))
	if FFiresAtSelf and \
		RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FSelfFireGroup)) and \
		_TargetsPossible(Self_, FSelfFireGroup) and \
		(FCheckTargetsForSelfInGroup.is_empty() or
		_TargetsPossible(ATarget.ToRParam(Targets), FCheckTargetsForSelfInGroup)):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(ATarget.Make(Owner))], FSelfFireGroup)
	if FFiresAtTargets and \
		RParam.AsBooleanDefaultTrue(Eventbus().Read(C.eiIsReady, [], FTargetsFireGroup)) and \
		_TargetsPossible(ATarget.ToRParam(Targets), FTargetsFireGroup) and \
		(FCheckSelfForTargetsInGroup.is_empty() or
		_TargetsPossible(ATarget.ToRParam(ATarget.Make(Owner)), FCheckSelfForTargetsInGroup)):
		Eventbus().Trigger(C.eiFire, [ATarget.ToRParam(Targets)], FTargetsFireGroup)


## Group for checks and fire for targets.
func FireTargetsInGroup(Group: Array) -> TAutoBrainBilateralComponent:
	FFiresAtTargets = true
	FTargetsFireGroup = DSet.Make(Group)
	return self


## Checks local group on owner for firing at targets as well.
func CheckSelfForTargetsInGroup(Group: Array) -> TAutoBrainBilateralComponent:
	FCheckSelfForTargetsInGroup = DSet.Make(Group)
	return self


## Group for checks and fire for self.
func FireSelfInGroup(Group: Array) -> TAutoBrainBilateralComponent:
	FFiresAtSelf = true
	FSelfFireGroup = DSet.Make(Group)
	return self


## Checks local group on targets for firing at owner as well.
func CheckTargetsForSelfInGroup(Group: Array) -> TAutoBrainBilateralComponent:
	FCheckTargetsForSelfInGroup = DSet.Make(Group)
	return self
