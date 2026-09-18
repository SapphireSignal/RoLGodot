// Port of the vegetation draw (Engine.Vegetation.pas TVegetationManager.RawRender): Standardshader.fx with the
// Vegetationshader.fx blocks (wind), flags LIGHTING, DIFFUSETEXTURE, ALPHATEST (ref 0.5, Alpha 1), cull none without
// CULLNONE (back faces keep the front normal), no material: the deferred light pass gives color * (light + ambient).
// Every part of the maps' vegetation is AlphaTested and not FlipCullNormals, so all of it uses this "grass shader".
// Gamma space like standard_shader.gdshaderinc. Palms are MultiMesh instances; grass tufts one mesh in world space.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

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

uniform sampler2D diffuse_texture : filter_linear_mipmap, repeat_enable;  // tsColor: auto, wrap
uniform float time = 0.0;                         // TimeManager.GetFloatingTimestamp / 1000
uniform vec3 wind_direction = vec3(0.70710677, 0.0, 0.70710677);  // game space

varying vec3 world_normal;

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
	// pre_vertexshader: the original's vertices are in world space (World = identity); wind is computed there.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 game = vec3(-world.x, world.y, world.z);
	vec4 wind = CUSTOM0;
	float x = time / 15.0 + wind.y + dot(wind_direction, game) / 10.0 * wind.x;
	float supersin = cos(x * PI) * cos(x * 3.0 * PI) * cos(x * 5.0 * PI) * cos(x * 7.0 * PI) + sin(x * 25.0 * PI) * 0.1;
	vec3 offset = supersin * wind.z * wind_direction;
	vec3 godot_offset = vec3(-offset.x, offset.y, offset.z);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * godot_offset;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec4 color = texture(diffuse_texture, UV);
	if (color.a - 0.5 < 0.0) discard;  // ALPHATEST: clip(Color.a - AlphaTestRef)
	vec3 normal = normalize(world_normal);
	vec3 light_intensity = vec3(0.0);
	for (int i = 0; i < rol_light_count; i++) {
		vec4 light_color = rol_light_color(i);
		light_intensity += clamp(dot(normal, rol_light_dir(i)), 0.0, 1.0) * light_color.rgb * light_color.a;
	}
	ALBEDO = rol_to_linear(color.rgb * (light_intensity + rol_ambient));
}
