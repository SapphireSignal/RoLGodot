class_name TWarheadSpottyKillComponent
extends TWarheadSpottyComponent
## Port of TWarheadSpottyKillComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:91,
## implementation :328), server only. Kills each target entity at once, regardless of shields or abilities:
## eiKill [OwnerID, owner's eiOwnerCommander], then eiKillDone [TargetID] in its group if the target died.
## Exile writes eiExiled := True first, Sacrifice triggers eiSacrifice [same] first. Remove only sends the global
## eiDelayedKillEntity [TargetID] (no death).

var FSacrifice := false
var FExile := false
var FRemove := false


func ApplyEffect(Entity: TEntity) -> void:
	if FRemove:
		GlobalEventbus().Trigger(C.eiDelayedKillEntity, [Entity.ID])
		return
	if FExile:
		Entity.Eventbus.Write(C.eiExiled, [true])
	if FSacrifice:
		Entity.Eventbus.Trigger(C.eiSacrifice, [Owner.ID, Owner.Eventbus.Read(C.eiOwnerCommander, [])])
	Entity.Eventbus.Trigger(C.eiKill, [Owner.ID, Owner.Eventbus.Read(C.eiOwnerCommander, [])])
	if not RParam.AsBoolean(Entity.Eventbus.Read(C.eiIsAlive, [])):
		Eventbus().Trigger(C.eiKillDone, [Entity.ID], ComponentGroup)


func Sacrifice() -> TWarheadSpottyKillComponent:
	FSacrifice = true
	return self


func Exile() -> TWarheadSpottyKillComponent:
	FExile = true
	return self


func Remove() -> TWarheadSpottyKillComponent:
	FRemove = true
	return self
