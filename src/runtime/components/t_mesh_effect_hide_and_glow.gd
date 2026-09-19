class_name TMeshEffectHideAndGlow
extends TMeshEffectWithTimekeys
## Port of TMeshEffectHideAndGlow (BaseConflict.EntityComponents.Client.Visuals.pas:652, implementation :6245): two
## timelines, the first the glow (hag_overshoot), the second the visibility (hag_visibility), both for the parts a
## mask texture marks (HideAndGlow.fx, the texture in variable texture 3).

const ORDER_VALUE := 9997


func Create(Duration = null, TextureFilename = null):
	super(Duration)
	SetTexture(TextureFilename)
	InitShader(PATH_GRAPHICS_SHADER + "HideAndGlow.fx")
	FOrderValue = ORDER_VALUE
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	return super(TMeshEffectHideAndGlow.new().Create(0, "") if Effect == null else Effect)


func SetUpShader(CurrentShader, Stage: int, PassIndex: int) -> void:
	super(CurrentShader, Stage, PassIndex)
	CurrentShader.SetShaderConstant("hag_is_glow_stage", 1.0 if Stage == TMesh.RS_GLOW else 0.0)
	CurrentShader.SetShaderConstant("hag_overshoot", CurrentValue())
	var GlowColor := RColor(TMeshEffectSpawn.GLOW_COLOR_MAP[FColorIdentity])
	CurrentShader.SetShaderConstant("hag_color", Vector3(GlowColor.r, GlowColor.g, GlowColor.b))
	CurrentShader.SetShaderConstant("hag_visibility", CurrentValue(1))
