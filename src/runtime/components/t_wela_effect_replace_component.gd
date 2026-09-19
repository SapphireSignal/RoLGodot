class_name TWelaEffectReplaceComponent
extends TWelaEffectComponent
## Port of TWelaEffectReplaceComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:337,
## implementation :997), server only. Replaces each entity target with a new unit of eiWelaUnitPattern (of its
## group), e.g. for upgrading a spawner: the target gets eiDelayedKillEntity, the new unit spawns at its position
## and front with its card league / level, owning commander and team (or SetNewTeam), the owner's skin. Then
## KeepTakenDamage takes the target's missing health off the new unit, KeepResource copies a balance of the target,
## the target gets eiWelaUnitProduced [new ID] in this group, and the global eiReplaceEntity [target ID, new ID,
## False] informs all interested parties.
## Fixed bugs of the original: eiReplaceEntity named the owner and KeepResource read the owner's balance, not the
## replaced target's (the same entity in every script; docs/original-bugs.md). A non-entity target is logged and skipped.

var FNewTeam := 0
var FKeepTakenDamage := false
var FResource: int = C.reNone


func Fire(Targets: Array) -> void:
	var Game = GlobalEventbus().Game
	for i in Targets.size():
		var Target: RTarget = Targets[i]
		if not Target.IsEntity():
			push_warning("TWelaEffectReplaceComponent.Fire: Only entities are valid targets!")
			continue
		var TargetEntity = Target.TryGetTargetEntity(Game)
		if TargetEntity == null:
			continue
		var TeamID: int = FNewTeam if FNewTeam != 0 else TargetEntity.TeamID()

		GlobalEventbus().Trigger(C.eiDelayedKillEntity, [TargetEntity.ID])
		var SkinID: String = Owner.SkinID
		var Preprocess := func(PreprocessedEntity: TEntity) -> void:
			PreprocessedEntity.SkinID = SkinID
			PreprocessedEntity.Blackboard.SetValue(C.eiSkinIdentifier, [], SkinID)
		var newEntity = Game.ServerEntityManager.SpawnUnit(TargetEntity.Position, TargetEntity.Front,
			RParam.AsString(Eventbus().Read(C.eiWelaUnitPattern, [], ComponentGroup)), TargetEntity.CardLeague(),
			TargetEntity.CardLevel(), TeamID, RParam.AsInteger(TargetEntity.Eventbus.Read(C.eiOwnerCommander, [])),
			Owner, Callable(), Preprocess)
		if newEntity == null:
			continue  # the original crashed
		if FKeepTakenDamage:
			var takenDamage := RParam.AsSingle(TargetEntity.Eventbus.Read(C.eiResourceCap, [C.reHealth]))
			takenDamage = takenDamage - RParam.AsSingle(TargetEntity.Eventbus.Read(C.eiResourceBalance, [C.reHealth]))
			newEntity.Eventbus.Trigger(C.eiResourceTransaction, [C.reHealth, RParam.ToSingle(-takenDamage)])
		if FResource != C.reNone:
			var OldResource = TargetEntity.Eventbus.Read(C.eiResourceBalance, [FResource])
			newEntity.Eventbus.Write(C.eiResourceBalance, [FResource, OldResource])
		TargetEntity.Eventbus.Trigger(C.eiWelaUnitProduced, [newEntity.ID], ComponentGroup)
		GlobalEventbus().Trigger(C.eiReplaceEntity, [TargetEntity.ID, newEntity.ID, false])


func SetNewTeam(NewTeam: int) -> TWelaEffectReplaceComponent:
	FNewTeam = NewTeam
	return self


func KeepTakenDamage() -> TWelaEffectReplaceComponent:
	FKeepTakenDamage = true
	return self


func KeepResource(Resource: int) -> TWelaEffectReplaceComponent:
	FResource = Resource
	return self
