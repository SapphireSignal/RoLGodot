// Port of the terrain's draw (Engine.Terrain.pas TTerrain.Render): Standardshader.fx with the flags DIFFUSETEXTURE,
// TEXTURETRANSFORM (applied to the UVs on the CPU), NORMALMAPPING, MATERIAL, MATERIALTEXTURE, LIGHTING, rendered into
// the G-buffer and lit by DeferredDirectionalAmbientLight.fx. Constants: Specularpower 0, Specularintensity 1,
// Shadingreduction = TTerrain.ShadingReduction, Speculartint never set for this shader (0). Gamma space like
// standard_shader.gdshaderinc (docs/assets.md "Shading"). Samplers: linear + mipmaps, clamp.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

global uniform vec3 rol_ambient;
global uniform int rol_light_count;
global uniform vec3 rol_light_dir_0;
global uniform vec3 rol_light_dir_1;
global uniform vec3 rol_light_dir_2;
global uniform vec3 rol_light_dir_3;
global uniform vec4 rol_light_color_0;
global uniform vec4 rol_light_color_1;
global uniform vec4 rol_light_color_2;
global uniform vec4 rol_light_color_3;

uniform sampler2D diffuse_texture : filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_texture : filter_linear_mipmap, repeat_disable;
// argb = (Shading Reduction, Specularintensity, Specularpower, Specular Tinting): r intensity, g power, b tint, a SR
uniform sampler2D material_texture : filter_linear_mipmap, repeat_disable;
uniform float specular_intensity = 1.0;
uniform float specular_power = 0.0;
uniform float specular_tint = 0.0;
uniform float shading_reduction = 0.0;

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 world_tangent;
varying vec3 world_binormal;

vec3 rol_light_dir(int i) {
	return i == 0 ? rol_light_dir_0 : (i == 1 ? rol_light_dir_1 : (i == 2 ? rol_light_dir_2 : rol_light_dir_3));
}

vec4 rol_light_color(int i) {
	return i == 0 ? rol_light_color_0 : (i == 1 ? rol_light_color_1 : (i == 2 ? rol_light_color_2 : rol_light_color_3));
}

vec3 rol_to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	// The mesh is built in world space (identity model matrix); the vectors are the world ones already.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
	world_tangent = TANGENT;
	world_binormal = CUSTOM0.xyz;
}

void fragment() {
	vec4 color = texture(diffuse_texture, UV);
	vec4 material = texture(material_texture, UV);
	// NORMALMAPPING: float3x3(Tangent, Normal, Binormal) rows, texture normal = .rbg * 2 - 1
	vec3 normal = normalize(world_normal);
	vec3 texture_normal = texture(normal_texture, UV).rbg * 2.0 - 1.0;
	normal = normalize(texture_normal.x * normalize(world_tangent) + texture_normal.y * normal
		+ texture_normal.z * normalize(world_binormal));
	// DRAW_MATERIAL with MATERIAL + MATERIALTEXTURE
	vec4 mb = vec4(specular_intensity * material.r, max(material.g, specular_power / 255.0), specular_tint * material.b,
		max(material.a, shading_reduction));
	if (color.a < 0.001) discard;
	vec3 light_intensity = vec3(0.0);
	vec3 specular = vec3(0.0);
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - world_position);
	for (int i = 0; i < rol_light_count; i++) {
		vec3 dir = rol_light_dir(i);
		vec4 light_color = rol_light_color(i);
		vec3 halfway = normalize(to_camera + dir);
		light_intensity += clamp(dot(normal, dir), 0.0, 1.0) * light_color.rgb * light_color.a;
		specular += mix(light_color.rgb, color.rgb, mb.b) * pow(clamp(dot(normal, halfway), 0.0, 1.0), mb.g * 255.0 + 1.0) * mb.r;
	}
	ALBEDO = rol_to_linear(color.rgb * mix(light_intensity + rol_ambient, vec3(1.0), mb.a) + specular * light_intensity);
	// the glow camera (TPostEffectManager, the camera without layer 20): black, only the depth the glow is tested against
	if ((CAMERA_VISIBLE_LAYERS & 524288u) == 0u) ALBEDO = vec3(0.0);
}
