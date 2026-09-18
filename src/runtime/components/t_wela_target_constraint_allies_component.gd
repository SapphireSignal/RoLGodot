class_name TWelaTargetConstraintAlliesComponent
extends TWelaTargetConstraintTeamComponent
## Port of TWelaTargetConstraintAlliesComponent (BaseConflict.EntityComponents.Shared.Wela.pas:415,
## implementation :1645): TWelaTargetConstraintTeamComponent for the owner's team.


func CreateGrouped(Owner = null, Group = [], _TargetsEnemies: bool = false) -> TEntityComponent:
	return super(Owner, Group, false)
