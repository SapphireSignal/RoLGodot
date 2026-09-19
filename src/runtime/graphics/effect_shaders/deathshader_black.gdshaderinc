// Port of Graphics/Effects/Shader/DeathShader_Black.fx (TUnitDecayManagerComponent, black): blocks for
// TShader.Compose. Noise eats the dying mesh away while it darkens to the void grey. The noise takes the game space
// world position (psin.WorldPosition). The shadow_clip_test block waits for the shadow mapping.
#block defines
  #define NEEDWORLD
#endblock

#block custom_parameters
  #inherited
  uniform float dsb_progress;
#endblock

#block custom_methods
  #inherited

  float dsb_powlerp(float x) {
    float t = x - 1.0;
    return t * t * t + 1.0;
  }

  float dsb_hash(float n) {
    return fract(sin(n) * 43758.5453);
  }

  // The dsb_noise function returns a value in the range 0.0 -> 1.0
  float dsb_noise(vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);

    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0 + 113.0 * p.z;

    return mix(mix(mix(dsb_hash(n + 0.0), dsb_hash(n + 1.0), f.x),
                   mix(dsb_hash(n + 57.0), dsb_hash(n + 58.0), f.x), f.y),
               mix(mix(dsb_hash(n + 113.0), dsb_hash(n + 114.0), f.x),
                   mix(dsb_hash(n + 170.0), dsb_hash(n + 171.0), f.x), f.y), f.z);
  }
#endblock

#block after_pixelshader
  #inherited
  {
  float progress = dsb_powlerp(dsb_progress);
  if ((dsb_noise(rol_game(world_position) * 12.0)) - progress - 0.001 < 0.0) discard;

  progress = clamp(progress * 4.0, 0.0, 1.0);
  pso_Color.rgb = mix(pso_Color.rgb, vec3(0.15, 0.15, 0.19), progress);
  #ifdef GBUFFER
    pso_MaterialBuffer.rg = vec2(1.0 - progress);
    pso_MaterialBuffer.b = progress;
    pso_MaterialBuffer.a = progress;
  #endif
  }
#endblock
