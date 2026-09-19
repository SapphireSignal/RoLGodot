class_name TBuildGridManagerComponent
extends TGDEntityComponent
## Port of TBuildGridManagerComponent (BaseConflict.EntityComponents.Client.pas:504, implementation :2950), on the
## client game's entity (TClientGame.BuildgridManager, made after Initialize: the scenario scripts set the build zones
## there): the build grid behind each nexus. Per free (not banned) field of every build zone a tile mesh (one of
## Gameplay\Buildgrid\Buildgrid1..4, random, turned by a random multiple of 90 degrees, just under the ground) with
## GlowOvershoot.fx, whose overshoot is the tile's glow transition. A wave spawn on a field (eiWaveSpawn: zone ID,
## coordinate) fades that tile's glow out (1 s, a curve that dips first); once every tile of the zone has spawned the
## zone resets and all glow in again (0.5 s ease out): the spawn rotation. Card placement colors the tiles
## (ShowOccupation / ShowInvalid / ResetColors, called by the client input when it is ported). Not yet: the
## activation particle effect (buildgrid_activate.pfx, particles are not ported).

const BUILDGRID_MESH_PATH := "Gameplay\\Buildgrid\\Buildgrid%d.xml"
const BUILDGRID_MESH_PATH_COUNT := 4
const PATH_GRAPHICS_SHADER := "Graphics\\Effects\\Shader\\"


## TTile: one field's mesh and its glow.
class TTile:
	const GLOW_TIME_IN := 500
	const GLOW_TIME_OUT := 1000
	const GLOW_INTENSITY := 0.032
	const GLOW_COLOR_INTENSITY := 0.4
	const GRIDNODE_SCALE := (TBuildZone.GRIDNODESIZE / 1.84) + 0.08

	var BuildZone: TBuildZone
	var Coordinate: Vector2i
	var TileMesh: TMesh = null  # Mesh in the original: a Godot class name
	var IsActive := true
	var FGlowTransition := TGUITransitionValueSingle.new()

	func _init(BuildZone_: TBuildZone, Coordinate_: Vector2i) -> void:
		IsActive = true
		BuildZone = BuildZone_
		Coordinate = Coordinate_
		TileMesh = TMesh.CreateFromFile(BUILDGRID_MESH_PATH % (randi_range(0, BUILDGRID_MESH_PATH_COUNT - 1) + 1))
		if TileMesh != null:
			var Center := BuildZone.GetCenterOfField(Coordinate)
			TileMesh.Position = Vector3(Center.x, -0.04, Center.y)
			TileMesh.ScaleVector = Vector3.ONE * GRIDNODE_SCALE
			TileMesh.SetRotation(Vector3(0, PI / 2 * randi_range(0, 3), 0))
			TileMesh.CustomShader.append(TMesh.RMeshShader.new(PATH_GRAPHICS_SHADER + "GlowOvershoot.fx", SetUpShader))
			TileMesh.ApplyMaterial()
			GFXD.AddToScene(TileMesh)
		FGlowTransition.TimingFunction = RCubicBezier.EASEOUT()
		FGlowTransition.SetValue(GLOW_INTENSITY)

	func Activate() -> void:
		IsActive = false
		FGlowTransition.SetValue(0.0)
		FGlowTransition.TimingFunction = RCubicBezier.Create(0, -2.38, 0.58, 1)
		FGlowTransition.Duration = GLOW_TIME_OUT

	func Reset() -> void:
		IsActive = true
		FGlowTransition.SetValue(GLOW_INTENSITY)
		FGlowTransition.TimingFunction = RCubicBezier.EASEOUT()
		FGlowTransition.Duration = GLOW_TIME_IN

	func SetUpShader(CurrentShader, Stage: int, _PassIndex: int) -> void:
		var ColorIntensity := FGlowTransition.CurrentValue()
		if Stage == TMesh.RS_GLOW:
			CurrentShader.SetShaderConstant("go_is_glow_stage", 1.0)
		else:
			CurrentShader.SetShaderConstant("go_is_glow_stage", 0.0)
			if not TOptionManager.GetBooleanOption(C.coGraphicsPostEffectGlow):
				ColorIntensity = ColorIntensity / GLOW_INTENSITY * GLOW_COLOR_INTENSITY
		CurrentShader.SetShaderConstant("go_overshoot", ColorIntensity)
		var GoColor := TMeshEffect.RColor(0x00FFFF)
		CurrentShader.SetShaderConstant("go_color", Vector3(GoColor.r, GoColor.g, GoColor.b))

	func Destroy() -> void:
		if TileMesh != null and is_instance_valid(TileMesh):
			TMesh.Release(TileMesh)
		TileMesh = null


