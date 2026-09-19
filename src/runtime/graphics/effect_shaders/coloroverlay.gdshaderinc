// Port of Graphics/Effects/Shader/ColorOverlay.fx (TMeshEffectColorOverlay, TMeshEffectTint): blocks for
// TShader.Compose, see t_shader.gd.
#block custom_parameters
  #inherited
  uniform vec4 co_color;
  uniform bool co_additive;
#endblock

#block after_pixelshader
  if (co_additive)
    pso_Color.rgb += co_color.rgb * co_color.a;
  else
    pso_Color.rgb = mix(pso_Color.rgb, co_color.rgb, co_color.a);
  #inherited
#endblock
