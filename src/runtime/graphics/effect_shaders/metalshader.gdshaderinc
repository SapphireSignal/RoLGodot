// Port of Engine/Shader/MetalShader.fx (TMeshEffectMetal): blocks for TShader.Compose, see t_shader.gd.
// SphereMap takes the reflection in game space (rol_game): its atan of x is not mirror-free.
#block color_adjustment
  {
  #ifdef MATERIAL
    #ifdef GBUFFER
      float metal = pso_MaterialBuffer.r;
      float tinting = pso_MaterialBuffer.b;
      pso_MaterialBuffer.rgb = vec3(0.0);
    #else
      float metal = specular_intensity;
      float tinting = specular_tint;
      #ifdef MATERIALTEXTURE
        metal *= Material.r;
        tinting *= Material.b;
      #endif
    #endif
  #else
    float metal = 0.0;
    float tinting = 0.0;
  #endif

  vec3 look_dir = normalize(world_position - CameraPosition);
  #ifdef GBUFFER
    vec3 reflection_vector = normalize(reflect(look_dir, normalize(pso_NormalBuffer.xyz)));
  #else
    vec3 reflection_vector = normalize(reflect(look_dir, normalize(Normal)));
  #endif
  vec3 reflected_color = textureLod(variable_texture_2, SphereMap(rol_game(reflection_vector)), 0.0).rgb;

  pso_Color.rgb = mix(pso_Color.rgb, mix(reflected_color, pso_Color.rgb * (reflected_color * 1.5 + 0.25), tinting), metal);
  }

  #inherited
#endblock
