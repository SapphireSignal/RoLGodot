class_name TWelaEffectFactoryComponent
extends TWelaEffectComponent
## Port of TWelaEffectFactoryComponent (GameServer/BaseConflict.EntityComponents.Server.Welas.pas:411,
## implementation :1244), server only. Spawns eiWelaCount (at least 1) units of eiWelaUnitPattern at each target
## through Game.ServerEntityManager.SpawnUnit: the owner's team (or SetSpawnedTeam), front, owning commander, card
## league / level and skin. A build target places the unit of eiWelaNeededGridSize on the grid and blocks its
## fields (not checked here: TWelaTargetConstraintGridComponent does that). For each unit eiWelaUnitProduced [ID]
## is triggered in the group the fire was called to (if any), then without group.
## Quirk kept: the build fields are blocked in the unit's PreProcessing, before SpawnUnit gives it its ID, so they
## hold entity ID 0 (TServerEntityManagerComponent.SpawnSpawner blocks with the real ID).
## Values are read in the group the fire was called to. Delphi's Random is Godot's RNG. The asserts of the original
## (empty pattern, build field outside every zone) are release-build silent: that unit / field is skipped.

var FNewTeam := -1
var FPassCardValues := false
var FSpawnsDifferentUnits := false
var FUseAoE := false
var FAoECircle := false
var FPassTargets := false
var FIsSpawner := false


func CreateGrouped(Entity = null, Group = []) -> TEntityComponent:
	super(Entity, Group)
	FNewTeam = -1
	return self


func Fire(Targets: Array) -> void:
	var Game = GlobalEventbus().Game
	var CalledToGroup: Array = TEventbus.CurrentEvent_CalledToGroup.duplicate()
	var Count := maxi(1, RParam.AsInteger(Eventbus().Read(C.eiWelaCount, [], CalledToGroup)))
	for index in Targets.size():
		var Target: RTarget = Targets[index].Clone()
		if FPassTargets and index != 0:
			return
		for i in Count:
			var Position := Target.GetTargetPosition(Game)
			var Front: Vector2 = Owner.Front
			var NeededGridSize := Vector2i.ZERO

			if Target.IsBuildTarget():
				NeededGridSize = RParam.AsIntVector2(Eventbus().Read(C.eiWelaNeededGridSize, [], CalledToGroup))
				Position = Target.GetRealBuildPosition(Game, NeededGridSize)
				Front = Target.GetBuildZone(Game).Front
			# apply spawn pattern when multispawn units
			if FUseAoE:
				var AoE = Eventbus().Read(C.eiWelaAreaOfEffect, [], CalledToGroup)
				if not RParam.IsEmpty(AoE):
					var Side: Vector2 = Front * RParam.AsSingle(AoE)
					if not FAoECircle:
						Side = Side * randf()
					Side = Side.rotated(randf() * 2 * PI)
					Position = Position + Side
				else:
					Position = RTarget.ComputeSpawningPattern(Position, Front, FIsSpawner, i, Count)

			var Pattern := ""
			var SkinID := ""
			if FSpawnsDifferentUnits:
				Pattern = RParam.AsString(Owner.Blackboard.GetIndexedValue(C.eiWelaUnitPattern, CalledToGroup, i))
				SkinID = RParam.AsString(Owner.Blackboard.GetIndexedValue(C.eiSkinIdentifier, CalledToGroup, i))
			if Pattern == "":
				Pattern = RParam.AsString(Eventbus().Read(C.eiWelaUnitPattern, [], CalledToGroup))
			if SkinID == "":
				SkinID = RParam.AsString(Eventbus().Read(C.eiSkinIdentifier, [], CalledToGroup))
			if SkinID == "":
				SkinID = Owner.SkinID

			if Pattern == "":
				continue
			var TeamID: int = FNewTeam if FNewTeam >= 0 else Owner.TeamID()

			if Front == Vector2.ZERO:
				Front = Game.Map.Lanes.GetOrientationOfNextLane(Game, Position, TeamID)

			var Setup := func(SpawnedEntity: TEntity) -> void:
				if FPassTargets:
					SpawnedEntity.Eventbus.Write(C.eiWelaSavedTargets, [ATarget.ToRParam(Targets)])
				# save target buildgrid, must be in setup, as the spawner can spawn directly after create
				if Target.IsBuildTarget():
					SpawnedEntity.Eventbus.Write(C.eiBuildgridOwner, [Target.GetBuildZone(Game).ID])
			var Preprocess := func(PreprocessedEntity: TEntity) -> void:
				_Preprocess(PreprocessedEntity, Game, Target, NeededGridSize, SkinID, CalledToGroup)
			var SpawnedEntity = Game.ServerEntityManager.SpawnUnit(Position, Front, Pattern, CardLeague(), CardLevel(),
				TeamID, RParam.AsInteger(Eventbus().Read(C.eiOwnerCommander, [])), Owner, Setup, Preprocess)
			if SpawnedEntity == null:
				continue

			if not CalledToGroup.is_empty():
				Eventbus().Trigger(C.eiWelaUnitProduced, [SpawnedEntity.ID], CalledToGroup)
			Eventbus().Trigger(C.eiWelaUnitProduced, [SpawnedEntity.ID])


