// Port of Engine/Shader/Watershader.fx as TWaterSurface.Render (Engine.Water.pas) draws it in the effects stage with
// DEFERRED_SHADING, REFLECTIONS, REFRACTION and CAUSTICS (the maps' surfaces have a caustics texture, no sky texture).
// The original ray-marches through the G-buffer's position buffer and samples the lit scene; the port gets both from
// Godot's depth and screen textures (world positions reconstructed from depth, the scene color back to gamma space).
// All shading math runs in game space (Godot x negated back), so the original's formulas are used unchanged; only
// screen projections use Godot's matrices. The output alpha is 1 like the original's (blending on, alpha 1).
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_always;

global uniform int rol_light_count;
global uniform vec3 rol_light_dir_0;   // -Direction of the first light, Godot space
global uniform vec4 rol_light_color_0;

uniform sampler2D wave_vs : filter_linear, repeat_enable;           // tsMaterial in the VS: linear, wrap, lod 0
uniform sampler2D wave_ps : filter_linear_mipmap, repeat_enable;    // tsColor: auto (linear), wrap
uniform sampler2D caustics_texture : filter_linear, repeat_enable;  // tsVariable3, sampled at lod 0
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;  // RenderContext.Scene
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;    // -> PositionBuffer
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, filter_nearest, repeat_disable;

uniform float time_tick = 0.0;          // TimeManager.GetFloatingTimestamp / 1000
uniform float wave_height = 1.2;        // WaveHeightVS
uniform float size = 90.0;              // Size, SizeVS
uniform vec2 texture_normalization = vec2(0.025);  // GeometrySize / 2000
uniform vec3 water_color = vec3(0.0);
uniform vec3 sky_color = vec3(0.0);
uniform float transparency_value = 0.0; // Transparency
uniform float specular_power = 40.0;
uniform float specular_intensity = 0.8;
uniform float roughness = 0.68;
uniform float fresnel_offset = 0.2;
uniform float refraction_index = 0.75;
uniform float depth_transparency_range = 1.5;
uniform float refraction_steps = 14.0;
uniform float refraction_step_length = 10.0;
uniform vec4 min_max = vec4(0.0);       // Position.XZ -/+ GeometrySize / 2 (game space)
uniform float color_extinction_range = 150.0;
uniform float caustics_range = 15.0;
uniform float caustics_scale = 1.0;

varying vec3 game_position;   // WorldPosition, game space
varying vec3 game_normal;     // the VS normal, game space

vec3 to_game(vec3 v) {
	return vec3(-v.x, v.y, v.z);
}

vec3 rol_to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec3 rol_to_gamma(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float speed = time_tick / 10.0 / 3.0 / size / max(texture_normalization.x, texture_normalization.y);
	vec2 scale = 0.45 * size * texture_normalization;
	vec2 tex = (UV + vec2(0.4, 1.0) * speed) * scale;
	vec4 center = textureLod(wave_vs, tex, 0.0);
	tex = (UV - vec2(0.4, 1.0) * speed) * scale;
	vec4 center2 = textureLod(wave_vs, tex, 0.0);
	float lift = mix(center.a, center2.a, 0.5) * wave_height - wave_height * 0.5;
	VERTEX.y += lift;
	world.y += lift;
	game_position = to_game(world);
	float height_norm = 1.2 / max(wave_height, 0.0001);
	vec3 n = normalize(mix(center.gbr * 2.0 - 1.0, center2.gbr * 2.0 - 1.0, 0.5));
	n.y *= height_norm;
	game_normal = normalize(n);
	// the effects stage is not in the G-buffer (toon.gdshaderinc): not drawn under the G-buffer camera. A shader that
	// writes POSITION anywhere must write it always (Godot then takes it for every camera).
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if ((CAMERA_VISIBLE_LAYERS & 262144u) == 0u) POSITION = vec4(2.0, 2.0, 2.0, 1.0);
}

// The G-buffer position at a screen coordinate, game space. Where nothing was drawn (the reverse-z depth buffer is
// still cleared to 0) the original's position buffer holds its clear value: (0, 0, 0).
vec3 scene_position(vec2 uv, mat4 inv_projection, mat4 inv_view) {
	float depth = textureLod(depth_texture, uv, 0.0).r;
	if (depth <= 0.0) {
		return vec3(0.0);
	}
	vec4 view = inv_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	return to_game((inv_view * vec4(view.xyz, 1.0)).xyz);
}

vec3 scene_color(vec2 uv) {
	return rol_to_gamma(textureLod(screen_texture, uv, 0.0).rgb);
}

// mul(mul(Projection, View), raypos) -> screen coordinate (before any clamping).
vec2 project(vec3 game_point, mat4 view_matrix, mat4 projection) {
	vec4 clip = projection * (view_matrix * vec4(to_game(game_point), 1.0));
	return (clip.xy / clip.w) * 0.5 + 0.5;
}

