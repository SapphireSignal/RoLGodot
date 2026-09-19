// Port of Graphics/Effects/Shader/SpawnShader_Green.fx (TMeshEffectSpawn, green): blocks for TShader.Compose.
// Worldposition and object_position are game space. powlerp sits in custom_methods (the original defines it in the
// defines block, HLSL allows a function there; Godot's defines block comes before the uniforms, which is fine too,
// but a function there would precede RGBToHSV & co., so it moves).
#block defines
  #inherited
  #define FALL_HEIGHT 4.0
  #define SPHERE_RADIUS 0.15
  #define GLOW_STRENGTH 0.8
  #define FALL_FINISH 0.1
  #define SEED_FINISH 0.4
  #define GROW_FINISH 0.7
#endblock

#block custom_methods
  #inherited
  float powlerp(float x) {
    float t = x - 1.0;
    return t * t * t * t * t + 1.0;
  }
#endblock

#block custom_parameters
  #inherited
  uniform float progress;
  uniform float glow;
  uniform vec3 object_position;
  uniform vec3 fading_color;
#endblock

#block vs_worldposition
  #inherited
  {
  vec3 center = object_position;
  center.y += SPHERE_RADIUS * 2.0;
  vec3 between = Worldposition.xyz - center;
  float fall_factor = clamp(progress / FALL_FINISH, 0.0, 1.0);
  float seed_factor = clamp((progress - FALL_FINISH) / (SEED_FINISH - FALL_FINISH), 0.0, 1.0);
  float grow_factor = clamp((progress - SEED_FINISH) / (GROW_FINISH - SEED_FINISH), 0.0, 1.0);

  vec3 between_factor = vec3(1.0 / mix(length(between) / (SPHERE_RADIUS * mix(2.0, 3.0, seed_factor)), 1.0, powlerp(grow_factor)));
  float spawn_factor = powlerp(fall_factor) * 0.5 + 0.5;
  float squash_factor = (1.0 - sin(PI * clamp(seed_factor * 3.0, 0.0, 1.0))) * 0.3 + 0.7;
  Worldposition.xyz = center + between * between_factor * spawn_factor * vec3(1.0 / squash_factor, squash_factor, 1.0 / squash_factor);

  Worldposition.y += mix(FALL_HEIGHT, 0.0, fall_factor);
  }
#endblock

#block after_pixelshader
  #inherited
  {
  float glow_factor = 1.0 - clamp((progress - GROW_FINISH) / (1.0 - GROW_FINISH), 0.0, 1.0);
  float seed_factor = clamp((progress - FALL_FINISH) / (SEED_FINISH - FALL_FINISH), 0.0, 1.0);
  pso_Color.rgb = mix(vec3(0.49, 0.38, 0.27), pso_Color.rgb, seed_factor);
  #ifdef GBUFFER
    pso_MaterialBuffer.a = mix(pso_MaterialBuffer.a, 1.0, glow_factor);
  #else
    pso_Color.a = mix(pso_Color.a, pso_Color.a + glow_factor * GLOW_STRENGTH, glow * seed_factor);
  #endif
  }
#endblock
