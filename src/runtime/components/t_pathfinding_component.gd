class_name TPathfindingComponent
extends TEntityComponent
## Port of TPathfindingComponent (BaseConflict.EntityComponents.Shared.pas:497, implementation :2161).
## Keeps the owner's current pathfinding tile (eiPathfindingTile). The owner blocks its tile when created and
## whenever it stands; moving onto another tile unblocks the old one without blocking the new one (so walking
## units block nothing until they stop). Standing also drops the owner's computed path.
## The original's Map global is the owner's Game.Map; without it or its pathfinding (tests, no game) the
## component does nothing.

var FCurrentTile: TPathfindingTile = null


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWritePosition", C.eiPosition, C.epLast, C.etWrite))
	e.append(XEvent("OnStand", C.eiStand, C.epLast, C.etTrigger))
	e.append(XEvent("OnAfterCreate", C.eiAfterCreate, C.epLast, C.etTrigger))
	e.append(XEvent("OnPathfindingTile", C.eiPathfindingTile, C.epFirst, C.etRead))


func Destroy() -> void:
	var Pathfinding = _Pathfinding()
	if Pathfinding != null:
		if FCurrentTile != null:
			FCurrentTile.UnblockTile(Owner)
		Pathfinding.CancelLastComputedPath(Owner)
	FCurrentTile = null
	super()


## The original's Map.Pathfinding: the owner's Game.Map.Pathfinding, or null without a game, map or pathfinding.
func _Pathfinding():
	var Game = GlobalEventbus().Game
	var Map = Game.get("Map") if Game != null else null
	return Map.get("Pathfinding") if Map != null else null


## If a entity is created it will block a tile. Port: a position outside the map has no tile (the original
## crashed there); then nothing is blocked.
func OnAfterCreate() -> bool:
	var Pathfinding = _Pathfinding()
	if Pathfinding == null:
		return true
	FCurrentTile = Pathfinding.GetTileByPosition(Owner.Position)
	if FCurrentTile != null:
		FCurrentTile.BlockTile(Owner)
	return true


## Return the current used pathfinding tile.
func OnPathfindingTile():
	return FCurrentTile


## If stand, the entity should no longer reserve any timeslots.
func OnStand() -> bool:
	var Pathfinding = _Pathfinding()
	if Pathfinding == null:
		return true
	Pathfinding.CancelLastComputedPath(Owner)
	if FCurrentTile != null:
		FCurrentTile.BlockTile(Owner)
	return true


## Updates the position on map.
func OnWritePosition(Position) -> bool:
	var Pathfinding = _Pathfinding()
	if Pathfinding == null:
		return true
	var newTile := Pathfinding.GetTileByPosition(RParam.AsVector2(Position)) as TPathfindingTile
	if newTile != null and newTile != FCurrentTile:
		if FCurrentTile != null:
			FCurrentTile.UnblockTile(Owner)
		FCurrentTile = newTile
	return true
