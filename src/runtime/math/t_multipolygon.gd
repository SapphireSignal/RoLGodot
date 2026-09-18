class_name TMultipolygon
extends RefCounted
## Port of TMultipolygon (Engine\Engine.Math.Collision2D.pas:391, implementation :1664): an area made of additive
## and subtractive polygons. The maps' zones (walk zone, drop zones, spell zones, camera) are multipolygons.

const COLLISIONEPSILON = 1E-4  # Engine.Math.Collision2D.pas:15


class RMultipolygon:
	extends RefCounted
	var Subtractive := false
	var Polygon: TPolygon

	func _init(Poly: TPolygon, Subtract: bool) -> void:
		Polygon = Poly
		Subtractive = Subtract


var Polygons: Array[RMultipolygon] = []


## Builds one from the map JSON (tools/convert_maps.py): [{Subtractive, Closed, Nodes: [[x, y], ...]}, ...].
static func CreateFromData(Data: Array) -> TMultipolygon:
	var Result := TMultipolygon.new()
	for Item: Dictionary in Data:
		var Nodes: Array = []
		for xy: Array in Item["Nodes"]:
			Nodes.append(Vector2(xy[0], xy[1]))
		Result.AddPolygon(TPolygon.Create(Nodes, Item["Closed"]), Item["Subtractive"])
	return Result


func AddPolygon(Poly: TPolygon, Subtractive: bool) -> void:
	Polygons.append(RMultipolygon.new(Poly, Subtractive))


## Returns whether a point lies within the described area. For overlapping polygons the number of additive and
## subtractive polygons are compared for this point.
func IsPointInMultiPolygon(Point: Vector2) -> bool:
	var counter := 0
	for Item in Polygons:
		if Item.Polygon.IsPointInPolygon(Point):
			if Item.Subtractive:
				counter -= 1
			else:
				counter += 1
	return counter > 0


## Clamp a point to the multipolygon. If it's outside it will be clamped to the nearest border.
func EnsurePointInMultiPoly(Point: Vector2) -> Vector2:
	if IsPointInMultiPolygon(Point):
		return Point
	return NextPointOnBorder(Point)


func NextPointOnBorder(Point: Vector2) -> Vector2:
	var Result := Vector2(NAN, 0)
	for Item in Polygons:
		var temp := Item.Polygon.NearestPointAtBorder(Point)
		if is_nan(Result.x) or Result.distance_to(Point) > temp.distance_to(Point):
			Result = temp
	# prevent rounding error, pushin result slightly into polygon
	return Result + ((Result - Point).normalized() * COLLISIONEPSILON)
