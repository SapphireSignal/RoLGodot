class_name TWelaTargetConstraintTeamIDComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintTeamIDComponent (BaseConflict.EntityComponents.Shared.Wela.pas:395,
## implementation :1445). Only entities of the target team (Invert: of every other team).

var FTargetTeamID := 0
var FInvert := false


func IsPossible(Target: RTarget) -> bool:
	var TargetEntity = Target.GetTargetEntity(TargetGame())
	if TargetEntity == null:
		return false
	if FInvert:
		return TargetEntity.TeamID() != FTargetTeamID
	return TargetEntity.TeamID() == FTargetTeamID


func SetTargetTeam(TeamID: int) -> TWelaTargetConstraintTeamIDComponent:
	FTargetTeamID = TeamID
	return self


## Targets everything except the target team id.
func Invert() -> TWelaTargetConstraintTeamIDComponent:
	FInvert = true
	return self
