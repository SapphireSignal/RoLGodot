shader_type canvas_item;
render_mode unshaded;
// Port of Engine/Shader/PosteffectUnsharpMasking.fx: the scene plus its difference to the blurred scene (edges
// overshoot).

uniform sampler2D color_texture : filter_nearest, repeat_disable;   // the scene
uniform sampler2D normal_texture : filter_nearest, repeat_disable;  // the blurred scene
uniform float amount = 0.7;

void fragment() {
	vec3 scene = texture(color_texture, UV).rgb;
	vec3 blurred_scene = texture(normal_texture, UV).rgb;
	vec3 difference = scene - blurred_scene;
	// add the differences between blurred scene and scene to highlight edges with contrast overshooting
	COLOR = vec4(scene + difference * amount, 1.0);
}
