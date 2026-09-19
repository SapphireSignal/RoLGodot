class_name TMeshEffectGlow
extends TMeshEffectWithTimekeys
## Port of TMeshEffectGlow (BaseConflict.EntityComponents.Client.Visuals.pas:637, implementation :6155): full glow on
## the mesh (GlowOvershoot.fx), the timeline's current value as the overshoot: in the glow stage it raises the glow,
## elsewhere it blends the albedo to the glow color of the entity's color identity (or a fixed one). A mesh without a
## glow texture gets its color's (glow override).

const ORDER_VALUE := 9998

var FFixedColorIdentity := false
var FFixedColor := 0


func Create(Duration = null, _Param1 = null):
	FUseGlowOverride = true
	super(Duration)
	InitShader(PATH_GRAPHICS_SHADER + "GlowOvershoot.fx")
	FOrderValue = ORDER_VALUE
	return self


func FixedColorIdentity(ColorIdentity_ = null):
	FFixedColorIdentity = true
	FFixedColor = int(ColorIdentity_)
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	var Result := super(TMeshEffectGlow.new().Create(0) if Effect == null else Effect)
	Result.FFixedColorIdentity = FFixedColorIdentity
	Result.FFixedColor = FFixedColor
	return Result


func SetUpShader(CurrentShader, Stage: int, PassIndex: int) -> void:
	super(CurrentShader, Stage, PassIndex)
	CurrentShader.SetShaderConstant("go_is_glow_stage", 1.0 if Stage == TMesh.RS_GLOW else 0.0)
	CurrentShader.SetShaderConstant("go_overshoot", CurrentValue())
	var Identity := FFixedColor if FFixedColorIdentity else FColorIdentity
	var GlowColor := RColor(TMeshEffectSpawn.GLOW_COLOR_MAP[Identity])
	CurrentShader.SetShaderConstant("go_color", Vector3(GlowColor.r, GlowColor.g, GlowColor.b))
