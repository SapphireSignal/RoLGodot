#block defines
#endblock
// Port of the original's mesh shading: Engine/Shader/Standardshader.fx (MegaVertexShader / MegaPixelShader) and, for
// opaque meshes, the deferred light pass Engine/Shader/DeferredDirectionalAmbientLight.fx that lights the G-buffer it
// writes. Read docs/assets.md ("Shading", "Mesh effects").
//
// This is a template, never #included: TShader.LoadShader (t_shader.gd) replaces its block sections (a line holding
// the block keyword anywhere starts one, so comments never name it) with the blocks of the mesh's effect shaders (src/runtime/graphics/effect_shaders/, the ports of the original's
// effect .fx files) the way Engine.GfxApi.pas composes them, and TMesh puts the render mode and the flag defines in
// front (the original's shader bitmask): GBUFFER (+ DRAW_COLOR, DRAW_NORMAL, DRAW_MATERIAL) for opaque meshes, which
// are lit here by the deferred light pass; without it the forward path (HasAlpha, the effects stage). DIFFUSETEXTURE,
// MATERIAL, MATERIALTEXTURE, CULLNONE, ROL_SKINNING, ROL_ALPHA. LIGHTING is always on for meshes (sfAllowLighting).
//
// The original renders in gamma space (no sRGB textures or targets): every value here is a raw 0..1 texture or
// color value, and the result is handed to Godot as srgb_to_linear(result) so Godot's final linear -> sRGB output
// step gives back exactly the original's value. Lighting is computed here (the material is unshaded), from the
// rol_* global shader parameters that TLightManager sets (docs/assets.md, "Lighting").
//
// Space: VERTEX / NORMAL / world_position are Godot space (game x mirrored, see TMesh). The block vs_worldposition
// works on Worldposition in game space, as the original's blocks expect.
#define LIGHTING

global uniform vec3 rol_ambient;          // Ambient.PremultiplyAlpha.RGB
global uniform int rol_light_count;       // enabled directional lights, at most 4 (MAX_DIRECTIONAL_LIGHTS)
global uniform vec3 rol_light_dir_0;      // -Direction (points to the light), normalized, Godot space
global uniform vec3 rol_light_dir_1;
global uniform vec3 rol_light_dir_2;
global uniform vec3 rol_light_dir_3;
global uniform vec4 rol_light_color_0;    // rgb color, a intensity
global uniform vec4 rol_light_color_1;
global uniform vec4 rol_light_color_2;
global uniform vec4 rol_light_color_3;

uniform sampler2D diffuse_texture : filter_linear_mipmap, repeat_enable;
// argb = (Shading Reduction, Specularintensity, Specularpower, Specular Tinting): r intensity, g power, b tint, a SR
uniform sampler2D material_texture : filter_linear_mipmap, repeat_enable;
// Shadertextures.fx VariableTexture1..3 (tsVariable1..3): the effects' textures
uniform sampler2D variable_texture_1 : filter_linear_mipmap, repeat_enable;
uniform sampler2D variable_texture_2 : filter_linear_mipmap, repeat_enable;
uniform sampler2D variable_texture_3 : filter_linear_mipmap, repeat_enable;
uniform float specular_intensity = 0.0;
uniform float specular_power = 128.0;
uniform float specular_tint = 1.0;
uniform float shading_reduction = 0.0;      // ShadingReduction, or ShadingReductionOverride when that is 0
uniform bool use_alpha = false;             // ALPHA flag
uniform float alpha = 1.0;
uniform float alpha_test_ref = 0.0;         // > 0: ALPHATEST, clip(color.a - ref)
uniform vec4 replacement_color = vec4(0.0); // COLOR_REPLACEMENT when a > 0
uniform bool color_adjustment = false;      // COLORADJUSTMENT
uniform bool absolute_color_adjustment = false;
uniform vec3 hsv_offset = vec3(0.0);
uniform vec3 absolute_hsv = vec3(0.0);
#block custom_parameters
#endblock

