class_name TWelaTargetConstraintBlacklistComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintBlacklistComponent (BaseConflict.EntityComponents.Shared.Wela.pas:265,
## implementation :2900). The wela can't target entities saved in eiWelaSavedTargets of its group.


func IsPossible(Target: RTarget) -> bool:
	var SavedTargets := ATarget.FromRParam(Eventbus().Read(C.eiWelaSavedTargets, [], ComponentGroup))
	return not ATarget.Contains(SavedTargets, Target)
