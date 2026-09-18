class_name TWelaEffectResetCooldownComponent
extends TWelaEffectComponent
## Port of TWelaEffectResetCooldownComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:522,
## implementation :2945), server only. On fire resets cooldowns on each entity target: eiWelaCooldownReset
## [Expire] to the target group plus the groups its eiWelaSearch finds for SearchForWelaBeacon (nothing if both
## are empty).

var FExpire := false
var FTargetGroup: Array = []
var FLookForGroup: Array = []  # SetUnitProperty


func Fire(Targets: Array) -> void:
	var game = GlobalEventbus().Game
	for Target in Targets:
		var TargetEntity = Target.TryGetTargetEntity(game)
		if TargetEntity != null:
			var ResetGroups: Array = FTargetGroup
			if not FLookForGroup.is_empty():
				ResetGroups = DSet.Union(ResetGroups, RParam.AsSet(TargetEntity.Eventbus.Read(C.eiWelaSearch, [FLookForGroup.duplicate()])))
			if not ResetGroups.is_empty():
				TargetEntity.Eventbus.Trigger(C.eiWelaCooldownReset, [FExpire], ResetGroups)


func TargetGroup(Group = []) -> TWelaEffectResetCooldownComponent:
	FTargetGroup = DSet.Make(Group)
	return self


func SearchForWelaBeacon(Properties = []) -> TWelaEffectResetCooldownComponent:
	FLookForGroup = DSet.Make(Properties)
	return self


func Expire() -> TWelaEffectResetCooldownComponent:
	FExpire = true
	return self