varying vec3 world_position;
varying vec3 forward_halfway;
varying vec3 smoothed_normal;

vec3 rol_light_dir(int i) {
	return i == 0 ? rol_light_dir_0 : (i == 1 ? rol_light_dir_1 : (i == 2 ? rol_light_dir_2 : rol_light_dir_3));
}

vec4 rol_light_color(int i) {
	return i == 0 ? rol_light_color_0 : (i == 1 ? rol_light_color_1 : (i == 2 ? rol_light_color_2 : rol_light_color_3));
}

// Godot space <-> game space (the x mirror, TMesh.ToGodot)
vec3 rol_game(vec3 v) {
	return vec3(-v.x, v.y, v.z);
}

// mul(World, pos): model space -> game space world position (the file data is used as it is, see TMesh)
vec4 rol_world(mat4 model_matrix, vec4 pos) {
	return vec4(rol_game((model_matrix * pos).xyz), 1.0);
}

// Shaderglobals.fx RGBToHSV / HSVToRGB
vec3 RGBToHSV(vec3 rgb) {
	vec3 hsv = vec3(0.0);
	float min_val = min(min(rgb.x, rgb.y), rgb.z);
	float max_val = max(max(rgb.x, rgb.y), rgb.z);
	float delta = max_val - min_val;
	hsv.z = max_val;
	if (delta != 0.0) {
		hsv.y = delta / max_val;
		vec3 del_rgb = (((vec3(max_val) - rgb) / 6.0) + (delta / 2.0)) / delta;
		if (rgb.x == max_val) hsv.x = del_rgb.z - del_rgb.y;
		else if (rgb.y == max_val) hsv.x = (1.0 / 3.0) + del_rgb.x - del_rgb.z;
		else if (rgb.z == max_val) hsv.x = (2.0 / 3.0) + del_rgb.y - del_rgb.x;
		if (hsv.x < 0.0) hsv.x += 1.0;
		if (hsv.x > 1.0) hsv.x -= 1.0;
	}
	return hsv;
}

vec3 HSVToRGB(vec3 hsv) {
	vec3 rgb = vec3(hsv.z);
	if (hsv.y != 0.0) {
		float var_h = hsv.x * 6.0;
		float f = fract(var_h);
		float p = hsv.z * (1.0 - hsv.y);
		float q = hsv.z * (1.0 - hsv.y * f);
		float t = hsv.z * (1.0 - hsv.y * (1.0 - f));
		if (var_h < 1.0) rgb = vec3(hsv.z, t, p);
		else if (var_h < 2.0) rgb = vec3(q, hsv.z, p);
		else if (var_h < 3.0) rgb = vec3(p, hsv.z, t);
		else if (var_h < 4.0) rgb = vec3(p, q, hsv.z);
		else if (var_h < 5.0) rgb = vec3(t, p, hsv.z);
		else if (var_h < 6.0) rgb = vec3(hsv.z, p, q);
		else rgb = vec3(hsv.z, t, p);
	}
	return rgb;
}

// Shaderglobals.fx SphereMap (game space normal)
vec2 SphereMap(vec3 Normal) {
	return vec2(atan(Normal.x, Normal.z) / (2.0 * PI) + 0.5, (asin(-Normal.y) / PI + 0.5));
}

// Exact inverse of the sRGB encoding Godot applies to the final linear image.
vec3 rol_to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

#ifdef ROL_SKINNING
// BoneTransforms[MAX_BONES]: TSkin.ComputeAnimatedMatrices (CombinedMatrix * BoneSpaceOffsetMatrix), file space.
uniform mat4 bone_transforms[66];
#endif

#block custom_methods
#endblock

