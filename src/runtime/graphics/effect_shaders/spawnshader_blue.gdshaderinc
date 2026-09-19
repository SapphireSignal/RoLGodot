// Port of Graphics/Effects/Shader/SpawnShader_Blue.fx (TMeshEffectSpawn, blue): blocks for TShader.Compose. Drawn in
// own passes (BLUE_PASSES, pass_progress = pass / (passes - 1)) that hide the mesh's normal drawing. Its
// vs_worldposition replaces the base block (no #inherited): it spins and scales the model space vertex, then
// declares Worldposition itself. Its custom_methods has no #inherited either, as written.
#block defines
  #inherited
  #define NEEDWORLD
  #define GLOW_STRENGTH 0.1
  #define GLOW_FINISH 1.0
  #define SCALE_OFFSET 0.5
  #define SCALE_FINISH 0.083
  #define ROT_OFFSET 0.166
  #define ROT_FINISH 0.666
#endblock

#block custom_methods
  float cos_lerp(float x) {
    float t = (1.0 + cos(x * 3.141)) / 2.0;
    return t < 0.5 ? 4.0 * t * t * t : (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0;
  }
#endblock

#block custom_parameters
  #inherited
  uniform float model_height;
  uniform float progress;
  uniform float glow;
  uniform float pass_progress;
  uniform vec3 fading_color;
#endblock

#block vs_worldposition
  float rot_factor = clamp(progress / ROT_FINISH - ROT_OFFSET, 0.0, 1.0);
  float rotation = cos_lerp(1.0 - clamp((rot_factor * 1.0 - 0.4 * pass_progress) * 1.3, 0.0, 1.0)) * 2.0 * 3.141592;
  // HLSL float3x3(rows) * v; GLSL mat3 takes columns: the transpose, so v * mat3 = mul(rot_mat, v)
  mat3 rot_mat = mat3(vec3(cos(rotation), 0.0, sin(rotation)), vec3(0.0, 1.0, 0.0), vec3(-sin(rotation), 0.0, cos(rotation)));
  vec3 temp = pos.xyz;
  temp = temp * rot_mat;
  float scale_progress = clamp(progress / SCALE_FINISH - SCALE_OFFSET, 0.0, 1.0);
  pos.xyz = temp * (scale_progress + sin(scale_progress * 3.14159));
  pos.y += 50.0 * model_height * pow((1.0 - clamp(progress / 0.5 - ROT_OFFSET, 0.0, 1.0)), 5.0);
  vec4 Worldposition = rol_world(MODEL_MATRIX, pos);
#endblock

#block after_pixelshader
  #inherited
  {
  float glow_factor = (1.0 - clamp(progress / GLOW_FINISH - ROT_OFFSET, 0.0, 1.0));
  pso_Color.rgb = mix(pso_Color.rgb, fading_color, (1.0 - glow) * glow_factor * 0.7);
  glow_factor *= (pass_progress < 0.01 ? 1.0 : 0.0);
  #ifdef GBUFFER
    pso_MaterialBuffer.a = mix(pso_MaterialBuffer.a, 1.0, glow_factor);
  #else
    pso_Color.a = mix(pso_Color.a, pso_Color.a / 20.0 + glow_factor * GLOW_STRENGTH, glow);
  #endif
  }
#endblock
