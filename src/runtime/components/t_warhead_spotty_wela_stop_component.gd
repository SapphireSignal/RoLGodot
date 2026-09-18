class_name TWarheadSpottyWelaStopComponent
extends TWarheadSpottyComponent
## Port of TWarheadSpottyWelaStopComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:215,
## implementation :1226), server only. Resets the targets of each target entity's welas: eiWelaStop.


func ApplyEffect(Entity: TEntity) -> void:
	Entity.Eventbus.Trigger(C.eiWelaStop, [])