void vertex() {
	vec3 SmoothedNormal = CUSTOM2.xyz;
#ifdef ROL_SKINNING
	// Standardshader.fx SKINNING: skinning = sum of BoneWeights[i] * BoneTransforms[BoneIndices[i]] (after the morph
	// targets, which Godot's blend shapes add before this stage); position and normal through it.
	mat4 skinning = CUSTOM0.x * bone_transforms[int(CUSTOM1.x)] + CUSTOM0.y * bone_transforms[int(CUSTOM1.y)]
		+ CUSTOM0.z * bone_transforms[int(CUSTOM1.z)] + CUSTOM0.w * bone_transforms[int(CUSTOM1.w)];
	VERTEX = mat3(skinning) * VERTEX + skinning[3].xyz;
	NORMAL = mat3(skinning) * NORMAL;
	SmoothedNormal = mat3(skinning) * SmoothedNormal;
#endif
	// SMOOTHED_NORMAL: world space (WorldInverseTranspose), then game space for the blocks
	SmoothedNormal = rol_game(normalize(MODEL_NORMAL_MATRIX * normalize(SmoothedNormal)));
	// pos: the model space vertex after morphs and skinning; Worldposition = mul(World, pos) in game space
	vec4 pos = vec4(VERTEX, 1.0);
	#block vs_worldposition
	vec4 Worldposition = rol_world(MODEL_MATRIX, pos);
	#endblock
	world_position = rol_game(Worldposition.xyz);
	smoothed_normal = rol_game(SmoothedNormal);
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world_position, 1.0));
	// Forward path: Halfway = normalize(normalize(CameraPosition - WorldPosition) + DirectionalLightDir) per vertex
	forward_halfway = normalize(normalize(CAMERA_POSITION_WORLD - world_position) + rol_light_dir_0);
	#block after_vertexshader
	#endblock
}

