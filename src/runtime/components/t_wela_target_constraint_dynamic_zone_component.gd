class_name TWelaTargetConstraintDynamicZoneComponent
extends TWelaTargetConstraintComponent
## Port of TWelaTargetConstraintDynamicZoneComponent (BaseConflict.EntityComponents.Shared.Wela.pas:382,
## implementation :1683). Only targets inside one of its dynamic zones of the owner's team (IgnoresTeams: any
## team), e.g. drops near towers: the global eiInDynamicZone read (empty counts as outside).

var FDynamicZone: Array = []
var FIgnoreTeam := false


func IsPossible(Target: RTarget) -> bool:
	var Pos := Target.GetTargetPosition(TargetGame())
	var TeamID: int = -1 if FIgnoreTeam else Owner.TeamID()
	return RParam.AsBoolean(GlobalEventbus().Read(C.eiInDynamicZone, [Pos, TeamID, FDynamicZone]))


func SetZone(Zone: Array) -> TWelaTargetConstraintDynamicZoneComponent:
	FDynamicZone = DSet.Make(Zone)
	return self


func IgnoresTeams() -> TWelaTargetConstraintDynamicZoneComponent:
	FIgnoreTeam = true
	return self