void fragment() {
	vec3 camera = to_game(CAMERA_POSITION_WORLD);
	vec2 texel = 1.0 / VIEWPORT_SIZE;
	float speed = time_tick / 10.0 / 3.0 / size / max(texture_normalization.x, texture_normalization.y);
	vec2 scale = 0.45 * size * texture_normalization;

	vec3 Normal = normalize(game_normal);
	vec3 Tangent = normalize(cross(vec3(1.0, -0.1, 0.0), Normal));
	vec3 Binormal = normalize(cross(Normal, Tangent));

	vec2 tex = (UV + (normalize(vec2(1.0, 0.6)) * speed * 1.35)) * scale * 4.0;
	vec3 normal = normalize(texture(wave_ps, tex).gbr * 2.0 - 1.0);
	tex = (UV - (normalize(vec2(1.0, 0.6)) * speed * 1.35)) * scale * 3.5;
	vec3 normal2 = normalize(texture(wave_ps, tex).gbr * 2.0 - 1.0);
	normal = normalize(mix(vec3(0.0, 1.0, 0.0), normalize(normal + normal2), roughness));
	// mul(float3x3(Tangent, Normal, Binormal), normal): the rows dotted with the vector
	normal = normalize(vec3(dot(Tangent, normal), dot(Normal, normal), dot(Binormal, normal)));

	vec3 view = normalize(game_position - camera);
	float fresnel = clamp(mix(pow(1.0 - dot(normal, -view), 5.0), 1.0, fresnel_offset), 0.0, 1.0);

	vec2 screen_tex;
	vec3 initial_scenepos = scene_position(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec3 scenepos = initial_scenepos;
	vec3 color_of_scene = scene_color(SCREEN_UV);
	vec3 raydirection;
	vec3 raypos;

	// REFRACTION
	raydirection = normalize(refract(view, normal, refraction_index)) * refraction_step_length;
	raypos = game_position + raydirection;
	for (float i = 0.0; i < refraction_steps; ++i) {
		screen_tex = clamp(project(raypos, VIEW_MATRIX, PROJECTION_MATRIX), 0.0, 1.0) - vec2(0.0, texel.y);
		scenepos = scene_position(screen_tex, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		if (distance(scenepos, camera) <= distance(raypos, camera)) {
			raypos -= raydirection;
			raydirection *= 0.5;
		}
		raypos += raydirection;
	}
	// due precision errors take 4 times upper target screen pixel to sample always behind obstacles
	screen_tex = clamp(clamp(project(raypos, VIEW_MATRIX, PROJECTION_MATRIX), 0.0, 1.0) - vec2(0.0, 4.0 * texel.y), 0.0, 1.0);
	scenepos = scene_position(screen_tex, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	color_of_scene = scene_color(screen_tex);

	float depth = distance(game_position, scenepos);
	float transparency = mix(0.0, 1.0 - transparency_value, clamp((depth - 0.1) / depth_transparency_range, 0.0, 1.0));

	// color extinction
	vec3 extinction = clamp(water_color, 0.0, 1.0);
	vec3 resulting_color = mix(color_of_scene, water_color, depth / color_extinction_range / extinction);

	vec3 reflection = reflect(view, normal);
	// REFLECTIONS
	raydirection = reflection * depth;
	raypos = game_position + raydirection;
	float hit = 0.0;
	for (float j = 0.0; j < refraction_steps; ++j) {
		screen_tex = project(raypos, VIEW_MATRIX, PROJECTION_MATRIX);
		if (any(lessThan(screen_tex, vec2(0.0))) || any(greaterThan(screen_tex, vec2(1.0)))) {
			break;
		}
		vec3 current_scenepos = scene_position(screen_tex, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
		if (distance(current_scenepos, camera) <= distance(raypos, camera)) {
			hit = 1.0;
			if (distance(current_scenepos, raypos) < 0.1) break;
			raypos -= raydirection;
			raydirection *= 0.5;
		}
		raypos += raydirection;
	}
	vec3 sky = sky_color;
	sky = mix(sky, scene_color(clamp(screen_tex, 0.0, 1.0)), hit);
	resulting_color = mix(resulting_color, sky, fresnel);

	// CAUSTICS
	vec3 view_normal = textureLod(normal_roughness_texture, SCREEN_UV, 0.0).xyz * 2.0 - 1.0;
	float scene_normal_y = (INV_VIEW_MATRIX * vec4(view_normal, 0.0)).y;
	vec2 caustic_tex = (initial_scenepos.xz - min_max.xy) / (min_max.zw - min_max.xy);
	vec2 temo_tex = (caustic_tex + (vec2(0.4, 1.0) * speed)) * scale * caustics_scale;
	float caustic1 = textureLod(caustics_texture, temo_tex, 0.0).a;
	temo_tex = (caustic_tex + (vec2(-0.4, -1.0) * speed)) * scale * caustics_scale;
	float caustic2 = textureLod(caustics_texture, temo_tex, 0.0).a;
	float resulting_caustic = clamp(transparency * caustic1 * caustic2 * (1.0 - ((game_position.y - scenepos.y) / caustics_range)) * scene_normal_y, 0.0, 1.0);
	resulting_color = resulting_color + resulting_caustic;

	// borders
	resulting_color = mix(color_of_scene, resulting_color, transparency);

	// specular
	vec3 light_dir = rol_light_count > 0 ? to_game(rol_light_dir_0) : vec3(0.0);
	vec3 light_color = rol_light_count > 0 ? rol_light_color_0.rgb : vec3(0.0);
	vec3 halfway = normalize(-view + light_dir);
	float specular = clamp(pow(clamp(dot(normal, halfway), 0.0, 1.0), specular_power) - 0.8, 0.0, 1.0) / 0.2;
	resulting_color = mix(resulting_color, light_color, specular * specular_intensity * transparency);

	ALBEDO = rol_to_linear(resulting_color);
	ALPHA = 1.0;
	// the glow camera (TPostEffectManager, the camera without layer 20): black, only the depth the glow is tested against
	if ((CAMERA_VISIBLE_LAYERS & 524288u) == 0u) ALBEDO = vec3(0.0);
}
