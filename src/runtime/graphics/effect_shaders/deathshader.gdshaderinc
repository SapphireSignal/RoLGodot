// Port of Graphics/Effects/Shader/DeathShader.fx (TUnitDecayManagerComponent, every color but black): blocks for
// TShader.Compose. The dying mesh swells, flies apart along its smoothed normals and flattens while noise eats it
// away, the rest glowing in the color's glow color. Worldposition and SmoothedNormal are game space in the vertex
// blocks; the noise takes the game space world position (psin.WorldPosition). The shadow_clip_test block waits for
// the shadow mapping.
#block defines
  #define NEEDWORLD
  #define SMOOTHED_NORMAL
  #define EXPLOSION_SIZE 0.5
#endblock

#block custom_parameters
  #inherited
  uniform float explosion_progress;
  uniform vec3 explosion_color;
#endblock

#block custom_methods
  #inherited

  float powlerp(float x) {
    float t = x - 1.0;
    return t * t * t + 1.0;
  }

  float hash(float n) {
    return fract(sin(n) * 43758.5453);
  }

  // The noise function returns a value in the range 0.0 -> 1.0
  float noise(vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);

    f = f * f * (3.0 - 2.0 * f);
    float n = p.x + p.y * 57.0 + 113.0 * p.z;

    return mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f.x),
                   mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
               mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
                   mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
  }
#endblock

#block vs_worldposition
  pos.xz *= 1.0 + explosion_progress * 0.5;
  vec4 Worldposition = rol_world(MODEL_MATRIX, pos);
  {
  float t = explosion_progress - 1.0;
  t = t * t * t + 1.0;
  Worldposition.xyz += SmoothedNormal * EXPLOSION_SIZE * t;
  Worldposition.y *= clamp(1.0 - explosion_progress * 1.5, 0.0, 1.0) + 0.1;
  }
#endblock

#block after_pixelshader
  #inherited
  {
  float progress = powlerp(explosion_progress);
  if ((noise(rol_game(world_position) * 12.0)) - progress - 0.001 < 0.0) discard;

  vec3 SmoothedNormal = normalize(smoothed_normal);
  vec3 look_dir = normalize(world_position - CameraPosition);
  float edge_angle = abs(dot(SmoothedNormal, look_dir)) * progress;
  pso_Color.rgb = mix(pso_Color.rgb, mix(explosion_color, vec3(1.0, 1.0, 1.0), edge_angle), clamp(progress * 4.0, 0.0, 1.0));
  #ifdef GBUFFER
    pso_MaterialBuffer.rg = vec2(1.0 - progress);
    pso_MaterialBuffer.b = progress;
    pso_MaterialBuffer.a = 1.0;
  #endif
  }
#endblock
