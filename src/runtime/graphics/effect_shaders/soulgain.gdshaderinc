// Port of Graphics/Effects/Shader/SoulGain.fx (TMeshEffectSoulGain): blocks for TShader.Compose, drawn in an own pass
// of the effects stage: a hull pushed out along the smoothed normals, in the soul color, fading towards the parts
// facing the camera and over the effect's time. SmoothedNormal is game space in the vertex blocks; the pixel block
// takes the camera direction in the same space as smoothed_normal (Godot's).
#block defines
  #inherited
  #define NEEDWORLD
  #define SMOOTHED_NORMAL
#endblock

#block custom_parameters
  #inherited
  uniform float soul_gain_progress;
  uniform float soul_gain_radius;
  uniform vec4 soul_color;
#endblock

#block vs_worldposition
  #inherited
  // push boundaries outside so the unit has a exploding ghostly hull
  Worldposition.xyz += SmoothedNormal * soul_gain_radius * soul_gain_progress;
#endblock

#block after_pixelshader
  #inherited
  {
  float soul_gain_camera_angle = abs(dot(normalize(smoothed_normal), CameraDirection));
  soul_gain_camera_angle = 1.0 - soul_gain_camera_angle;
  pso_Color.rgb = soul_color.rgb;
  pso_Color.a *= clamp(soul_gain_camera_angle, 0.0, 1.0) * (1.0 - soul_gain_progress) * soul_color.a;
  }
#endblock
