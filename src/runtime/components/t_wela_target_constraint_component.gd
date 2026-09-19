class_name TWelaTargetConstraintComponent
extends TGDEntityComponent
## Port of TWelaTargetConstraintComponent (BaseConflict.EntityComponents.Shared.Wela.pas:222, implementation
## :1363). Base of the checks on a wela's targets: eiWelaTargetPossible (or, with ConstraintsWarhead,
## eiWarheadTargetPossible) read [Targets: ATarget] in its group returns an RTargetValidity that each constraint
## narrows (epHigher). Subclasses override IsPossible (one target) or Check (all of them together).

const BC = preload("res://src/runtime/base_conflict_constants.gd")

var FForWarhead := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnTargetPossible", C.eiWelaTargetPossible, C.epHigher, C.etRead))
	e.append(XEvent("OnTargetPossible", C.eiWarheadTargetPossible, C.epHigher, C.etRead))


## The Game the targets are resolved in (the original's Game global).
func TargetGame():
	return GlobalEventbus().Game


## Makes a single check for a target.
func IsPossible(_Target: RTarget) -> bool:
	return true


## Makes a single check for each target. Can be overridden for meta-checks of multiple items in combination.
func Check(Targets: Array, Validity: RTargetValidity) -> void:
	for i in Targets.size():
		Validity.SetValidity(i, IsPossible(Targets[i]))


## Return the result of the constraint.
func OnTargetPossible(Targets, PrevValue):
	var Event := TEventbus.GetCurrentEvent_EventIdentifier()
	if ((not FForWarhead and Event == C.eiWelaTargetPossible) or (FForWarhead and Event == C.eiWarheadTargetPossible)) \
			and IsLocalCall():
		var TargetList := ATarget.FromRParam(Targets)
		var Validity: RTargetValidity
		if RParam.IsEmpty(PrevValue):
			Validity = RTargetValidity.Create(TargetList)
		else:
			Validity = RTargetValidity.FromRParam(PrevValue)
		Check(TargetList, Validity)
		return Validity
	return PrevValue


func ConstraintsWarhead() -> TWelaTargetConstraintComponent:
	FForWarhead = true
	return self
