class_name TLightManager
extends RefCounted
## BaseConflict.Map.Client.pas TLightManager: the map's ambient and directional lights (<Map>.lig, converted into
## the map JSON's "Lights" by tools/convert_maps.py), pushed to the renderer. The renderer side is
## Engine.Core.pas's deferred light pass: at most MAX_DIRECTIONAL_LIGHTS enabled lights, direction negated (to the
## light), Ambient.PremultiplyAlpha.RGB. The port's mesh shader reads them as rol_* global shader parameters.

const MAP_DIRECTORY = "res://src/content/maps/"
const MAX_DIRECTIONAL_LIGHTS = 4

## Ambient: rgb color, w intensity.
var Ambient := Vector4(0.7, 0.7, 0.7, 1.0)
## Each: {Direction: Vector3 (game space, the light's travel direction, normalized), Color: Vector4, Enabled: bool}.
var DirectionalLights: Array[Dictionary] = []


## TLightManager.Create: the default sun and ambient.
func _init() -> void:
	DirectionalLights.append(_light(Vector3(0.2545, -0.76334, -0.5937), Vector4(1, 1, 1, 0.8), true))


static func _light(direction: Vector3, color: Vector4, enabled: bool) -> Dictionary:
	# TDirectionalLight.setDirection normalizes.
	return {"Direction": direction.normalized(), "Color": color, "Enabled": enabled}


## TClientMap loads <Map>.lig next to the map.
static func CreateFromMap(map_name: String) -> TLightManager:
	var manager := TLightManager.new()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_DIRECTORY + map_name + ".json"))
	if data is Dictionary and data.has("Lights"):
		var lights: Dictionary = data.Lights
		var a: Array = lights.Ambient
		manager.Ambient = Vector4(a[0], a[1], a[2], a[3])
		manager.DirectionalLights.clear()
		for item: Dictionary in lights.DirectionalLights:
			var d: Array = item.Direction
			var c: Array = item.Color
			manager.DirectionalLights.append(_light(Vector3(d[0], d[1], d[2]), Vector4(c[0], c[1], c[2], c[3]), item.Enabled))
	return manager


## SynchronizeLightWithGFXD + the light pass's constant upload.
func SynchronizeLightWithGFXD() -> void:
	var parameters := ShaderParameters()
	for key: String in parameters:
		RenderingServer.global_shader_parameter_set(key, parameters[key])


## The global shader parameters the lights become (name -> value).
func ShaderParameters() -> Dictionary:
	var parameters := {"rol_ambient": Vector3(Ambient.x, Ambient.y, Ambient.z) * Ambient.w}
	var count := 0
	# Only the first MAX_DIRECTIONAL_LIGHTS entries are looked at, enabled or not.
	for i in mini(DirectionalLights.size(), MAX_DIRECTIONAL_LIGHTS):
		var light := DirectionalLights[i]
		if not light.Enabled:
			continue
		var color: Vector4 = light.Color
		parameters["rol_light_dir_%d" % count] = TMesh.ToGodot(-(light.Direction as Vector3))
		parameters["rol_light_color_%d" % count] = Color(color.x, color.y, color.z, color.w)
		count += 1
	parameters["rol_light_count"] = count
	return parameters
