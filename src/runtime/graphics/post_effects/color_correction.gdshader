shader_type canvas_item;
render_mode unshaded;
// Port of Engine/Shader/PosteffectColorCorrection.fx: levels (shadows, lights) and a gamma (midtones).

uniform sampler2D color_texture : filter_nearest, repeat_disable;
uniform float shadows = 0.0;
uniform float midtones = 1.0;
uniform float lights = 1.0;

void fragment() {
	vec3 scene_color = texture(color_texture, UV).rgb;
	// rescale linear color scale
	scene_color = clamp((scene_color - shadows) / lights, 0.0, 1.0);
	// gamma correct
	scene_color = pow(scene_color, vec3(midtones));
	COLOR = vec4(scene_color, 1.0);
}
