class_name TPolygon
extends RefCounted
## Port of TPolygon (Engine\Engine.Math.Collision2D.pas:334, implementation :1402): a polyline, a polygon when
## Closed. Only the members the game uses are ported (the rest serve the map editor).

var Nodes: Array[Vector2] = []
var Closed := false


static func Create(Nodes_: Array = [], Closed_: bool = false) -> TPolygon:
	var Result := TPolygon.new()
	for Node in Nodes_:
		Result.AddNode(Node)
	Result.Closed = Closed_
	return Result


func AddNode(Node: Vector2) -> void:
	Nodes.append(Node)


func EdgeCount() -> int:
	return Nodes.size() if Closed else Nodes.size() - 1


func Edge(index: int) -> RLine2D:
	assert((Closed and index <= Nodes.size() - 1) or index <= Nodes.size() - 2)
	return RLine2D.CreateFromPoints(Nodes[index], Nodes[(index + 1) % Nodes.size()])


## Returns whether a point lies within the polygon (even-odd rule); an open polyline contains nothing.
func IsPointInPolygon(Point: Vector2) -> bool:
	if not Closed:
		return false
	var Result := false
	for i in Nodes.size():
		var Startpoint := Nodes[i]
		var Endpoint := Nodes[(i + 1) % Nodes.size()]
		if ((Startpoint.y > Point.y) != (Endpoint.y > Point.y)) and \
				(Point.x < (Endpoint.x - Startpoint.x) * (Point.y - Startpoint.y) / (Endpoint.y - Startpoint.y) + Startpoint.x):
			Result = not Result
	return Result


## Returns the closest point on the border of the poly to a point (EMPTY = NaN x without edges).
func NearestPointAtBorder(Point: Vector2) -> Vector2:
	var Result := Vector2(NAN, 0)
	for i in EdgeCount():
		var nearest := Edge(i).NearestPointOnLine(Point)
		if is_nan(Result.x) or Point.distance_to(nearest) < Point.distance_to(Result):
			Result = nearest
	return Result


## Clamp a point to the polygon. If it's outside it will be clamped to the nearest border.
func EnsurePointInPoly(Point: Vector2) -> Vector2:
	if IsPointInPolygon(Point):
		return Point
	return NearestPointAtBorder(Point)
