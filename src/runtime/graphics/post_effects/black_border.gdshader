shader_type canvas_item;
render_mode unshaded;
// Port of Engine/Shader/PosteffectBlackBorder.fx: one pass of the Toon effect's border blur (TPostEffectToon.Render).
// A 1D blur along (pixelwidth, pixelheight) of the border buffer that only takes the samples whose G-buffer depth is
// within range of the center's and whose normal faces the same half space (dot >= normalbias * |n|): where the
// surface jumps, the buffer darkens. Where a sample has a shading reduction >= border_threshold the pass keeps the
// input (lerp with the count of such samples, which can pass 1: lerp extrapolates, the 8 bit target clamps).
// Point sampling, clamped. The G-buffer comes from the G-buffer camera, packed by toon.gdshaderinc
// (rol_gbuffer_encode); the input of the first pass is the buffer cleared white ($00FFFFFF).

#define KERNELSIZE 3

uniform sampler2D color_texture : filter_nearest, repeat_disable;
uniform bool clear_input = false;  // the input is the cleared BlurredScene2: white
uniform sampler2D gbuffer_texture : filter_nearest, repeat_disable;
uniform float pixelwidth = 0.0;
uniform float pixelheight = 0.0;
uniform float range = 1.0;
uniform float normalbias = 0.0;
uniform float border_threshold = 1.0;

// The original's NormalTexture (xyz normal, w distance to the camera) and MaterialBuffer.w (shading reduction, only its
// step against border_threshold is used) from the packed G-buffer: r depth, g octahedral x + 2 * (sr >= threshold),
// b octahedral y + 2 when drawn. Cleared pixels (nothing drawn): all 0.
vec4 normal_depth(vec2 uv, out float threshold_step) {
	vec3 g = texture(gbuffer_texture, uv).rgb;
	threshold_step = 0.0;
	if (g.b < 1.5) {
		return vec4(0.0);
	}
	threshold_step = g.g >= 1.5 ? 1.0 : 0.0;
	vec2 o = (vec2(g.g - 2.0 * threshold_step, g.b - 2.0) - 0.5) * 2.0;
	vec3 n = vec3(o, 1.0 - abs(o.x) - abs(o.y));
	if (n.z < 0.0) {
		n.xy = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
	}
	return vec4(normalize(n), g.r);
}

vec3 border_color(vec2 uv) {
	return clear_input ? vec3(1.0) : texture(color_texture, uv).rgb;
}

void fragment() {
	float weight[KERNELSIZE] = {0.312, 0.2269, 0.1176};
	vec3 original_color = border_color(UV);
	vec3 color = original_color * weight[0];
	float threshold_check;
	vec4 normaldepth = normal_depth(UV, threshold_check);
	for (int i = 1; i < KERNELSIZE; i++) {
		vec2 offset = float(i) * vec2(pixelwidth, pixelheight);
		vec2 sample_coord = UV + offset;
		float sample_step;
		vec4 sample_normaldepth = normal_depth(sample_coord, sample_step);
		float rangecheck = abs(normaldepth.w - sample_normaldepth.w) < range ? 1.0 : 0.0;
		rangecheck *= dot(normaldepth.xyz, sample_normaldepth.xyz) >= normalbias * length(normaldepth.xyz) ? 1.0 : 0.0;
		threshold_check += sample_step;
		color += border_color(sample_coord) * weight[i] * rangecheck;

		sample_coord -= 2.0 * offset;
		sample_normaldepth = normal_depth(sample_coord, sample_step);
		rangecheck = abs(normaldepth.w - sample_normaldepth.w) < range ? 1.0 : 0.0;
		rangecheck *= dot(normaldepth.xyz, sample_normaldepth.xyz) >= normalbias * length(normaldepth.xyz) ? 1.0 : 0.0;
		threshold_check += sample_step;
		color += border_color(sample_coord) * weight[i] * rangecheck;
	}
	color = mix(color, original_color, threshold_check);
	COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}
