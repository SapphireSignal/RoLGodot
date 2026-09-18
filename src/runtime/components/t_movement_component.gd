class_name TMovementComponent
extends TPositionComponent
## Port of TMovementComponent (BaseConflict.EntityComponents.Shared.pas:108, implementation :657).
## Handles movement of units. eiMoveTo sets a target (RTarget) and a range and starts moving; every global
## eiIdle moves the owner by ZDiff * eiSpeed (eiMove sets position and front) until the target is reached, then
## eiStand stops it and triggers eiMoveTargetReached.
## Two modes, chosen at eiAfterCreate by the unit data udUsePathfinding:
## - direct: straight towards the target until within range (a SPATIALEPSILON tolerance); the server syncs the
##   position every UNITSYNCINTERVAL.
## - pathfinding: the server computes a path (TPathfinding.ComputePath, at most PATHFINDING_MAX_COMPUTED_PATH_LENGTH)
##   and sends it as eiSyncPath [start, target, tile coordinates]; both sides walk it tile center by tile center
##   (the last tile: the exact target) and stop when on the target's tile. The server computes a new path when the
##   path runs out or the next tile is blocked. The client straightens the path (OptimizePath) and walks it at a
##   speed scaled so it arrives at the same time.
## Port: the original's Map global is the owner's Game.Map (none: no path), GameTimeManager.ZDiff is
## TTimeManager.ZDiff. Not ported: the network serialisation of FTarget ([XNetworkSerialize(eiMoveTo)]).

const SPATIALEPSILON = 0.1  # BaseConflict.Constants.pas:31
const UNITSYNCINTERVAL = 3000  # BaseConflict.Constants.pas:46
const PATHFINDING_MAX_COMPUTED_PATH_LENGTH = 15  # BaseConflict.Constants.pas:55

var FSyncTimer: TTimer = null  # server
var FOverwriteMovementSpeed := false  # client
var FOverwrittenSpeed := 0.0  # client
var FTargetPathfindingPosition := Vector2.ZERO
var FTarget := RTarget.CreateEmpty()
var FPath: Array = []  # Array[Vector2i], reversed: the next tile is the last
var FMoving := false
var FUsePathfinding := false
var FRange := 0.0


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnExiled", C.eiExiled, C.epLast, C.etWrite))
	e.append(XEvent("OnIsMoving", C.eiIsMoving, C.epFirst, C.etRead))
	e.append(XEvent("OnMoveTo", C.eiMoveTo, C.epLast, C.etTrigger))
	e.append(XEvent("OnMoveTargetReached", C.eiMoveTargetReached, C.epFirst, C.etRead))
	e.append(XEvent("OnStand", C.eiStand, C.epFirst, C.etTrigger))
	e.append(XEvent("OnMove", C.eiMove, C.epLast, C.etTrigger))
	e.append(XEvent("OnSyncPath", C.eiSyncPath, C.epLast, C.etTrigger))
	e.append(XEvent("OnIdle", C.eiIdle, C.epHigher, C.etTrigger, C.esGlobal))
	e.append(XEvent("OnDie", C.eiDie, C.epLast, C.etTrigger))
	e.append(XEvent("OnLose", C.eiLose, C.epMiddle, C.etTrigger, C.esGlobal))


func Create(Owner = null) -> TEntityComponent:
	super(Owner)
	if IsServerSide():
		FSyncTimer = TTimer.new().CreateAndStart(UNITSYNCINTERVAL)
	return self


func Destroy() -> void:
	if FSyncTimer != null:
		FSyncTimer.Free()
		FSyncTimer = null
	super()


func _Game():
	return GlobalEventbus().Game


## The original's Map.Pathfinding: the owner's Game.Map.Pathfinding, or null without a game, map or pathfinding.
func _Pathfinding():
	var Game = _Game()
	var Map = Game.get("Map") if Game != null else null
	return Map.get("Pathfinding") if Map != null else null


func _Speed() -> float:
	return RParam.AsSingle(Eventbus().Read(C.eiSpeed, []))


