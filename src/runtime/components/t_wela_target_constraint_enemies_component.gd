class_name TWelaTargetConstraintEnemiesComponent
extends TWelaTargetConstraintTeamComponent
## Port of TWelaTargetConstraintEnemiesComponent (BaseConflict.EntityComponents.Shared.Wela.pas:420,
## implementation :1652): TWelaTargetConstraintTeamComponent for the other teams.


func CreateGrouped(Owner = null, Group = [], _TargetsEnemies: bool = true) -> TEntityComponent:
	return super(Owner, Group, true)
