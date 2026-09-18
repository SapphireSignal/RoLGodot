class_name TWelaTargetingSelfComponent
extends TWelaTargetingComponent
## Port of TWelaTargetingSelfComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:103,
## implementation :3229), server only. The only target is the owner; valid while its efficiency is > 0.


func UpdateTargets(CurrentList: Array) -> void:
	CurrentList.clear()
	CurrentList.append(RTarget.Create(Owner))


func ValidateTarget(Target: RTarget) -> bool:
	var Result: bool = Target.IsEntity() and Target.EntityID == Owner.ID
	if Result:
		Result = FetchEfficiency(Owner, FValidateGroup) > 0
	return Result
