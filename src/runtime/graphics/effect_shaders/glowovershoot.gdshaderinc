// Port of Graphics/Effects/Shader/GlowOvershoot.fx (TMeshEffectGlow): blocks for TShader.Compose. In the glow stage
// the overshoot raises the glow alpha; elsewhere it tints the albedo to the glow color and raises the shading
// reduction (unlit).
#block custom_parameters
  #inherited
  uniform float go_overshoot;
  uniform vec3 go_color;
  uniform float go_is_glow_stage;
#endblock

#block color_adjustment
  #ifdef GBUFFER
    #ifdef DRAW_MATERIAL
      pso_MaterialBuffer.a += go_overshoot;
    #endif
  #endif
  pso_Color.a += go_overshoot * go_is_glow_stage;
  pso_Color.rgb = mix(pso_Color.rgb, go_color, go_overshoot * (1.0 - go_is_glow_stage));

  #inherited
#endblock
