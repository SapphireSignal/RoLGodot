// Port of Graphics/Effects/Shader/SpawnShader_White.fx (TMeshEffectSpawn, white): blocks for TShader.Compose.
#block defines
  #inherited
  #define NEEDWORLD
  #define FADE_LENGTH 0.4
  #define CLIP_SPEED 3.14
  #define GLOW_STRENGTH 0.4
#endblock

#block custom_parameters
  #inherited
  uniform float progress;
  uniform float model_height;
  uniform float glow;
  uniform vec3 fading_color;
#endblock

#block after_pixelshader
  #inherited
  {
  #ifdef DIFFUSETEXTURE
    float mask_color = texture(variable_texture_3, UV).r;
  #else
    float mask_color = 1.0;
  #endif
  float relative_height = world_position.y / model_height;
  float progress_threshold = (1.0 - (progress * (1.0 + FADE_LENGTH)));

  if (-((1.0 - progress * CLIP_SPEED) - relative_height) < 0.0) discard;

  float value = 1.0 - clamp(-(progress_threshold - relative_height) / FADE_LENGTH + mask_color, 0.0, 1.0);

  pso_Color.rgb = mix(pso_Color.rgb, fading_color, value);
  #ifdef GBUFFER
    pso_MaterialBuffer.a = mix(pso_MaterialBuffer.a, 1.0, value);
  #else
    pso_Color.a = mix(pso_Color.a, pso_Color.a + value * GLOW_STRENGTH, glow);
  #endif
  }
#endblock