## The PreProcessing of the spawned unit: card values, skin, blocked build fields.
func _Preprocess(PreprocessedEntity: TEntity, Game, Target: RTarget, NeededGridSize: Vector2i, SkinID: String, CalledToGroup: Array) -> void:
	if FPassCardValues:
		PreprocessedEntity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reCardTimesPlayed, Owner.Balance(C.reCardTimesPlayed, CalledToGroup))
		PreprocessedEntity.Blackboard.SetIndexedValue(C.eiResourceBalance, [], C.reLevel, Owner.Balance(C.reLevel, CalledToGroup))

	PreprocessedEntity.SkinID = SkinID
	PreprocessedEntity.Blackboard.SetValue(C.eiSkinIdentifier, [], SkinID)

	if Target.IsBuildTarget():
		# block gridfields
		var BlockedFieldGrids: Array = []
		for k in NeededGridSize.x * NeededGridSize.y:
			BlockedFieldGrids.append([0, Vector2i.ZERO])
		var j := 0
		for x in NeededGridSize.x:
			for y in NeededGridSize.y:
				var TargetPos: Vector2 = Target.GetBuildZone(Game).GetCenterOfField(Target.BuildGridCoordinate + Vector2i(x, y))
				var BuildZone: TBuildZone = Game.Map.BuildZones.GetBuildZoneByPosition(TargetPos)
				if BuildZone == null:
					continue
				BlockedFieldGrids[j] = [BuildZone.ID, BuildZone.PositionToCoord(TargetPos)]
				GlobalEventbus().Write(C.eiSetGridFieldBlocking, [BlockedFieldGrids[j][0], BlockedFieldGrids[j][1], PreprocessedEntity.ID])
				j += 1
		# save blocked gridfields, for refunding
		PreprocessedEntity.Eventbus.Write(C.eiBuildgridBlockedFields, [BlockedFieldGrids])


## Saves the resources reCardTimesPlayed and reLevel in the entity.
func PassCardValues() -> TWelaEffectFactoryComponent:
	FPassCardValues = true
	return self


## If this option is used the factory spawns different units found in the indices of eiWelaUnitPattern.
## Otherwise the return value of eiWelaUnitPattern is used for all spawned units.
func SpawnsDifferentUnits() -> TWelaEffectFactoryComponent:
	FSpawnsDifferentUnits = true
	return self


## Uses eiWelaAreaOfEffect for randomize spawning position.
func SpreadSpawns() -> TWelaEffectFactoryComponent:
	FUseAoE = true
	return self


## Uses eiWelaAreaOfEffect for randomize spawning position on a circle around target.
func SpreadSpawnsOnCircle() -> TWelaEffectFactoryComponent:
	FUseAoE = true
	FAoECircle = true
	return self


func IsSpawner() -> TWelaEffectFactoryComponent:
	FIsSpawner = true
	return self


## This option will spawn the entity at the first target and then save the targets with their index in
## eiWelaSavedTargets at the spawned entity.
func PassTargets() -> TWelaEffectFactoryComponent:
	FPassTargets = true
	return self


## Units spawned by this factory won't inherit the TeamID, but take the specified one.
func SetSpawnedTeam(TeamID: int) -> TWelaEffectFactoryComponent:
	FNewTeam = TeamID
	return self
