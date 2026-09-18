class_name TWelaTargetConstraintBuildTeamComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintBuildTeamComponent (BaseConflict.EntityComponents.Shared.Wela.pas:249,
## implementation :1515). Only build targets in a build zone of the owner's team.


func IsPossible(Target: RTarget) -> bool:
	if not Target.IsBuildTarget():
		return false
	var TargetBuildZone: TBuildZone = Target.GetBuildZone(TargetGame())
	return TargetBuildZone != null and TargetBuildZone.TeamID == Owner.TeamID()
