class_name TMap
extends TObject
## Port of TMap (BaseConflict.Map.pas:197, implementation :240): a map's gameplay data. CreateFromFile reads
## the JSON that tools/convert_maps.py makes from the original .bcm (team and player count, boundaries, the
## named zones); the scenario scripts then add the build zones and pick the lanes. The client map (terrain,
## vegetation, water) is TClientMap and comes with the client.
## CreateFromFile builds the Pathfinding grid over the boundaries from the walk zone. SaveToFile serves the map
## editor only.

const C = preload("res://src/runtime/dws/dws_const.gd")
const L = preload("res://src/runtime/dws/dws_lib.gd")
const MAP_DIRECTORY = "res://src/content/maps/"
const PATHFINDING_TILE_SIZE = 0.8  # BaseConflict.Constants.pas:53

var FFilepath := ""
var FPlayerCount := 0
var FBuildZones: TBuildZoneManager
var FLanes: TLaneManager

var TeamCount := 0
var MapBoundaries := Rect2()  # RRectFloat Left/Top/Right/Bottom as position/end
var Zones := {}  # String -> TMultipolygon
var Pathfinding: TPathfinding = null

var BuildZones: TBuildZoneManager:
	get:
		return FBuildZones
var Lanes: TLaneManager:
	get:
		return FLanes
var Filepath: String:
	get:
		return FFilepath
var PlayerCount: int:
	get:
		return FPlayerCount
	set(Value):
		FPlayerCount = Value


func Create() -> TMap:
	MapBoundaries = Rect2(Vector2(-100, -100), Vector2(200, 200))
	FBuildZones = TBuildZoneManager.new()
	FLanes = TLaneManager.new().Create()
	return self


func CreateEmpty() -> TMap:
	return Create()


## The map file of a scenario's MapName (the original: Maps\<MapName>\<MapName>.bcm).
static func MapFile(MapName: String) -> String:
	return MAP_DIRECTORY + MapName + ".json"


func CreateFromFile(Filename: String) -> TMap:
	Create()
	var Data = JSON.parse_string(FileAccess.get_file_as_string(Filename))
	if not Data is Dictionary:
		push_error("TMap.CreateFromFile: cannot read %s" % Filename)
		return self
	TeamCount = int(Data["TeamCount"])
	PlayerCount = int(Data["PlayerCount"])
	var Bounds: Dictionary = Data["MapBoundaries"]
	MapBoundaries = Rect2(Vector2(Bounds["Left"], Bounds["Top"]),
		Vector2(Bounds["Right"] - Bounds["Left"], Bounds["Bottom"] - Bounds["Top"]))
	for ZoneName: String in Data["Zones"]:
		Zones[ZoneName] = TMultipolygon.CreateFromData(Data["Zones"][ZoneName])
	assert(Zones.has(C.ZONE_WALK))
	Pathfinding = TPathfinding.new().Create(PATHFINDING_TILE_SIZE, 4, MapBoundaries, Zones[C.ZONE_WALK], self)
	FFilepath = Filename
	return self


func TeamSize() -> int:
	if TeamCount > 0:
		return L.Div(FPlayerCount, TeamCount)
	return 0


func ClampToZone(Zone: String, Position: Vector2) -> Vector2:
	if Zones.has(Zone):
		return Zones[Zone].EnsurePointInMultiPoly(Position)
	return Position


func Idle() -> void:
	pass


func Destroy() -> void:
	if Pathfinding != null:
		Pathfinding.Free()
	FBuildZones.Free()
	Zones.clear()
	super()
