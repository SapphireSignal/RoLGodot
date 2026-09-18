class_name TClientMap
extends Node3D
## BaseConflict.Map.Client.pas TClientMap: what the client draws of a map: its lights (TLightManager), terrain,
## water and vegetation, loaded from the importer's output of Maps/<Name>/ (tools/import_map_graphics.py), and the
## decorations: client entities built from scripts (bridges, stones, ambient sound emitters), the map's own from
## <Map>.bcc SavedDecorations and the ones the scenario scripts add (AddDecoEntity). Missing files give the
## original's fallbacks (an empty terrain is not built: nothing to draw). Read docs/assets.md ("Maps").

const C = preload("res://src/runtime/dws/dws_const.gd")
const GRAPHICS_ROOT := "res://assets/graphics/"

var LightManager: TLightManager
var Terrain: TTerrain
var Water: TWaterManager
var Vegetation: TVegetationManager
var MapName := ""
## The client's global bus the decoration entities are created on (the original's GlobalEventbus global); without
## one (tools, tests of the ground alone) the decorations are not loaded.
var FGlobalEventbus: TEventbus = null
## RDecoEntityDescription as {Position, Front, Size, ScriptFilename}, and the entities made from them.
var Decorations: Array = []
var DecorationEntities: Array = []


## A game-root relative file name as the original's data writes it ("Graphics\\Environment\\Grass\\Grass.tga",
## "\\Maps\\Classic\\Caustics.tga") -> the importer's lowercased copy under res://assets/graphics/.
static func ResolveGamePath(game_path: String) -> String:
	var parts := Array(game_path.replace("\\", "/").split("/", false))
	if not parts.is_empty() and String(parts[0]).to_lower() == "graphics":
		parts.pop_front()
	return GRAPHICS_ROOT + "/".join(parts).to_lower()


## TClientMap.CreateFromFile for the map Maps/<map_name>/<map_name>; with a client global bus it loads the
## decorations too ("doodads", last, as the original does).
static func CreateFromFile(map_name: String, GlobalEventbus: TEventbus = null) -> TClientMap:
	var map := TClientMap.new()
	map.name = "ClientMap"
	map.MapName = map_name
	map.FGlobalEventbus = GlobalEventbus
	var base := GRAPHICS_ROOT + "maps/%s/%s" % [map_name.to_lower(), map_name.to_lower()]
	map.LightManager = TLightManager.CreateFromMap(map_name)
	if FileAccess.file_exists(base + ".terrain.json"):
		map.Terrain = TTerrain.CreateFromFile(base)
		if map.Terrain:
			map.add_child(map.Terrain)
	map.Water = TWaterManager.CreateFromFile(base + ".water.json")
	map.add_child(map.Water)
	map.Vegetation = TVegetationManager.CreateFromFile(base + ".vegetation.json")
	map.add_child(map.Vegetation)
	if GlobalEventbus != null and FileAccess.file_exists(base + ".decorations.json"):
		map.LoadDecorationDescriptions(JSON.parse_string(FileAccess.get_file_as_string(base + ".decorations.json")))
	return map


## TClientMap.Idle: the lights reach the renderer (TLightManager.Idle when dirty).
func _ready() -> void:
	LightManager.SynchronizeLightWithGFXD()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		FreeDecorations()


## Port: frees the decoration entities (the original's FDecoEntities owns them).
func FreeDecorations() -> void:
	for Entity: TEntity in DecorationEntities:
		Entity.Free()
	DecorationEntities.clear()
	Decorations.clear()


## DrawTerrain / DrawWater / DrawVegetation.
func SetDrawTerrain(value: bool) -> void:
	if Terrain:
		Terrain.visible = value


func SetDrawWater(value: bool) -> void:
	Water.visible = value


func SetDrawVegetation(value: bool) -> void:
	Vegetation.visible = value


func LoadDecorationDescriptions(Value: Array) -> void:
	Decorations.clear()
	for Desc: Dictionary in Value:
		AddDecoEntityDesc({"Position": _vec3(Desc.Position), "Front": _vec3(Desc.Front), "Size": float(Desc.Size),
			"ScriptFilename": String(Desc.ScriptFilename)})


static func _vec3(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])


## [ScriptIncludeMember] AddDecoEntity(PositionX, PositionY, PositionZ, FrontX, FrontY, FrontZ, Size, ScriptFilename),
## the scenario scripts' call (Game.ClientMap.AddDecoEntity).
func AddDecoEntity(PositionX, PositionY, PositionZ, FrontX, FrontY, FrontZ, Size, ScriptFilename) -> TClientMap:
	AddDecoEntityDesc({"Position": Vector3(PositionX, PositionY, PositionZ), "Front": Vector3(FrontX, FrontY, FrontZ),
		"Size": RParam.ToSingle(Size), "ScriptFilename": ScriptFilename})
	return self


## AddDecoEntity(EntityDesc): the entity from the script, placed, then eiAfterCreate.
func AddDecoEntityDesc(EntityDesc: Dictionary) -> void:
	Decorations.append(EntityDesc)
	var newEntity := TEntity.CreateFromScript(EntityDesc.ScriptFilename, FGlobalEventbus)
	if newEntity == null:
		Decorations.pop_back()
		return
	DecorationEntities.append(newEntity)
	UpdateDecoEntity(DecorationEntities.size() - 1, EntityDesc)
	newEntity.Eventbus.Trigger(C.eiAfterCreate, [])


func UpdateDecoEntity(index: int, EntityDesc: Dictionary) -> void:
	Decorations[index] = EntityDesc
	var Entity: TEntity = DecorationEntities[index]
	var p: Vector3 = EntityDesc.Position
	Entity.Position = Vector2(p.x, p.z)
	Entity.DisplayPosition = p
	Entity.DisplayFront = EntityDesc.Front
	Entity.DisplayUp = Vector3(0, 1, 0)
	Entity.Eventbus.Write(C.eiSize, [Vector3.ONE * float(EntityDesc.Size)])
