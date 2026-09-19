// Port of Graphics/Effects/Shader/HideAndGlow.fx (TMeshEffectHideAndGlow): blocks for TShader.Compose. The mask
// (variable texture 3, red) marks the parts that glow (first timeline, hag_overshoot) and hide (second timeline,
// hag_visibility): masked parts glow in the glow stage and fade in the glow color elsewhere.
#block custom_parameters
  #inherited
  uniform float hag_overshoot;
  uniform vec3 hag_color;
  uniform float hag_is_glow_stage;
  uniform float hag_visibility;
#endblock

#block after_pixelshader
  #inherited
  #ifdef DIFFUSETEXTURE
  {
    float hag_mask_color = textureLod(variable_texture_3, UV, 0.0).r;

    #ifdef GBUFFER
      #ifdef DRAW_MATERIAL
        pso_MaterialBuffer.a += hag_overshoot * hag_mask_color;
      #endif
    #endif
    pso_Color.a = mix(pso_Color.a, hag_overshoot, hag_is_glow_stage * hag_mask_color);
    pso_Color.rgb = mix(pso_Color.rgb, hag_color, hag_overshoot * (1.0 - hag_is_glow_stage) * hag_mask_color);

    // hide in glow stage
    if (1.0 - hag_mask_color + hag_overshoot * hag_is_glow_stage * hag_mask_color + 1.0 - hag_is_glow_stage - 0.001 < 0.0) discard;
    // hide in world stage
    if (1.0 - hag_mask_color + hag_visibility * (1.0 - hag_is_glow_stage) * hag_mask_color + hag_is_glow_stage - 0.8 < 0.0) discard;
  }
  #endif
#endblock
