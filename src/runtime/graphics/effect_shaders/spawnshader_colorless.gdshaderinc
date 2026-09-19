// Port of Graphics/Effects/Shader/SpawnShader_Colorless.fx (TMeshEffectSpawn, colorless): blocks for TShader.Compose.
// Worldposition and object_position are game space.
#block defines
  #inherited
  #define NEEDWORLD
  #define SMOOTHED_NORMAL
  #define BREAK_START 0.4
  #define BREAK_LENGTH 0.15
  #define SQUEEZE_START 0.4
  #define SQUEEZE_LENGTH 0.30
  #define COLOR_START 0.4
  #define COLOR_LENGTH 0.6
#endblock

#block custom_parameters
  #inherited
  uniform vec3 object_position;
  uniform float progress;
  uniform float model_height;
#endblock

#block vs_worldposition
  #inherited
  {
  float melt_factor = clamp((progress - BREAK_START) / BREAK_LENGTH, 0.0, 1.0);
  Worldposition.y -= (model_height * 1.1) * (1.0 - melt_factor);

  float squeeze_factor = clamp((progress - SQUEEZE_START) / SQUEEZE_LENGTH, 0.0, 1.0);
  vec3 relative_position = Worldposition.xyz - object_position;
  relative_position *= 0.35 * vec3(1, -1, 1) * -sin(squeeze_factor * PI * 2.0) + 1.0;
  Worldposition.xyz = object_position + relative_position;
  }
#endblock

#block after_pixelshader
  #inherited
  {
  float color_factor = clamp((progress - COLOR_START) / COLOR_LENGTH, 0.0, 1.0);
  pso_Color.rgb = mix(vec3(0.24, 1.0, 1.0), pso_Color.rgb, color_factor);
  #ifdef GBUFFER
    pso_MaterialBuffer.a = mix(pso_MaterialBuffer.a, 1.0, 1.0 - color_factor);
  #endif
  }
#endblock