## TBuildGridVisualizer: the tiles of one build zone and its spawn rotation.
class TBuildGridVisualizer:
	var FTiles: Array[TTile] = []
	var FFieldCount := 0
	var CurrentRotationCount := 0

	func _init(BuildZone: TBuildZone) -> void:
		for X in BuildZone.Size.x:
			for Y in BuildZone.Size.y:
				if not BuildZone.IsBanned(X, Y):
					FTiles.append(TTile.new(BuildZone, Vector2i(X, Y)))
					FFieldCount += 1
		CurrentRotationCount = FFieldCount

	func Spawn(Coordinate: Vector2i) -> void:
		for Tile: TTile in FTiles:
			if Tile.Coordinate == Coordinate:
				# FActivateEffect (buildgrid_activate.pfx) at the tile: particles are not ported yet
				if Tile.IsActive:
					Tile.Activate()
					CurrentRotationCount -= 1
		if CurrentRotationCount <= 0:
			Reset()

	func Reset() -> void:
		CurrentRotationCount = FFieldCount
		for Tile: TTile in FTiles:
			Tile.Reset()

	func ShowOccupation(_ReferencePosition: Vector2, TeamID: int) -> void:
		for Tile: TTile in FTiles:
			var Active := 0.0 if Tile.IsActive else 1.0
			if Tile.BuildZone.IsFree(Tile.Coordinate) and TeamID == Tile.BuildZone.TeamID:
				_color(Tile, Vector3(-0.17, 0.12 * Active, 0.04))
			else:
				_color(Tile, Vector3(-0.5, 0.12 * Active, 0.04))

	func ShowInvalid() -> void:
		for Tile: TTile in FTiles:
			if Tile.TileMesh != null:
				Tile.TileMesh.AbsoluteHSV.x = 1.0
			_color(Tile, Vector3(0, 0.12 * (0.0 if Tile.IsActive else 1.0), 0.04))

	func ResetColors() -> void:
		for Tile: TTile in FTiles:
			if Tile.TileMesh != null:
				Tile.TileMesh.AbsoluteHSV = Vector3.ZERO
			_color(Tile, Vector3.ZERO)

	static func _color(Tile: TTile, Adjustment: Vector3) -> void:
		if Tile.TileMesh != null:
			Tile.TileMesh.ColorAdjustment = Adjustment
			Tile.TileMesh.ApplyMaterial()

	func Destroy() -> void:
		for Tile: TTile in FTiles:
			Tile.Destroy()
		FTiles.clear()


## BuildZone.ID -> TBuildGridVisualizer
var FBuildGridVisualizers := {}


func _DeclareEvents(e: Array) -> void:
	super(e)
	e.append(XEvent("OnWaveSpawn", C.eiWaveSpawn, C.epLast, C.etTrigger, C.esGlobal))


func Create(Owner = null) -> TEntityComponent:
	super(Owner)
	var Map_: TMap = GlobalEventbus().Game.Map
	if Map_ != null:
		for BuildZone: TBuildZone in Map_.BuildZones.BuildZones.values():
			FBuildGridVisualizers[BuildZone.ID] = TBuildGridVisualizer.new(BuildZone)
	return self


func Destroy() -> void:
	for Visualizer: TBuildGridVisualizer in FBuildGridVisualizers.values():
		Visualizer.Destroy()
	FBuildGridVisualizers.clear()
	super()


## The tile count of all zones (port: tests and the viewer's smoke test).
func TileCount() -> int:
	var Count := 0
	for Visualizer: TBuildGridVisualizer in FBuildGridVisualizers.values():
		Count += Visualizer.FFieldCount
	return Count


func OnWaveSpawn(GridID, Coordinate) -> bool:
	var Visualizer: TBuildGridVisualizer = FBuildGridVisualizers.get(RParam.AsInteger(GridID))
	if Visualizer != null:
		Visualizer.Spawn(RParam.AsIntVector2(Coordinate))
	return true


func ResetColors() -> TBuildGridManagerComponent:
	for Visualizer: TBuildGridVisualizer in FBuildGridVisualizers.values():
		Visualizer.ResetColors()
	return self


func ShowInvalid() -> TBuildGridManagerComponent:
	for Visualizer: TBuildGridVisualizer in FBuildGridVisualizers.values():
		Visualizer.ShowInvalid()
	return self


func ShowOccupation(ReferencePosition: Vector2, TeamID: int) -> TBuildGridManagerComponent:
	for Visualizer: TBuildGridVisualizer in FBuildGridVisualizers.values():
		Visualizer.ShowOccupation(ReferencePosition, TeamID)
	return self
