class_name TPathWaypoint
extends TObject
## Port of TPathWaypoint (BaseConflict.Classes.Pathfinding.pas:93, implementation :687): one tile of a computed
## path, entered at EnterTimestamp (ms) and reserved for StayDuration (ms).

var Tile: TPathfindingTile
var EnterTimestamp := 0
var StayDuration := 0


func Create(EnterTimestamp_: int = 0, StayDuration_: int = 0, Tile_: TPathfindingTile = null) -> TPathWaypoint:
	EnterTimestamp = EnterTimestamp_
	StayDuration = StayDuration_
	Tile = Tile_
	return self
