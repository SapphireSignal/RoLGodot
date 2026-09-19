// Port of Graphics/Effects/Shader/SpawnShader_Black.fx (TMeshEffectSpawn, black): blocks for TShader.Compose.
// Worldposition and SmoothedNormal are game space.
#block defines
  #inherited
  #define NEEDWORLD
  #define SMOOTHED_NORMAL
  #define MELT_FINISH 0.6
  #define MELT_LENGTH 3.0
  #define COLOR_START 0.3
  #define COLOR_LENGTH 0.2
  #define WOBBLE_FINISH 0.9
  #define WOBBLE_COUNT 4.0*2.0*3.141
#endblock

#block custom_parameters
  #inherited
  uniform float progress;
  uniform float model_height;
#endblock

#block vs_worldposition
  #inherited
  {
  float melt_factor = clamp(progress / MELT_FINISH, 0.0, 1.0);
  melt_factor = clamp(melt_factor / (1.0 - clamp(Worldposition.y / model_height, 0.0, 1.0)), 0.0, 1.0);

  Worldposition.y = mix(-MELT_LENGTH * model_height, Worldposition.y, melt_factor);

  float wobble_factor = 1.0 - clamp(progress / WOBBLE_FINISH, 0.0, 1.0);
  vec3 wobble_lead_vector = vec3(sin(wobble_factor * WOBBLE_COUNT), 0.0, cos(wobble_factor * WOBBLE_COUNT));
  float wobble_strength = clamp(dot(wobble_lead_vector, SmoothedNormal) * 0.1 + 0.01, 0.0, 1.0);
  Worldposition.xyz += wobble_lead_vector * wobble_strength * wobble_factor;
  }
#endblock

#block after_pixelshader
  #inherited
  {
  float color_factor = clamp((progress - COLOR_START) / COLOR_LENGTH, 0.0, 1.0);
  pso_Color.rgb = mix(vec3(0.15, 0.15, 0.19), pso_Color.rgb, color_factor);
  }
#endblock
