class_name T2DGrid
extends RefCounted
## Port of T2DGrid<T> (Engine\Engine.Helferlein.DataStructures.pas:428, implementation :833): a Width x Height
## grid. Nodes are read and written safely: out of range, Get returns the default value and Set does nothing.
## Setting Size resets every node to the default value.

var FDefaultValue = null
var FGrid: Array = []  # FGrid[x][y]

var Width: int:
	get:
		return FGrid.size()
var Height: int:
	get:
		return FGrid[0].size() if Width > 0 else 0
var Size: Vector2i:
	get:
		return Vector2i(Width, Height)
	set(WidthHeight):
		FGrid.resize(maxi(WidthHeight.x, 0))
		for i in WidthHeight.x:
			var Column: Array = []
			Column.resize(maxi(WidthHeight.y, 0))
			Column.fill(FDefaultValue)
			FGrid[i] = Column


## Create(DefaultValue): an empty grid whose missing nodes read as DefaultValue.
func _init(DefaultValue = null) -> void:
	FDefaultValue = DefaultValue


func GetNode(xy: Vector2i):
	if xy.x >= 0 and xy.x < Width and xy.y >= 0 and xy.y < Height:
		return FGrid[xy.x][xy.y]
	return FDefaultValue


func SetNode(xy: Vector2i, Node) -> void:
	if xy.x >= 0 and xy.x < Width and xy.y >= 0 and xy.y < Height:
		FGrid[xy.x][xy.y] = Node


## Calls func(x, y, Item) for each item in this grid (x outer, y inner). Returns itself for chains.
func Each(function: Callable) -> T2DGrid:
	for x in Width:
		for y in Height:
			function.call(x, y, GetNode(Vector2i(x, y)))
	return self


## Calls func(x, y, Item) for each item in this grid and replaces the value with the result.
func Update(function: Callable) -> T2DGrid:
	for x in Width:
		for y in Height:
			SetNode(Vector2i(x, y), function.call(x, y, GetNode(Vector2i(x, y))))
	return self
