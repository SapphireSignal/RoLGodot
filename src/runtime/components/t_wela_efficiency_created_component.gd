class_name TWelaEfficiencyCreatedComponent
extends TWelaEfficiencyComponent
## Port of TWelaEfficiencyCreatedComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:846,
## implementation :3177): the target's age in milliseconds (older targets first).


func GetEfficiencyToTarget(Entity) -> float:
	return RParam.ToSingle(TTimeManager.GetTimeStamp() - Entity.CreatedTimestamp)
