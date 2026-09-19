extends SceneTree
## Shader compile check (tools/run_tests.ps1 runs it with a window: headless Godot does not compile shaders). Builds
## every mesh shader variant the port can make (TMesh._shader_for: flag combinations x cull modes x skinning x the
## ported effect shaders alone and in the combinations the scripts create); the renderer parses each at once and a
## failed one has no parameters. "SHADER ERROR" lines go to the log (the runner counts them). Exit code 1 on failure.
## Nothing is drawn (drawing hundreds of variants stalls the first frame for minutes); it quits right away.

const EFFECTS := ["MatcapShader.fx", "MetalShader.fx", "ColorOverlay.fx", "SpawnShader_White.fx",
	"SpawnShader_Colorless.fx", "SpawnShader_Green.fx", "SpawnShader_Black.fx", "SpawnShader_Black_Legendary.fx",
	"SpawnShader_Blue.fx", "DeathShader.fx", "DeathShader_Black.fx", "GlowOvershoot.fx", "HideAndGlow.fx",
	"SoulGain.fx"]
## Effects on one mesh at once, in order value order (spawn 1, tint 5000, matcap 9993, hide and glow 9997, glow 9998,
## metal 10000).
const COMBINATIONS := [["SpawnShader_White.fx", "MatcapShader.fx"], ["SpawnShader_Green.fx", "ColorOverlay.fx", "MetalShader.fx"],
	["SpawnShader_Black.fx", "MatcapShader.fx", "MetalShader.fx"], ["ColorOverlay.fx", "MatcapShader.fx"],
	["ColorOverlay.fx", "HideAndGlow.fx", "GlowOvershoot.fx", "MetalShader.fx"]]


func _initialize() -> void:
	var failed := []
	var count := 0
	var lists: Array = [[]]
	for effect in EFFECTS:
		lists.append([effect])
	lists.append_array(COMBINATIONS)
	var flag_sets := []
	for alpha in [false, true]:
		for diffuse in [false, true]:
			for material in [false, true]:
				for texture in [false, true]:
					var flags := PackedStringArray()
					if alpha:
						flags.append("ROL_ALPHA")
					else:
						flags.append_array(["GBUFFER", "DRAW_COLOR", "DRAW_NORMAL", "DRAW_MATERIAL"])
					if diffuse:
						flags.append("DIFFUSETEXTURE")
					if material:
						flags.append("MATERIAL")
					if texture:
						flags.append("MATERIALTEXTURE")
					flag_sets.append(flags)
	# the glow stage (TMesh._glow_flags): the glow pass and own passes, with and without a glow texture
	for own in [false, true]:
		for glow in [false, true]:
			flag_sets.append(TMesh._glow_flags(glow, own))
	# own passes of the effects stage (TMesh._effects_flags)
	flag_sets.append(TMesh._effects_flags(PackedStringArray(["GBUFFER", "DIFFUSETEXTURE", "MATERIAL", "MATERIALTEXTURE"])))
	flag_sets.append(TMesh._effects_flags(PackedStringArray(["ROL_ALPHA"])))
	for list: Array in lists:
		for flags: PackedStringArray in flag_sets:
			for cull in ["cmCCW", "cmNone"]:
				# skinning only touches the vertex stage: with the full flag sets
				for skinning in ([false, true] if flags.has("DIFFUSETEXTURE") and (flags.has("MATERIALTEXTURE")
						or flags.has("ROL_GLOW_STAGE")) else [false]):
					var own_pass := flags.has("ROL_ALPHA") and (flags.has("ROL_GLOW_STAGE") or flags.has("ROL_EFFECTS_STAGE"))
					for blend in ([TMesh.BLEND_LINEAR, TMesh.BLEND_ADDITIVE] if own_pass else [TMesh.BLEND_LINEAR]):
						var shader := TMesh._shader_for(cull, flags, skinning, list, blend)
						count += 1
						if RenderingServer.get_shader_parameter_list(shader.get_rid()).is_empty():
							failed.append("%s %s %s %s %d" % [list, flags, cull, skinning, blend])
	# the post effects' passes (TPostEffectManager)
	for file in DirAccess.get_files_at(TPostEffectManager.SHADER_ROOT):
		if file.ends_with(".gdshader"):
			var shader: Shader = load(TPostEffectManager.SHADER_ROOT + file)
			count += 1
			if RenderingServer.get_shader_parameter_list(shader.get_rid()).is_empty():
				failed.append(file)
	print("check_shaders: %d variants, %d failed" % [count, failed.size()])
	for f in failed.slice(0, 20):
		print("  failed: ", f)
	quit(1 if not failed.is_empty() else 0)
