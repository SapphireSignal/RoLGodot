extends "res://tests/test_case.gd"
## The build grid (TBuildGridManagerComponent) and its timing helpers: RCubicBezier.Solve, TGUITransitionValueSingle,
## a zone's tiles and their spawn rotation. Expected curve values come from the original's algorithm (Engine.Math.pas
## RCubicBezier.Solve) run in Python. The drawn grid is checked by the map viewer smoke test (tile count) and captures.

var _free: Array = []


func after_each() -> void:
	for obj in _free:
		obj.Destroy()
	_free.clear()
	# the tiles load up to 4 geometries into TMesh's cache (not a leak; dropped so the leak count stays readable)
	TMesh.ClearGeometryCache()
	TTimeManager.SetFakeTime(null)
	super()


func _has_assets() -> bool:
	if TMesh.Exists("Gameplay\\Buildgrid\\Buildgrid1.xml"):
		return true
	print("  (assets/graphics missing: run python tools/import_graphics.py)")
	return false


## LINEAR is the identity; EASEOUT (0, 0, 0.58, 1) at 0.25 / 0.5; the tiles' fade-out curve (0, -2.38, 0.58, 1) dips
## below zero first (the tile flashes brighter before it goes dark); inputs are clamped.
func test_cubic_bezier() -> String:
	check_near(RCubicBezier.LINEAR().Solve(0.3), 0.3, 1e-6, "linear")
	check_near(RCubicBezier.EASEOUT().Solve(0.25), 0.378138130826099, 1e-5, "ease out 0.25")
	check_near(RCubicBezier.EASEOUT().Solve(0.5), 0.6846431874941069, 1e-5, "ease out 0.5")
	var dip := RCubicBezier.Create(0, -2.38, 0.58, 1)
	check_near(dip.Solve(0.2), -0.7405247305561322, 1e-4, "dip 0.2")
	check_near(dip.Solve(0.5), 0.05885368013682368, 1e-4, "dip 0.5")
	check_near(dip.Solve(1.5), 1.0, 1e-6, "clamped")
	return take_failure()


## The first SetValue jumps; a new target eases from the current value over Duration; setting the same target again
## does not restart it.
func test_transition_value() -> String:
	TTimeManager.SetFakeTime(1000.0)
	var value := TGUITransitionValueSingle.new()
	value.SetValue(0.032)
	check_near(value.CurrentValue(), 0.032, 1e-9, "first value jumps")
	value.Duration = 1000
	value.SetValue(0.0)
	check_near(value.CurrentValue(), 0.032, 1e-9, "starts where it was")
	TTimeManager.SetFakeTime(1500.0)
	check_near(value.CurrentValue(), 0.016, 1e-6, "linear half way")
	value.SetValue(0.0)
	check_near(value.CurrentValue(), 0.016, 1e-6, "same target: no restart")
	TTimeManager.SetFakeTime(2500.0)
	check_near(value.CurrentValue(), 0.0, 1e-9, "arrived")
	return take_failure()


## A 3 x 2 zone with one banned field: 5 tiles at the field centers just under the ground, glowing 0.032. A spawn on a
## field fades that tile (flashing brighter first); spawning on it again does not count; after the 5th field the zone
## resets and every tile glows in again.
func test_spawn_rotation() -> String:
	if not _has_assets():
		return ""
	TTimeManager.SetFakeTime(1000.0)
	var zone := TBuildZone.new().Create(7).SetSize(3, 2).SetPosition(10, 20).SetFront(1, 0).Block(1, 1)
	var visualizer := TBuildGridManagerComponent.TBuildGridVisualizer.new(zone)
	_free.append(visualizer)
	_free.append(zone)
	check_eq(visualizer.FTiles.size(), 5, "tiles on the free fields")
	var tile: TBuildGridManagerComponent.TTile = visualizer.FTiles[0]
	var center := zone.GetCenterOfField(tile.Coordinate)
	check(tile.TileMesh.Position.is_equal_approx(Vector3(center.x, -0.04, center.y)), "at the field center")
	check_near(tile.TileMesh.GetScale(), 2 / 1.84 + 0.08, 1e-6, "GRIDNODE_SCALE")
	check_near(tile.FGlowTransition.CurrentValue(), 0.032, 1e-9, "glowing")
	visualizer.Spawn(tile.Coordinate)
	check(not tile.IsActive and visualizer.CurrentRotationCount == 4, "used")
	TTimeManager.SetFakeTime(1200.0)
	check(tile.FGlowTransition.CurrentValue() > 0.05, "flashes first")
	TTimeManager.SetFakeTime(2000.0)
	check_near(tile.FGlowTransition.CurrentValue(), 0.0, 1e-9, "dark after 1 s")
	visualizer.Spawn(tile.Coordinate)
	check_eq(visualizer.CurrentRotationCount, 4, "a used field does not count again")
	for other: TBuildGridManagerComponent.TTile in visualizer.FTiles.slice(1):
		visualizer.Spawn(other.Coordinate)
	check_eq(visualizer.CurrentRotationCount, 5, "all used: the rotation resets")
	check(tile.IsActive, "active again")
	TTimeManager.SetFakeTime(2500.0)
	check_near(tile.FGlowTransition.CurrentValue(), 0.032, 1e-6, "glows in over 0.5 s")
	return take_failure()
