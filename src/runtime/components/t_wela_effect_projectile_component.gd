class_name TWelaEffectProjectileComponent
extends TWelaEfficiencyEffectComponent
## Port of TWelaEffectProjectileComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:549,
## implementation :1822), server only. Spawns a projectile (eiWelaUnitPattern of its group) per target (eiWelaCount
## per target with MultipleProjectiles) through Game.ServerEntityManager.SpawnUnit, from the owner (IsLinkEffect:
## from eiLinkSource, ReverseLink: eiLinkDest; a commander without position shoots from the target), facing the
## owner's front, with the owner's team, commander, card league / level and skin of the group. Before its script
## finishes the projectile gets a TProjectileEventRedirecter, upProjectile, the group's eiWelaDamage,
## eiWelaSplashfactor, eiWelaAreaOfEffect, eiDamageType, eiWelaTargetCount, eiWelaCount (blackboard group [0], so
## it is independent after launch) and eiWelaSavedTargets = the target (Reverse: flies from the target to the
## owner). After deploy the owner gets eiWelaShotProjectile [projectile] in its group, then without group.
## Efficiency: 1 against any target that is not upUntargetable, else -1.
## Quirk kept: a shooter standing exactly at (0, 0) counts as having no position (a commander), so its projectile
## starts at the target.
## Port: an empty link list falls back to the owner (the original read past the array).

var FReverse := false
var FIsLinkEffect := false
var FReverseLink := false
var FMultipleProjectiles := false


func Fire(Targets: Array) -> void:
	var Game = GlobalEventbus().Game
	var Count := 1
	if FMultipleProjectiles:
		Count = RParam.AsIntegerDefault(Eventbus().Read(C.eiWelaCount, [], ComponentGroup), 1)
	if Count <= 0:
		return
	for i in Targets.size():
		var Target: RTarget = Targets[i].Clone()
		var StartingEntity = Owner
		if FIsLinkEffect:
			var LinkTarget: Array
			if FReverseLink:
				LinkTarget = ATarget.FromRParam(Eventbus().Read(C.eiLinkDest, []))
			else:
				LinkTarget = ATarget.FromRParam(Eventbus().Read(C.eiLinkSource, []))
			if not LinkTarget.is_empty():
				StartingEntity = LinkTarget[0].TryGetTargetEntity(Game)
				if StartingEntity == null:
					StartingEntity = Owner
		var Position: Vector2
		if FReverse:
			Position = Target.GetTargetPosition(Game)
		else:
			# if a commander shoots a projectile, there is no starting position, so use from target
			Position = StartingEntity.Position
			if Position == Vector2.ZERO:
				Position = Target.GetTargetPosition(Game)

		var SkinID: String = Owner.GetSkinID(ComponentGroup)
		var SavedTarget := ATarget.Make(StartingEntity) if FReverse else ATarget.Make(Target)
		var Preprocess := func(PreprocessedEntity: TEntity) -> void:
			_Preprocess(PreprocessedEntity, SavedTarget, SkinID)
		var Postprocess := func(Entity: TEntity) -> void:
			Eventbus().Trigger(C.eiWelaShotProjectile, [Entity], ComponentGroup)
			if not ComponentGroup.is_empty():
				Eventbus().Trigger(C.eiWelaShotProjectile, [Entity])
		for ii in Count:
			Game.ServerEntityManager.SpawnUnit(Position, Owner.Front,
				RParam.AsString(Eventbus().Read(C.eiWelaUnitPattern, [], ComponentGroup)), CardLeague(), CardLevel(),
				Owner.TeamID(), RParam.AsInteger(Eventbus().Read(C.eiOwnerCommander, [])), Owner, Callable(),
				Preprocess, Postprocess, "")


func _Preprocess(PreprocessedEntity: TEntity, SavedTarget: Array, SkinID: String) -> void:
	TProjectileEventRedirecter.new().Create(PreprocessedEntity)
	var UnitProperties := RParam.AsSet(PreprocessedEntity.Blackboard.GetValue(C.eiUnitProperties, []))
	UnitProperties = DSet.Make(UnitProperties + [C.upProjectile])
	PreprocessedEntity.Blackboard.SetValue(C.eiUnitProperties, [], UnitProperties)

	for Event in [C.eiWelaDamage, C.eiWelaSplashfactor, C.eiWelaAreaOfEffect, C.eiDamageType, C.eiWelaTargetCount, C.eiWelaCount]:
		var Value = Eventbus().Read(Event, [], ComponentGroup)
		if not RParam.IsEmpty(Value):
			PreprocessedEntity.Blackboard.SetValue(Event, [0], Value)

	PreprocessedEntity.Blackboard.SetValue(C.eiWelaSavedTargets, [], ATarget.ToRParam(SavedTarget))

	PreprocessedEntity.SkinID = SkinID
	PreprocessedEntity.Blackboard.SetValue(C.eiSkinIdentifier, [], SkinID)


func GetEfficiency(_TargetsInRange: Array) -> float:
	return RParam.AsSingle(Eventbus().Read(C.eiWelaDamage, [], ComponentGroup))


func GetEfficiencyToTarget(Entity) -> float:
	var IsPossible: bool = not RParam.AsSet(Entity.Eventbus.Read(C.eiUnitProperties, [])).has(C.upUntargetable)
	return 1.0 if IsPossible else -1.0


## Shoots at each target eiWelaCount projectiles.
func MultipleProjectiles() -> TWelaEffectProjectileComponent:
	FMultipleProjectiles = true
	return self


## Shoots the projectile from Target to self.
func Reverse() -> TWelaEffectProjectileComponent:
	FReverse = true
	return self


## Shoots from eiLinkSource and not from self.
func IsLinkEffect() -> TWelaEffectProjectileComponent:
	FIsLinkEffect = true
	return self


## Shoots from eiLinkDest and not from self.
func ReverseLink() -> TWelaEffectProjectileComponent:
	FReverseLink = true
	return self
