class_name TAutoBrainOnCommanderAbilityUsedComponent
extends TAutoBrainComponent
## Port of TAutoBrainOnCommanderAbilityUsedComponent (GameServer/BaseConflict.EntityComponents.Server.Brains.pas:729,
## implementation :3101), server only. At every global eiCommanderAbilityUsed [TeamID, ATarget] (epMiddle), if the
## brain can think (ConstraintOnSameTeamID: the owner's team only; ConstraintOnInWelaRange: a target within
## eiWelaRange of its group), runs CheckAndFire with the spell's targets as default targets.

var FConstraintOnSameTeamID := false
var FConstraintOnInWelaRange := false


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnCommanderAbilityUsed", C.eiCommanderAbilityUsed, C.epMiddle, C.etTrigger, C.esGlobal))


func OnCommanderAbilityUsed(TeamID, TargetsRaw) -> bool:
	if not CanThink():
		return true
	if FConstraintOnSameTeamID and RParam.AsInteger(TeamID) != Owner.TeamID():
		return true
	var Targets := ATarget.FromRParam(TargetsRaw).duplicate()
	if FConstraintOnInWelaRange:
		var AnyTargetInRange := false
		var WelaRange := RParam.AsSingle(Eventbus().Read(C.eiWelaRange, [], ComponentGroup))
		var game = BrainGame()
		for Target: RTarget in Targets:
			if Owner.Position.distance_to(Target.GetTargetPosition(game)) <= WelaRange:
				AnyTargetInRange = true
				break
		if not AnyTargetInRange:
			return true
	CheckAndFire(Targets)
	return true


func ConstraintOnInWelaRange() -> TAutoBrainOnCommanderAbilityUsedComponent:
	FConstraintOnInWelaRange = true
	return self


func ConstraintOnSameTeamID() -> TAutoBrainOnCommanderAbilityUsedComponent:
	FConstraintOnSameTeamID = true
	return self
