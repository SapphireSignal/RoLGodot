class_name TWaterManager
extends Node3D
## Engine.Water.pas TWaterManager: the map's water surfaces, loaded from the importer's <map>.water.json (the
## converted <Map>.wat).


## TWaterManager.CreateFromFile; an empty manager when the file is missing (TClientMap: TWaterManager.Create).
static func CreateFromFile(json_path: String) -> TWaterManager:
	var manager := TWaterManager.new()
	manager.name = "Water"
	if FileAccess.file_exists(json_path):
		var surfaces: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if surfaces is Array:
			for data: Dictionary in surfaces:
				manager.AddSurface(TWaterSurface.CreateFromData(data))
	return manager


func AddSurface(surface: TWaterSurface) -> void:
	add_child(surface)


func SurfaceCount() -> int:
	return get_child_count()


func Surfaces(index: int) -> TWaterSurface:
	return get_child(index) as TWaterSurface
