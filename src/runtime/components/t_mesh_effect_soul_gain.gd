class_name TMeshEffectSoulGain
extends TMeshEffectWithTimekeys
## Port of TMeshEffectSoulGain (BaseConflict.EntityComponents.Client.Visuals.pas:602, implementation :6919): a ghostly
## hull (SoulGain.fx) in one own pass of the effects stage, growing by Radius over the timeline and fading out, in the
## soul color (default $FFBFFDED).

const ORDER_VALUE := 9999

var FRadius := 0.3
## an RColor (the Color method below shadows the type's constructor in this class)
var FColor = RColor(0xFFBFFDED)


func Create(Duration = null, _Param1 = null):
	super(Duration)
	FColor = RColor(0xFFBFFDED)
	FRadius = 0.3
	FNeedOwnPass = [TMesh.RS_EFFECTS]
	FOwnPasses = 1
	InitShader(PATH_GRAPHICS_SHADER + "SoulGain.fx")
	FOrderValue = ORDER_VALUE
	return self


func Radius(Radius_ = null):
	FRadius = RParam.ToSingle(Radius_)
	return self


func Color(Color_ = null):
	FColor = RColor(int(Color_))
	return self


func Clone(Effect: TMeshEffect) -> TMeshEffect:
	var Result := super(TMeshEffectSoulGain.new().Create(0) if Effect == null else Effect)
	Result.FColor = FColor
	Result.FRadius = FRadius
	return Result


func SetUpShader(CurrentShader, Stage: int, PassIndex: int) -> void:
	super(CurrentShader, Stage, PassIndex)
	CurrentShader.SetShaderConstant("soul_gain_progress", CurrentValue())
	CurrentShader.SetShaderConstant("soul_gain_radius", FRadius)
	CurrentShader.SetShaderConstant("soul_color", Vector4(FColor.r, FColor.g, FColor.b, FColor.a))
