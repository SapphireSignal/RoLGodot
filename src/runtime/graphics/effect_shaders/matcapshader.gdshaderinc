// Port of Engine/Shader/MatcapShader.fx (TMeshEffectMatcap): blocks for TShader.Compose, see t_shader.gd.
// Mirror-free: CameraLeft / CameraUp / normals are all Godot space, their dot products are the original's.
#block custom_methods
  #inherited
  // Converts a Normal to a texturecoordinate for a screen aligned half sphere with only a normal 2D-Texture.
  vec2 MatcapMap(vec3 Normal, vec3 CameraLeft, vec3 CameraUp) {
    float x = dot(CameraLeft, Normal);
    float y = dot(CameraUp, Normal);
    return vec2(x, y) * -0.5 + 0.5;
  }
#endblock

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

  #ifdef GBUFFER
    vec3 reflection_vector = normalize(pso_NormalBuffer.xyz);
  #else
    vec3 reflection_vector = normalize(Normal);
  #endif
  vec4 reflected_color = textureLod(variable_texture_2, MatcapMap(reflection_vector, CameraLeft, CameraUp), 0.0).rgba;

  pso_Color.rgb = mix(pso_Color.rgb, mix(reflected_color.rgb, pso_Color.rgb * reflected_color.rgb, tinting), metal);
  pso_Color.a *= reflected_color.a;
  }

  #inherited
#endblock
