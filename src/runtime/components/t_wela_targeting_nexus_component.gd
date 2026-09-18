class_name TWelaTargetingNexusComponent
extends TWelaTargetingComponent
## Port of TWelaTargetingNexusComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:94,
## implementation :2785), server only. The target is the enemy nexus Game.EntityManager.TryGetNexusNextEnemy
## returns (quirk kept there: the farthest one); valid while it exists and its efficiency is > 0.
## Without a Game (tests) there is no nexus.


func UpdateTargets(CurrentList: Array) -> void:
	CurrentList.clear()
	var Game = TargetGame()
	var opponentNexus = Game.EntityManager.TryGetNexusNextEnemy(Owner) if Game != null else null
	if opponentNexus != null:
		CurrentList.append(RTarget.Create(opponentNexus))


func ValidateTarget(Target: RTarget) -> bool:
	var Entity = Target.TryGetTargetEntity(TargetGame())
	var Result := Target.IsEntity() and Entity != null
	if Result:
		Result = FetchEfficiency(Entity, FValidateGroup) > 0
	return Result
