class_name TWelaTargetConstraintMaxTargetDistanceComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintMaxTargetDistanceComponent (BaseConflict.EntityComponents.Shared.Wela.pas:241,
## implementation :1659): all set targets must lie within eiAbilityTargetRange of each other (Relocate).
## Fixed bug of the original: it tested IsEmpty where it means "is set", so it only compared empty targets and never
## failed (docs/original-bugs.md).


func Check(Targets: Array, Validity: RTargetValidity) -> void:
	var j := 0
	for Target in Targets:
		if not Target.IsEmpty():
			j += 1
	if j <= 1:
		return
	var Range := RParam.AsSingle(Eventbus().Read(C.eiAbilityTargetRange, [], ComponentGroup))
	if Range <= 0:
		return
	var game = TargetGame()
	for i in range(Targets.size() - 1):
		if not Targets[i].IsEmpty():
			for k in range(i + 1, Targets.size()):
				if not Targets[k].IsEmpty() and Targets[i].GetTargetPosition(game).distance_to(Targets[k].GetTargetPosition(game)) > Range:
					Validity.SetTogetherValid(false)
					break
