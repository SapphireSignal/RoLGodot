// Port of the original's mesh shading: Engine/Shader/Standardshader.fx (MegaPixelShader) and, for opaque meshes, the
// deferred light pass Engine/Shader/DeferredDirectionalAmbientLight.fx that lights the G-buffer it writes.
// Included by the variants TMesh builds (render modes differ: cull mode, blending). Read docs/assets.md.
//
// The original renders in gamma space (no sRGB textures or targets): every value here is a raw 0..1 texture or
// color value, and the result is handed to Godot as srgb_to_linear(result) so Godot's final linear -> sRGB output
// step gives back exactly the original's value. Lighting is computed here (the material is unshaded), from the
// rol_* global shader parameters that TLightManager sets (docs/assets.md, "Lighting").

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

uniform bool has_diffuse_texture = false;
uniform sampler2D diffuse_texture : filter_linear_mipmap, repeat_enable;
uniform bool has_material_texture = false;
// argb = (Shading Reduction, Specularintensity, Specularpower, Specular Tinting): r intensity, g power, b tint, a SR
uniform sampler2D material_texture : filter_linear_mipmap, repeat_enable;
uniform bool has_material_settings = false; // TRawMesh.HasMaterialSettings: the MATERIAL shader flag
uniform float specular_intensity = 0.0;
uniform float specular_power = 128.0;
uniform float specular_tint = 1.0;
uniform float shading_reduction = 0.0;      // ShadingReduction, or ShadingReductionOverride when that is 0
uniform bool forward_path = false;          // HasAlpha: drawn in the effects stage, lit directly (no G-buffer)
uniform bool use_alpha = false;             // ALPHA flag
uniform float alpha = 1.0;
uniform float alpha_test_ref = 0.0;         // > 0: ALPHATEST, clip(color.a - ref)
uniform vec4 replacement_color = vec4(0.0); // COLOR_REPLACEMENT when a > 0
uniform bool color_adjustment = false;      // COLORADJUSTMENT
uniform bool absolute_color_adjustment = false;
uniform vec3 hsv_offset = vec3(0.0);
uniform vec3 absolute_hsv = vec3(0.0);

varying vec3 world_position;
varying vec3 forward_halfway;

vec3 rol_light_dir(int i) {
	return i == 0 ? rol_light_dir_0 : (i == 1 ? rol_light_dir_1 : (i == 2 ? rol_light_dir_2 : rol_light_dir_3));
}

vec4 rol_light_color(int i) {
	return i == 0 ? rol_light_color_0 : (i == 1 ? rol_light_color_1 : (i == 2 ? rol_light_color_2 : rol_light_color_3));
}

// Shaderglobals.fx RGBToHSV / HSVToRGB
vec3 rgb_to_hsv(vec3 rgb) {
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

vec3 hsv_to_rgb(vec3 hsv) {
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

// Standardshader.fx block color_adjustment
vec3 adjust_color(vec3 color) {
	if (!color_adjustment) return color;
	vec3 hsv = rgb_to_hsv(color);
	if (absolute_color_adjustment) {
		hsv = mix(hsv, hsv_offset, absolute_hsv);
		hsv = mix(hsv, vec3(abs(fract(hsv.x + hsv_offset.x)), clamp(hsv.yz + hsv_offset.yz, 0.0, 1.0)), 1.0 - absolute_hsv);
	} else {
		hsv = vec3(abs(fract(hsv.x + hsv_offset.x)), clamp(hsv.yz + hsv_offset.yz, 0.0, 1.0));
	}
	return hsv_to_rgb(hsv);
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

void vertex() {
#ifdef ROL_SKINNING
	// Standardshader.fx SKINNING: skinning = sum of BoneWeights[i] * BoneTransforms[BoneIndices[i]] (after the morph
	// targets, which Godot's blend shapes add before this stage); position and normal through it.
	mat4 skinning = CUSTOM0.x * bone_transforms[int(CUSTOM1.x)] + CUSTOM0.y * bone_transforms[int(CUSTOM1.y)]
		+ CUSTOM0.z * bone_transforms[int(CUSTOM1.z)] + CUSTOM0.w * bone_transforms[int(CUSTOM1.w)];
	VERTEX = mat3(skinning) * VERTEX + skinning[3].xyz;
	NORMAL = mat3(skinning) * NORMAL;
#endif
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Forward path: Halfway = normalize(normalize(CameraPosition - WorldPosition) + DirectionalLightDir) per vertex
	forward_halfway = normalize(normalize(CAMERA_POSITION_WORLD - world_position) + rol_light_dir_0);
}

void fragment() {
	// block pixelshader_diffuse
	vec4 color = has_diffuse_texture ? texture(diffuse_texture, UV) : vec4(0.5, 0.5, 0.5, 1.0);
	if (replacement_color.a > 0.0) color.rgb = mix(color.rgb, replacement_color.rgb, replacement_color.a);
	if (use_alpha) color.a *= alpha;
	if (alpha_test_ref > 0.0 && color.a - alpha_test_ref < 0.0) discard;
	vec4 material = has_material_texture ? texture(material_texture, UV) : vec4(0.0);
	vec3 normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 result;
	if (!forward_path) {
		// G-buffer: the color gets its adjustment before lighting; material buffer as DRAW_MATERIAL writes it
		color.rgb = adjust_color(color.rgb);
		vec4 mb = vec4(0.0);
		if (has_material_settings) {
			mb = has_material_texture
				? vec4(specular_intensity * material.r, max(material.g, specular_power / 255.0), specular_tint * material.b, max(material.a, shading_reduction))
				: vec4(specular_intensity, specular_power / 255.0, specular_tint, shading_reduction);
		} else if (has_material_texture) {
			mb = vec4(0.0, 0.0, 0.0, material.a);
		}
		// DeferredDirectionalAmbientLight: clip(Color.a - 0.001) leaves the pixel unlit (background shows through)
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
		result = color.rgb * mix(light_intensity + rol_ambient, vec3(1.0), mb.a) + specular * light_intensity;
	} else {
		// Forward (effects stage): one directional light (DirectionalLightDir / DirectionalLightColor)
		vec3 light_intensity = rol_light_count > 0
			? clamp(dot(normal, rol_light_dir_0), 0.0, 1.0) * rol_light_color_0.rgb * rol_light_color_0.a : vec3(0.0);
		if (has_material_settings) {
			float tint = has_material_texture ? material.b : specular_tint;
			float power = has_material_texture ? max(material.g * 255.0, specular_power) + 1.0 : specular_power;
			float intensity = has_material_texture ? material.r * specular_intensity : specular_intensity;
			float reduction = has_material_texture ? max(material.a, shading_reduction) : shading_reduction;
			vec3 spec = mix(rol_light_color_0.rgb, color.rgb, tint);
			spec *= pow(clamp(dot(normal, normalize(forward_halfway)), 0.0, 1.0), power) * intensity;
			result = color.rgb * mix(light_intensity + rol_ambient, vec3(1.0), reduction) + spec * light_intensity;
		} else if (has_material_texture) {
			result = color.rgb * mix(light_intensity + rol_ambient, vec3(1.0), material.a);
		} else {
			result = color.rgb * (light_intensity + rol_ambient);
		}
		result = adjust_color(result);
	}
	ALBEDO = rol_to_linear(result);
	#ifdef ROL_ALPHA
	ALPHA = clamp(color.a, 0.0, 1.0);
	#endif
}