func ComputeNewPath() -> void:
	var Pathfinding = _Pathfinding()
	if Pathfinding == null:
		return
	Pathfinding.CancelLastComputedPath(Owner)
	# negate because IgnoreOtherEntities is the opposite of USE_PATHFINDING
	# USE_PATHFINDING is confusing caption, because if value false pathfinding will used but without
	# takeing other entites into account (entity will block timeslots but ignore other an so will walk through units)
	var IgnoreOtherEntities := not RParam.AsBooleanDefaultTrue(Owner.UnitData(C.udUsePathfinding))
	# Use direct (beeline heuristic) pathfinding if non-nexus entity is targeted
	var UseWaypoints := false
	if FTarget.IsEntity():
		var AEntity = FTarget.TryGetTargetEntity(_Game())
		if AEntity != null:
			UseWaypoints = RParam.AsSet(AEntity.Eventbus.Read(C.eiUnitProperties, [])).has(C.upNexus)
	var TargetPosition := FTarget.GetTargetPosition(_Game())
	var Path: Array = Pathfinding.ComputePath(Owner, TargetPosition, PATHFINDING_MAX_COMPUTED_PATH_LENGTH,
		UseWaypoints, IgnoreOtherEntities)
	var CoordPath: Array = Path.map(func(Tile): return Tile.GridPosition)
	Eventbus().Trigger(C.eiSyncPath, [Owner.Position, FTarget.GetTargetPosition(_Game()), CoordPath])


func IdleDirect() -> void:
	if FMoving:
		var walkingdistance := RParam.ToSingle(TTimeManager.ZDiff * _Speed())
		var Position: Vector2 = Owner.Position
		var targetPos := FTarget.GetTargetPosition(_Game())
		var between := targetPos - Position
		var distance := RParam.ToSingle(between.length())
		if TargetReached():
			between = between.normalized() * FRange
			Eventbus().Trigger(C.eiMove, [targetPos - between])
			Eventbus().Trigger(C.eiStand, [])
			return
		if distance - FRange <= walkingdistance:
			between = between.normalized() * FRange
			Eventbus().Trigger(C.eiMove, [targetPos - between])
			Eventbus().Trigger(C.eiStand, [])
		else:
			between = targetPos - Position
			Eventbus().Trigger(C.eiMove, [Position + (walkingdistance * between.normalized())])

	if IsServerSide() and FSyncTimer.Expired:
		Eventbus().Trigger(C.eiSyncPosition, [Owner.Position])
		FSyncTimer.Start()


func IdlePathfinding() -> void:
	if FMoving:
		var walkingdistance: float
		if not IsServerSide() and FOverwriteMovementSpeed:
			walkingdistance = RParam.ToSingle(TTimeManager.ZDiff * FOverwrittenSpeed)
		else:
			walkingdistance = RParam.ToSingle(TTimeManager.ZDiff * _Speed())
		# safety for lags
		if walkingdistance > 50 or walkingdistance < 0:
			walkingdistance = 0
		if FUsePathfinding:
			var Pathfinding = _Pathfinding()
			if Pathfinding == null:
				return
			var Position: Vector2 = Owner.Position
			if IsServerSide() and FPath.size() <= 0:
				ComputeNewPath()
				return
			while FPath.size() > 0:
				var Coord: Vector2i = FPath[-1]
				var NextNode: TPathfindingTile = Pathfinding.Grid(Coord.x, Coord.y)
				if IsServerSide():
					var CurrentTile = RParam.AsObject(Owner.Eventbus.Read(C.eiPathfindingTile, []))
					# if a tile (where unit next want to walk) and where the unit currently not stand, is
					# blocked, we need a new path, old path is no longer valid
					if CurrentTile != NextNode and NextNode.IsBlocked():
						# we need a new path
						ComputeNewPath()
						return
				var TargetTile = Pathfinding.GetTileByPosition(FTargetPathfindingPosition)
				var targetPos: Vector2
				if NextNode == TargetTile:
					targetPos = FTargetPathfindingPosition
				else:
					targetPos = NextNode.Center
				var distance := RParam.ToSingle(Position.distance_to(targetPos))
				if distance <= walkingdistance:
					Position = targetPos
					Eventbus().Trigger(C.eiMove, [Position])
					walkingdistance = RParam.ToSingle(walkingdistance - distance)
					FPath.resize(FPath.size() - 1)
					continue
				else:
					var between := (targetPos - Position).normalized()
					Position = Position + (between * walkingdistance)
					break
			Eventbus().Trigger(C.eiMove, [Position])
			if TargetReached():
				Eventbus().Trigger(C.eiStand, [])


## If unit dies, it shouldn't move any longer.
func OnDie(_KillerID, _KillerCommanderID) -> bool:
	Eventbus().Trigger(C.eiStand, [])
	return true


## Unit stops movement on exile.
func OnExiled(Exiled) -> bool:
	if RParam.AsBoolean(Exiled):
		Eventbus().Trigger(C.eiStand, [])
	return true


## Compute movement.
func OnIdle() -> bool:
	if FUsePathfinding:
		IdlePathfinding()
	else:
		IdleDirect()
	return true


