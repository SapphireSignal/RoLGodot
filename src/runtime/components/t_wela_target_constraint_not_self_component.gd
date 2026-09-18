class_name TWelaTargetConstraintNotSelfComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintNotSelfComponent (BaseConflict.EntityComponents.Shared.Wela.pas:257,
## implementation :1566). The wela can't target its own unit.


func IsPossible(Target: RTarget) -> bool:
	return not Target.IsEntity() or Target.EntityID != FOwner.ID
