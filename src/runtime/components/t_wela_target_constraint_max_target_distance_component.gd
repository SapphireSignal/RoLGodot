class_name TWelaTargetConstraintMaxTargetDistanceComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintMaxTargetDistanceComponent (BaseConflict.EntityComponents.Shared.Wela.pas:241,
## implementation :1659). Meant to keep all targets within eiAbilityTargetRange of each other.
## Quirk kept: the original tests IsEmpty where it means "is set", so it only compares empty targets (all at the
## same spot) and never fails in practice.


func Check(Targets: Array, Validity: RTargetValidity) -> void:
	var j := 0
	for Target in Targets:
		if Target.IsEmpty():
			j += 1
	if j <= 1:
		return
	var Range := RParam.AsSingle(Eventbus().Read(C.eiAbilityTargetRange, [], ComponentGroup))
	if Range <= 0:
		return
	var game = TargetGame()
	for i in range(Targets.size() - 1):
		if Targets[i].IsEmpty():
			for k in range(i + 1, Targets.size()):
				if Targets[k].IsEmpty() and Targets[i].GetTargetPosition(game).distance_to(Targets[k].GetTargetPosition(game)) > Range:
					Validity.SetTogetherValid(false)
					break
