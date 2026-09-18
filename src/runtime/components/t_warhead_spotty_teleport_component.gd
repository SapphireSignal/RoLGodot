class_name TWarheadSpottyTeleportComponent
extends TWarheadComponent
## Port of TWarheadSpottyTeleportComponent (GameServer/BaseConflict.EntityComponents.Server.Warheads.pas:66,
## implementation :925), server only. Teleports an entity: the imprinted one (ImprintTeleportedID) or each entity
## target to its team's nexus (ToNexus; else the farthest nexus, the NexusNext quirk) or to the fixed target
## (ToTarget / ToCoordinate); without either the owner itself goes to the target.
## Unless imprinted: Offset / OffsetByCollisionRadius put it that far (+ both radii) from an entity destination, on
## its own side; the entity is exiled and re-keyed (global eiReplaceEntity [ID, new unique ID, True]) so every
## targeting lets go of it. Then either the entity arrives at once (position, eiStand, eiSyncPosition, eiExiled
## False) or, AsProjectile, a projectile of eiWelaUnitPattern flies from it towards the destination carrying a
## teleport warhead in group [0] imprinted with the entity and aimed at the ground at the destination (+ offset).
## Quirk kept: the projectile's owning commander is the owner's ID (the original passes FOwner.ID).
## Port: a missing nexus (assert in the original, then a crash) skips the teleport.

var FAsProjectile := false
var FToNexus := false
var FOffsetByCollisionRadius := false
var FTeleportedEntityID := -1
var FOffset := 0.0
var FFixedTarget := RTarget.CreateEmpty()


func CreateGrouped(Owner = null, Group = []) -> TEntityComponent:
	super(Owner, Group)
	FTeleportedEntityID = -1
	return self


func FireWarhead(Targets: Array) -> void:
	var Game = GlobalEventbus().Game
	for i in Targets.size():
		var Target: RTarget = Targets[i].Clone()
		var TeleportedEntity = Game.EntityManager.TryGetEntityByID(FTeleportedEntityID)
		if TeleportedEntity == null:
			TeleportedEntity = Target.TryGetTargetEntity(Game)
		if TeleportedEntity == null:
			continue
		var TeleportTarget: RTarget
		var TargetEntity = null
		# teleport target to owning teams nexus
		if FToNexus:
			TargetEntity = Game.EntityManager.TryGetNexusByTeamID(TeleportedEntity.TeamID())
			if TargetEntity == null:
				TargetEntity = Game.EntityManager.NexusNext(TeleportedEntity.Position)
			if TargetEntity == null:
				continue
			TeleportTarget = RTarget.Create(TargetEntity)
		# teleport imprinted target to target
		elif not FFixedTarget.IsEmpty():
			TeleportTarget = FFixedTarget.Clone()
		# teleport owner to target
		else:
			TeleportedEntity = Owner
			TeleportTarget = Target

		var TeleportOffset := Vector2.ZERO
		if FTeleportedEntityID < 0:
			if FOffset > 0 or FOffsetByCollisionRadius:
				TargetEntity = TeleportTarget.TryGetTargetEntity(Game)
				if TargetEntity != null:
					var OffsetRange := FOffset
					if FOffsetByCollisionRadius:
						OffsetRange = RParam.ToSingle(OffsetRange + TargetEntity.CollisionRadius + TeleportedEntity.CollisionRadius)
					TeleportOffset = TWelaTargetingRadialComponent.Normalize(TeleportedEntity.Position - TargetEntity.Position) * OffsetRange

			# remove entity from battlefield
			TeleportedEntity.Eventbus.Write(C.eiExiled, [true])
			# break up targeting stuff by virtually converting unit into new unit
			GlobalEventbus().Trigger(C.eiReplaceEntity, [TeleportedEntity.ID, Game.EntityManager.GenerateUniqueID(), true])

		if FAsProjectile:
			# save entity in projectile
			var SkinID: String = Owner.GetSkinID(ComponentGroup)
			var Destination := TeleportTarget.GetTargetPosition(Game)
			var Setup := func(Entity: TEntity) -> void:
				var GroundTarget := RTarget.Create(TeleportTarget.GetTargetPosition(Game) + TeleportOffset)
				TWarheadSpottyTeleportComponent.new().CreateGrouped(Entity, [0]) \
					.ImprintTeleportedID(TeleportedEntity.ID) \
					.ToTarget(GroundTarget)
				Entity.Eventbus.Write(C.eiWelaSavedTargets, [ATarget.ToRParam(ATarget.Make(GroundTarget))])
				Entity.SkinID = SkinID
				Entity.Blackboard.SetValue(C.eiSkinIdentifier, [], SkinID)
			Game.ServerEntityManager.SpawnUnit(TeleportedEntity.Position,
				TWelaTargetingRadialComponent.Normalize(Destination - TeleportedEntity.Position),
				RParam.AsString(Eventbus().Read(C.eiWelaUnitPattern, [], ComponentGroup)), CardLeague(), CardLevel(),
				Owner.TeamID(), Owner.ID, Owner, Setup)
		else:
			var TeleportTo := TeleportTarget.GetTargetPosition(Game)
			TeleportedEntity.Position = TeleportTo + TeleportOffset
			TeleportedEntity.Eventbus.Trigger(C.eiStand, [])
			# SyncPosition is needed, because some units such as towers don't react on eiStand, which normally syncs position
			TeleportedEntity.Eventbus.Trigger(C.eiSyncPosition, [TeleportTo + TeleportOffset])
			# bring entity back to the battlefield
			TeleportedEntity.Eventbus.Write(C.eiExiled, [false])


## The teleported entity will be moved "range" towards their between vector.
func Offset(Range: float) -> TWarheadSpottyTeleportComponent:
	FOffset = RParam.ToSingle(Range)
	return self


func OffsetByCollisionRadius() -> TWarheadSpottyTeleportComponent:
	FOffsetByCollisionRadius = true
	return self


func ImprintTeleportedID(ID: int) -> TWarheadSpottyTeleportComponent:
	FTeleportedEntityID = ID
	return self


## Makes the teleport not instant, but by a projectile in eiWelaUnitpattern.
func AsProjectile() -> TWarheadSpottyTeleportComponent:
	FAsProjectile = true
	return self


## Target is teleported to the next friendly nexus.
func ToNexus() -> TWarheadSpottyTeleportComponent:
	FToNexus = true
	return self


## Target is teleported to specified target.
func ToTarget(Target: RTarget) -> TWarheadSpottyTeleportComponent:
	FFixedTarget = Target.Clone()
	return self


func ToCoordinate(CoordinateX: float, CoordinateY: float) -> TWarheadSpottyTeleportComponent:
	return ToTarget(RTarget.Create(Vector2(RParam.ToSingle(CoordinateX), RParam.ToSingle(CoordinateY))))
