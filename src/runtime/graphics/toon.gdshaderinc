// The Toon post effect's two ends in the world shaders (standard, terrain, vegetation): see docs/assets.md, "Post
// effects", and TPostEffectManager.
//
// G-buffer camera: TPostEffectManager's third camera (GBufferViewport, HDR) lacks the cull layer bit GBUFFER_LAYER_BIT
// (layer 19, 262144u) every other camera has; ROL_GBUFFER_CAMERA tests it. Under it the world stage (what the original
// draws into its G-buffer in rsWorld) writes rol_gbuffer_encode instead of its color, everything else is not drawn.
//
// Toon (PosteffectToon.fx with NO_LIGHTING, the stack's ttBorder): the original draws it over the scene after the
// deferred light pass (rsWorldPostEffects), before water, alpha meshes and particles (rsEffects). The port applies it
// in the world stage's own fragments (rol_toon): the visible opaque fragment of a pixel is what the scene holds there,
// and the pass reads nothing else of the scene.
global uniform bool rol_toon_enabled;
global uniform sampler2D rol_toon_border;          // BlurredScene2: the border blur's result
global uniform vec3 rol_toon_border_color;
global uniform float rol_toon_border_gradient;
global uniform float rol_toon_border_threshold;   // BorderShadingReductionThreshold

#define ROL_GBUFFER_CAMERA ((CAMERA_VISIBLE_LAYERS & 262144u) == 0u)

// The G-buffer the border pass reads, packed into the three channels an opaque draw can write (the HDR viewport keeps
// them raw at 16 bit float, the original's normal buffer format): r = the distance to the camera (NormalBuffer.w),
// g / b = the normal octahedral-encoded into 0..1; g + 2 when the 8 bit shading reduction (MaterialBuffer.a) is at
// least the threshold (all the border pass uses of it), b + 2 marks a drawn pixel (the cleared buffer is 0).
vec3 rol_gbuffer_encode(vec3 normal, float depth, float shading_reduction) {
	vec3 n = normal / max(abs(normal.x) + abs(normal.y) + abs(normal.z), 1e-20);
	vec2 o = n.xy;
	if (n.z < 0.0) {
		o = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
	}
	float sr = round(clamp(shading_reduction, 0.0, 1.0) * 255.0) / 255.0;
	float flag = sr >= rol_toon_border_threshold ? 1.0 : 0.0;
	return vec3(depth, o.x * 0.5 + 0.5 + 2.0 * flag, o.y * 0.5 + 0.5 + 2.0);
}

// PosteffectToon.fx on the scene color (gamma space, the 8 bit scene: clamped) and alpha of this pixel: factor =
// pow(saturate(border), border_gradient), lerp(border_color, color, factor); clip(Color.a - 0.1 + (1 - factor))
// keeps the scene as it was (SwitchScene copied it into the target first).
vec3 rol_toon(vec3 color, float alpha, vec2 fragcoord) {
	if (!rol_toon_enabled) {
		return color;
	}
	float black_border = clamp(texelFetch(rol_toon_border, ivec2(fragcoord), 0).r, 0.0, 1.0);
	float factor = pow(black_border, rol_toon_border_gradient);
	if (clamp(alpha, 0.0, 1.0) - 0.1 + (1.0 - factor) < 0.0) {
		return color;
	}
	return mix(rol_toon_border_color, clamp(color, 0.0, 1.0), factor);
}