void fragment() {
	// the original's shader constants (Shaderglobals.fx), Godot space: CameraLeft = the camera's screen left
	vec3 CameraPosition = CAMERA_POSITION_WORLD;
	vec3 CameraLeft = -INV_VIEW_MATRIX[0].xyz;
	vec3 CameraUp = INV_VIEW_MATRIX[1].xyz;
	vec4 pso_Color = vec4(0.0);
	#block pixelshader_diffuse
	#ifdef DIFFUSETEXTURE
	pso_Color = texture(diffuse_texture, UV);
	#else
	pso_Color = vec4(0.5, 0.5, 0.5, 1.0);
	#endif
	#endblock
	if (replacement_color.a > 0.0) pso_Color.rgb = mix(pso_Color.rgb, replacement_color.rgb, replacement_color.a);
	if (use_alpha) pso_Color.a *= alpha;
	if (alpha_test_ref > 0.0 && pso_Color.a - alpha_test_ref < 0.0) discard;
	#ifdef MATERIALTEXTURE
	vec4 Material = texture(material_texture, UV);
	#endif
	vec3 Normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	#ifdef GBUFFER
	// G-buffer (DRAW_MATERIAL, DRAW_NORMAL): what the deferred light pass reads
	#ifdef MATERIAL
	#ifndef MATERIALTEXTURE
	vec4 pso_MaterialBuffer = vec4(specular_intensity, specular_power / 255.0, specular_tint, shading_reduction);
	#else
	vec4 pso_MaterialBuffer = vec4(specular_intensity * Material.r, max(Material.g, specular_power / 255.0), specular_tint * Material.b, max(Material.a, shading_reduction));
	#endif
	#else
	#ifndef MATERIALTEXTURE
	vec4 pso_MaterialBuffer = vec4(0.0);
	#else
	vec4 pso_MaterialBuffer = vec4(0.0, 0.0, 0.0, Material.a);
	#endif
	#endif
	vec4 pso_NormalBuffer = vec4(Normal, length(CameraPosition - world_position));
	#else
	// Forward (effects stage): one directional light (DirectionalLightDir / DirectionalLightColor)
	vec3 LightIntensity = rol_light_count > 0
		? clamp(dot(Normal, rol_light_dir_0), 0.0, 1.0) * rol_light_color_0.rgb * rol_light_color_0.a : vec3(0.0);
	#ifdef MATERIAL
	#ifdef MATERIALTEXTURE
	float fw_specular_tint = Material.b;
	float fw_specular_power = max(Material.g * 255.0, specular_power) + 1.0;
	float fw_specular_intensity = Material.r * specular_intensity;
	float fw_shading_reduction = max(Material.a, shading_reduction);
	#else
	float fw_specular_tint = specular_tint;
	float fw_specular_power = specular_power;
	float fw_specular_intensity = specular_intensity;
	float fw_shading_reduction = shading_reduction;
	#endif
	vec3 Specular = mix(rol_light_color_0.rgb, pso_Color.rgb, fw_specular_tint);
	Specular *= pow(clamp(dot(Normal, normalize(forward_halfway)), 0.0, 1.0), fw_specular_power);
	Specular *= fw_specular_intensity;
	pso_Color.rgb = pso_Color.rgb * mix(LightIntensity + rol_ambient, vec3(1.0), fw_shading_reduction) + Specular * LightIntensity;
	#else
	#ifdef MATERIALTEXTURE
	pso_Color.rgb = pso_Color.rgb * mix(LightIntensity + rol_ambient, vec3(1.0), Material.a);
	#else
	pso_Color.rgb = pso_Color.rgb * (LightIntensity + rol_ambient);
	#endif
	#endif
	#endif

	#block color_adjustment
	if (color_adjustment) {
		pso_Color.rgb = RGBToHSV(pso_Color.rgb);
		if (absolute_color_adjustment) {
			pso_Color.rgb = mix(pso_Color.rgb, hsv_offset, absolute_hsv);
			pso_Color.rgb = mix(pso_Color.rgb, vec3(abs(fract(pso_Color.r + hsv_offset.r)), clamp(pso_Color.gb + hsv_offset.gb, 0.0, 1.0)), 1.0 - absolute_hsv);
		} else {
			pso_Color.rgb = vec3(abs(fract(pso_Color.r + hsv_offset.r)), clamp(pso_Color.gb + hsv_offset.gb, 0.0, 1.0));
		}
		pso_Color.rgb = HSVToRGB(pso_Color.rgb);
	}
	#endblock

	#block after_pixelshader
	#endblock

	vec3 result = pso_Color.rgb;
	#ifdef GBUFFER
	// DeferredDirectionalAmbientLight: clip(Color.a - 0.001) leaves the pixel unlit (background shows through);
	// per light (the first 4 enabled) Lambert + Blinn specular, power g * 255 + 1
	if (pso_Color.a < 0.001) discard;
	vec3 light_normal = pso_NormalBuffer.xyz;
	vec3 light_intensity = vec3(0.0);
	vec3 specular = vec3(0.0);
	vec3 to_camera = normalize(CameraPosition - world_position);
	for (int i = 0; i < rol_light_count; i++) {
		vec3 dir = rol_light_dir(i);
		vec4 light_color = rol_light_color(i);
		vec3 halfway = normalize(to_camera + dir);
		light_intensity += clamp(dot(light_normal, dir), 0.0, 1.0) * light_color.rgb * light_color.a;
		specular += mix(light_color.rgb, pso_Color.rgb, pso_MaterialBuffer.b) * pow(clamp(dot(light_normal, halfway), 0.0, 1.0), pso_MaterialBuffer.g * 255.0 + 1.0) * pso_MaterialBuffer.r;
	}
	result = pso_Color.rgb * mix(light_intensity + rol_ambient, vec3(1.0), pso_MaterialBuffer.a) + specular * light_intensity;
	#endif
	ALBEDO = rol_to_linear(result);
	#ifdef ROL_ALPHA
	ALPHA = clamp(pso_Color.a, 0.0, 1.0);
	#endif
}