func OnIsMoving():
	return FMoving


## Stop movement on lose (the server only stops; the client stands).
func OnLose(_TeamID) -> bool:
	if IsServerSide():
		FMoving = false
	else:
		Eventbus().Trigger(C.eiStand, [])
	return true


## Sets the entity to the target.
func OnMove(Target) -> bool:
	var Front: Vector2 = (RParam.AsVector2(Target) - Owner.Position).normalized()
	if Front != Vector2.ZERO:
		Owner.Front = Front
	Owner.Position = RParam.AsVector2(Target)
	return true


## Return whether the target has been reached.
func OnMoveTargetReached():
	return TargetReached()


## Sets the new movementtarget and start moving. Returns false (stopping the event) when already moving to an
## equal target.
func OnMoveTo(Target, Range) -> bool:
	FRange = RParam.AsSingle(Range)
	var NewTarget: RTarget = RParam.AsObject(Target)
	# cannot move to empty target
	if NewTarget == null or NewTarget.IsEmpty():
		return true
	# only start moving if new target is different from current or we're not moving at the moment
	var Result := not FTarget.Equal(NewTarget) or not FMoving
	if Result:
		var Position: Vector2 = Owner.Position
		FTarget = NewTarget.Clone()
		FMoving = true
		if IsServerSide():
			if FUsePathfinding:
				ComputeNewPath()
			Eventbus().Trigger(C.eiSyncPosition, [Position])
	return Result


## Stand still, now. Returns whether the unit was moving (stopping the event otherwise).
func OnStand() -> bool:
	var Result := FMoving
	FMoving = false
	if Result:
		FPath = []
		if IsServerSide():
			Eventbus().Trigger(C.eiSyncPosition, [Owner.Position])
		Eventbus().Trigger(C.eiMoveTargetReached, [])
	return Result


## Sets the walking path of the unit (Path: tile coordinates from start to target).
func OnSyncPath(_Start, Target, Path) -> bool:
	FTargetPathfindingPosition = RParam.AsVector2(Target)
	var Coords: Array = RParam.AsArray(Path)
	if IsServerSide():
		FPath = Coords.duplicate()
		FPath.reverse()
		return true
	var Pathfinding = _Pathfinding()
	if Pathfinding == null:
		FPath = []
		return true
	var nodePath: Array = Coords.map(func(Coord): return Pathfinding.Grid(Coord.x, Coord.y))
	var optimizedPath := OptimizePath(nodePath)
	if optimizedPath.size() != nodePath.size():
		var oldLength := RParam.ToSingle(Pathfinding.ComputePathLength(nodePath))
		FOverwrittenSpeed = RParam.ToSingle(RParam.ToSingle(Pathfinding.ComputePathLength(optimizedPath)) * _Speed() / oldLength)
		FOverwriteMovementSpeed = true
	else:
		FOverwriteMovementSpeed = false
	FPath = optimizedPath.map(func(Tile): return Tile.GridPosition)
	FPath.reverse()
	return true


## Client: drops the inner nodes a unit would pass anyway by always stepping to the optimal neighbour
## (TPathfindingTile.GetOptimalNeighbour towards the last node). The first and last nodes stay.
func OptimizePath(Path: Array) -> Array:
	# if path is shorter or equal two nodes, there is nothing to optimize
	if Path.size() <= 2:
		return Path
	var Target: TPathfindingTile = Path[-1]
	# the first node belongs to every path
	var Result: Array = [Path[0]]
	for i in range(1, Path.size() - 1):
		var NextNode: TPathfindingTile = Path[i + 1]
		var node: TPathfindingTile = Path[i]
		# if next node is best choice, we don't need it in path because the node is only the discreet
		if node.GetOptimalNeighbour(Target) == NextNode:
			continue
		Result.append(node)
	# the last node belongs to every path
	Result.append(Target)
	return Result


func TargetReached() -> bool:
	var Position: Vector2 = Owner.Position
	if FUsePathfinding:
		var Pathfinding = _Pathfinding()
		if Pathfinding == null:
			return false
		return Pathfinding.GetTileByPosition(Position) == Pathfinding.GetTileByPosition(FTarget.GetTargetPosition(_Game()))
	return RParam.ToSingle(Position.distance_to(FTarget.GetTargetPosition(_Game()))) - FRange <= SPATIALEPSILON


## Init.
func OnAfterCreate() -> bool:
	FUsePathfinding = RParam.AsBoolean(Owner.UnitData(C.udUsePathfinding))
	return true
