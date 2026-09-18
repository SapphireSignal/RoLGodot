class_name TPathfindingTileNeighbour
extends TObject
## Port of TPathfindingTileNeighbour (BaseConflict.Classes.Pathfinding.pas:35, implementation :696): the step to
## one neighbour tile and its cost, the distance between the tile centers.
## The original constructor also computes the lane orientation at the tile and the step's orientation, then
## never uses them (a commented-out cost tweak); the port skips those side-effect-free lookups.

var FCost := 0.0
var FNeighbour: TPathfindingTile

var NeighbourTile: TPathfindingTile:
	get:
		return FNeighbour
var Cost: float:
	get:
		return FCost


func Create(FromTile: TPathfindingTile = null, ToTile: TPathfindingTile = null) -> TPathfindingTileNeighbour:
	FNeighbour = ToTile
	FCost = RParam.ToSingle((ToTile.Center - FromTile.Center).length())
	return self
