shader_type canvas_item;
render_mode unshaded;
// Port of Engine/Shader/PosteffectGaussianBlur.fx (without BILATERAL): one pass of TTextureBlur.RenderBlur, a 1D blur
// along (pixelwidth, pixelheight) with the kernel (Shaderglobals.fx GAUSS_<KERNELSIZE>[_ADDITIVE], set by
// TPostEffectManager), times intensity, alpha 1. The last pass of an additive blur is blended One / One onto the scene:
// here it reads the scene (base_texture) and adds itself, both clamped like the 8 bit targets.

uniform sampler2D color_texture : filter_linear, repeat_disable;
uniform float pixelwidth = 0.0;
uniform float pixelheight = 0.0;
uniform float intensity = 1.0;
uniform float kernel[6];
uniform int kernel_length = 6;  // REAL_KERNELSIZE = KERNELSIZE + 2
uniform bool add_to_base = false;
uniform sampler2D base_texture : filter_nearest, repeat_disable;

void fragment() {
	vec3 color = texture(color_texture, UV).rgb * kernel[0];
	for (int i = 1; i < kernel_length; i++) {
		vec2 tex_offset = float(i) * vec2(pixelwidth, pixelheight);
		color += texture(color_texture, UV + tex_offset).rgb * kernel[i];
		color += texture(color_texture, UV - tex_offset).rgb * kernel[i];
	}
	color *= intensity;
	if (add_to_base) {
		color = texture(base_texture, UV).rgb + clamp(color, 0.0, 1.0);
	}
	COLOR = vec4(color, 1.0);
}
