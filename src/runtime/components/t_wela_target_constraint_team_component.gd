class_name TWelaTargetConstraintTeamComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintTeamComponent (BaseConflict.EntityComponents.Shared.Wela.pas:407, implementation
## :1469). Only entities of another team (TargetsEnemies) or of the owner's team.

var FTargetsEnemies := false


func CreateGrouped(Owner = null, Group = [], TargetsEnemies: bool = false) -> TEntityComponent:
	super(Owner, Group)
	FTargetsEnemies = TargetsEnemies
	return self


func IsPossible(Target: RTarget) -> bool:
	var TargetEntity = Target.GetTargetEntity(TargetGame())
	if TargetEntity == null:
		return false
	return (FTargetsEnemies and TargetEntity.TeamID() != Owner.TeamID()) \
		or (not FTargetsEnemies and TargetEntity.TeamID() == Owner.TeamID())
