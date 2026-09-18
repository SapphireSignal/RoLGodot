class_name TClientMap
extends Node3D
## BaseConflict.Map.Client.pas TClientMap: what the client draws of a map: its lights (TLightManager), terrain,
## water and vegetation, loaded from the importer's output of Maps/<Name>/ (tools/import_map_graphics.py).
## Missing files give the original's fallbacks (an empty terrain is not built: nothing to draw).
## Not yet: the decorations (<Map>.bcc SavedDecorations and the scenarios' AddDecoEntity) are client entities
## created from scripts; they come with the client entity visuals (phase 5). Read docs/assets.md ("Maps").

const GRAPHICS_ROOT := "res://assets/graphics/"

var LightManager: TLightManager
var Terrain: TTerrain
var Water: TWaterManager
var Vegetation: TVegetationManager
var MapName := ""


## A game-root relative file name as the original's data writes it ("Graphics\\Environment\\Grass\\Grass.tga",
## "\\Maps\\Classic\\Caustics.tga") -> the importer's lowercased copy under res://assets/graphics/.
static func ResolveGamePath(game_path: String) -> String:
	var parts := Array(game_path.replace("\\", "/").split("/", false))
	if not parts.is_empty() and String(parts[0]).to_lower() == "graphics":
		parts.pop_front()
	return GRAPHICS_ROOT + "/".join(parts).to_lower()


## TClientMap.CreateFromFile for the map Maps/<map_name>/<map_name>.
static func CreateFromFile(map_name: String) -> TClientMap:
	var map := TClientMap.new()
	map.name = "ClientMap"
	map.MapName = map_name
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
	return map


## TClientMap.Idle: the lights reach the renderer (TLightManager.Idle when dirty).
func _ready() -> void:
	LightManager.SynchronizeLightWithGFXD()


## DrawTerrain / DrawWater / DrawVegetation.
func SetDrawTerrain(value: bool) -> void:
	if Terrain:
		Terrain.visible = value


func SetDrawWater(value: bool) -> void:
	Water.visible = value


func SetDrawVegetation(value: bool) -> void:
	Vegetation.visible = value
