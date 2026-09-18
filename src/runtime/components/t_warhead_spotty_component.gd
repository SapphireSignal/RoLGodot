class_name TWarheadSpottyComponent
extends TWarheadComponent
## Port of TWarheadSpottyComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:59, implementation
## :318), server only. Master class of the warheads that act on single entities: ApplyEffect on each target entity
## that still exists, in target order.


func FireWarhead(Targets: Array) -> void:
	var game = GlobalEventbus().Game
	for Target in Targets:
		var Entity = Target.TryGetTargetEntity(game)
		if Entity != null:
			ApplyEffect(Entity)


## Abstract.
func ApplyEffect(_Entity: TEntity) -> void:
	pass
