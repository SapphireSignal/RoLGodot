class_name TBuildZone
extends TObject
## Port of TBuildZone (BaseConflict.Map.pas:39, implementation :308): one build grid a team places its units on.
## Fields hold FIELD_FREE, a banned mark (FIELD_BANNED and lower) or the ID of the entity blocking them. The
## scenario scripts set the zones up (`TBuildZone.new().Create(ID).SetTeam(..).SetPosition(..)...`).
## Coordinates are Vector2i (RIntVector2); out-of-range fields read as FIELD_FREE and ignore writes (T2DGrid).
## The client-only debug rendering (RenderDebug, RenderEntityGrid, RenderOccupation) comes with the client.

const L = preload("res://src/runtime/dws/dws_lib.gd")

const GRIDNODESIZE = 2
const FIELD_BANNED = -2  # and lower means banned
const FIELD_FREE = -1

# the owner of that buildzone (Slot ID), owning team, ID in map
var TeamID := 0
var ID := 0
# the index when this grid will spawn in rotation
var SpawnRotationIndex := 0
# position of center and front of orientation
var Center := Vector2.ZERO
var SpawnTarget := Vector2.ZERO
var SpawnDirection := Vector2.ZERO

# direction the grid is pointing to
var FFront := Vector2.ZERO
# gridsize
var FSize := Vector2i.ZERO
# saves whether a gridfield is blocked or not
var FGrid: T2DGrid

## size of grid in fields; setting it frees every field
var Size: Vector2i:
	get:
		return FSize
	set(Value):
		FSize = Value
		FGrid.Size = FSize
var Front: Vector2:
	get:
		return FFront
	set(Value):
		FFront = Value.normalized()
var Left: Vector2:
	get:
		return Vector2(-Front.y, Front.x)
## RMatrix2x2.CreateBase(Left, Front): columns Left and Front, so CoordBase * v = Left * v.x + Front * v.y.
var CoordBase: Transform2D:
	get:
		return Transform2D(Left, Front, Vector2.ZERO)
var SpawnTargetBase: Transform2D:
	get:
		var Direction := SpawnDirection.normalized()
		return Transform2D(Direction, Vector2(-SpawnDirection.y, SpawnDirection.x).normalized(), Vector2.ZERO)


func Create(ID_: int = 0) -> TBuildZone:
	ID = ID_
	FGrid = T2DGrid.new(FIELD_FREE)
	Size = Vector2i(2, 2)
	Front = Vector2(0, 1)
	return self


## GetCenterOfField(Coord: Vector2i) or GetCenterOfField(CoordX, CoordY).
func GetCenterOfField(CoordX, CoordY = null) -> Vector2:
	var Coord: Vector2i = CoordX if CoordY == null else Vector2i(CoordX, CoordY)
	return Center + (GRIDNODESIZE * Front * (Coord.y - Size.y / 2.0 + 0.5)) \
		+ (GRIDNODESIZE * Left * (Coord.x - Size.x / 2.0 + 0.5))


## InRange(WorldCoord: Vector2) or InRange(Coord: Vector2i): inside the grid and not banned.
func InRange(Coord) -> bool:
	if Coord is Vector2:
		return InRange(PositionToCoord(Coord))
	return Coord.x >= 0 and Coord.y >= 0 and Coord.x < Size.x and Coord.y < Size.y and not IsBanned(Coord)


## Round is Delphi's banker's rounding.
func PositionToCoord(Position: Vector2) -> Vector2i:
	var Offset := Position - Center
	return Vector2i(L.Round(Left.dot(Offset) / GRIDNODESIZE + Size.x / 2.0 - 0.5),
		L.Round(Front.dot(Offset) / GRIDNODESIZE + Size.y / 2.0 - 0.5))


func IsFree(Coord: Vector2i) -> bool:
	return FGrid.GetNode(Coord) == FIELD_FREE


## IsBanned(Coord: Vector2i) or IsBanned(CoordX, CoordY).
func IsBanned(CoordX, CoordY = null) -> bool:
	var Coord: Vector2i = CoordX if CoordY == null else Vector2i(CoordX, CoordY)
	return FGrid.GetNode(Coord) <= FIELD_BANNED


func GetFieldID(Coord: Vector2i) -> int:
	return FGrid.GetNode(Coord)


func SetFieldID(Coord: Vector2i, BlockerID: int) -> void:
	FGrid.SetNode(Coord, BlockerID)


func UpdateEntityID(oldID: int, newID: int) -> void:
	FGrid.Update(func(_x, _y, old): return newID if old == oldID else old)


## Blocks the field, so no player can build on it.
func Block(CoordX: int, CoordY: int) -> TBuildZone:
	SetFieldID(Vector2i(CoordX, CoordY), FIELD_BANNED)
	return self


func SetTeam(TeamID_: int) -> TBuildZone:
	TeamID = TeamID_
	return self


func SetPosition(PosX: float, PosY: float) -> TBuildZone:
	Center = Vector2(PosX, PosY)
	return self


func SetSize(SizeX: int, SizeY: int) -> TBuildZone:
	Size = Vector2i(SizeX, SizeY)
	return self


func SetFront(FrontX: float, FrontY: float) -> TBuildZone:
	Front = Vector2(FrontX, FrontY)
	return self


func SetSpawnTarget(PosX: float, PosY: float, NormalX: float, NormalY: float) -> TBuildZone:
	SpawnTarget = Vector2(PosX, PosY)
	SpawnDirection = Vector2(NormalX, NormalY).normalized()
	return self
